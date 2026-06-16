"""
Router de autenticación con soporte de múltiples roles.

Endpoints:
- POST /auth/login
- POST /auth/register
- GET  /auth/me
- POST /auth/users          (Admin: crear usuario en la empresa)
- GET  /auth/users          (Admin: listar usuarios)
- PUT  /auth/users/{id}/roles (Admin/HR: asignar roles)
- PUT  /auth/users/{id}     (Admin/HR: editar usuario)
- DELETE /auth/users/{id}   (Admin: desactivar usuario)
"""
from __future__ import annotations

from datetime import timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm, OAuth2PasswordBearer
from pydantic import BaseModel, EmailStr
from slowapi import Limiter
from slowapi.util import get_remote_address
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

limiter = Limiter(key_func=get_remote_address)

from app.database import get_db
from app.models.base import Company, RoleName, User, UserRole
from app.services import auth as auth_service

router = APIRouter(prefix="/auth", tags=["auth"])
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


# ─── Schemas ──────────────────────────────────────────────────────────────────

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserCreate(BaseModel):
    email: EmailStr
    password: str
    full_name: Optional[str] = None
    phone: Optional[str] = None
    position: Optional[str] = None
    company_name: Optional[str] = None   # Solo para el primer registro
    roles: Optional[List[str]] = ["technician"]


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    phone: Optional[str] = None
    position: Optional[str] = None
    is_active: Optional[bool] = None


class RolesUpdate(BaseModel):
    roles: List[str]


class UserOut(BaseModel):
    id: int
    email: str
    full_name: Optional[str]
    phone: Optional[str]
    position: Optional[str]
    company_id: int
    is_active: bool
    roles: List[str]

    class Config:
        from_attributes = True

    @classmethod
    def from_orm_with_roles(cls, user: User) -> "UserOut":
        return cls(
            id=user.id,
            email=user.email,
            full_name=user.full_name,
            phone=user.phone,
            position=user.position,
            company_id=user.company_id,
            is_active=user.is_active,
            roles=[ur.role for ur in user.user_roles],
        )


# ─── Dependencies ─────────────────────────────────────────────────────────────

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    payload = auth_service.verify_token(token)
    user_id = payload.get("sub")
    company_id = payload.get("company_id")
    if not user_id or not company_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token inválido")

    result = await db.execute(
        select(User)
        .options(selectinload(User.user_roles))
        .where(User.id == int(user_id), User.company_id == int(company_id), User.is_active == True)
    )
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Usuario no encontrado o inactivo")
    return user


def require_roles(*allowed_roles: str):
    """Dependency factory: exige que el usuario tenga al menos uno de los roles indicados."""
    async def checker(current_user: User = Depends(get_current_user)) -> User:
        user_roles = [ur.role for ur in current_user.user_roles]
        if not any(r in user_roles for r in allowed_roles):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Acceso restringido. Se requiere uno de: {', '.join(allowed_roles)}"
            )
        return current_user
    return checker


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.post("/login", response_model=TokenResponse)
@limiter.limit("10/minute")
async def login(
    request: Request,
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: AsyncSession = Depends(get_db),
):
    """Autenticación con rate limiting: máx. 10 intentos por minuto por IP."""
    result = await db.execute(
        select(User)
        .options(selectinload(User.user_roles))
        .where(User.email == form_data.username, User.is_active == True)
    )
    user = result.scalars().first()
    if not user or not auth_service.verify_password(form_data.password, user.hashed_password):
        # Mismo mensaje para no revelar si el email existe
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenciales incorrectas",
            headers={"WWW-Authenticate": "Bearer"},
        )

    roles = [ur.role.value if hasattr(ur.role, 'value') else ur.role for ur in user.user_roles]
    token_data = {
        "sub": str(user.id),
        "company_id": str(user.company_id),
        "roles": roles,
    }
    # Token de 60 minutos (configurable por ACCESS_TOKEN_EXPIRE_MINUTES)
    token = auth_service.create_access_token(token_data)
    return {"access_token": token, "token_type": "bearer"}


@router.post("/register", response_model=UserOut, status_code=status.HTTP_201_CREATED)
async def register(payload: UserCreate, db: AsyncSession = Depends(get_db)):
    """Registro del primer usuario de una empresa nueva."""
    existing = await db.execute(select(User).where(User.email == payload.email))
    if existing.scalars().first():
        raise HTTPException(status_code=400, detail="El email ya está registrado")

    company = Company(name=payload.company_name or "Mi Empresa")
    db.add(company)
    await db.flush()

    hashed = auth_service.get_password_hash(payload.password)
    user = User(
        email=payload.email,
        full_name=payload.full_name,
        phone=payload.phone,
        position=payload.position,
        hashed_password=hashed,
        company_id=company.id,
    )
    db.add(user)
    await db.flush()

    # El primer usuario siempre es admin
    user_role = UserRole(user_id=user.id, role=RoleName.admin)
    db.add(user_role)
    await db.commit()
    await db.refresh(user)

    result = await db.execute(
        select(User).options(selectinload(User.user_roles)).where(User.id == user.id)
    )
    user = result.scalars().first()
    return UserOut.from_orm_with_roles(user)


@router.get("/me", response_model=UserOut)
async def me(current_user: User = Depends(get_current_user)):
    return UserOut.from_orm_with_roles(current_user)


@router.get("/users", response_model=List[UserOut])
async def list_users(
    skip: int = 0,
    limit: int = 100,
    current_user: User = Depends(require_roles("admin", "hr")),
    db: AsyncSession = Depends(get_db),
):
    """Lista usuarios de la empresa con paginación (skip/limit)."""
    result = await db.execute(
        select(User)
        .options(selectinload(User.user_roles))
        .where(User.company_id == current_user.company_id)
        .order_by(User.full_name)
        .offset(skip)
        .limit(min(limit, 200))  # máx 200 por página
    )
    users = result.scalars().all()
    return [UserOut.from_orm_with_roles(u) for u in users]


@router.post("/users", response_model=UserOut, status_code=201)
async def create_user(
    payload: UserCreate,
    current_user: User = Depends(require_roles("admin", "hr")),
    db: AsyncSession = Depends(get_db),
):
    existing = await db.execute(select(User).where(User.email == payload.email))
    if existing.scalars().first():
        raise HTTPException(status_code=400, detail="El email ya está registrado")

    hashed = auth_service.get_password_hash(payload.password)
    user = User(
        email=payload.email,
        full_name=payload.full_name,
        phone=payload.phone,
        position=payload.position,
        hashed_password=hashed,
        company_id=current_user.company_id,
    )
    db.add(user)
    await db.flush()

    roles_to_assign = payload.roles or ["technician"]
    for role_str in roles_to_assign:
        try:
            role_enum = RoleName(role_str)
            db.add(UserRole(user_id=user.id, role=role_enum))
        except ValueError:
            pass

    await db.commit()
    result = await db.execute(
        select(User).options(selectinload(User.user_roles)).where(User.id == user.id)
    )
    user = result.scalars().first()
    return UserOut.from_orm_with_roles(user)


@router.put("/users/{user_id}/roles", response_model=UserOut)
async def update_user_roles(
    user_id: int,
    payload: RolesUpdate,
    current_user: User = Depends(require_roles("admin", "hr")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User)
        .options(selectinload(User.user_roles))
        .where(User.id == user_id, User.company_id == current_user.company_id)
    )
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    # Borrar roles actuales y reasignar
    for ur in user.user_roles:
        await db.delete(ur)
    await db.flush()

    for role_str in payload.roles:
        try:
            role_enum = RoleName(role_str)
            db.add(UserRole(user_id=user.id, role=role_enum))
        except ValueError:
            raise HTTPException(status_code=400, detail=f"Rol inválido: {role_str}")

    await db.commit()
    result = await db.execute(
        select(User).options(selectinload(User.user_roles)).where(User.id == user.id)
    )
    user = result.scalars().first()
    return UserOut.from_orm_with_roles(user)


@router.put("/users/{user_id}", response_model=UserOut)
async def update_user(
    user_id: int,
    payload: UserUpdate,
    current_user: User = Depends(require_roles("admin", "hr")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User)
        .options(selectinload(User.user_roles))
        .where(User.id == user_id, User.company_id == current_user.company_id)
    )
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    if payload.full_name is not None:
        user.full_name = payload.full_name
    if payload.phone is not None:
        user.phone = payload.phone
    if payload.position is not None:
        user.position = payload.position
    if payload.is_active is not None:
        user.is_active = payload.is_active

    await db.commit()
    await db.refresh(user)
    result = await db.execute(
        select(User).options(selectinload(User.user_roles)).where(User.id == user.id)
    )
    user = result.scalars().first()
    return UserOut.from_orm_with_roles(user)
