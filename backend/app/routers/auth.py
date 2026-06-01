"""
Router de autenticación: login, register, me.

Endpoints:
- POST /auth/login  (OAuth2PasswordRequestForm)
- POST /auth/register
- GET  /auth/me     (requiere token)

Todos los endpoints protegidos filtran por `company_id` cuando aplica.
"""
from __future__ import annotations

from datetime import timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm, OAuth2PasswordBearer
from pydantic import BaseModel, EmailStr
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.base import Company, User
from app.services import auth as auth_service


router = APIRouter()

# OAuth2 scheme for extracting the Bearer token from requests
# tokenUrl debe corresponder con la ruta de login expuesta en la API
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserCreate(BaseModel):
    email: EmailStr
    password: str
    company_id: Optional[int] = None
    role: Optional[str] = "technician"


class UserOut(BaseModel):
    id: int
    email: EmailStr
    company_id: int
    role: str

    class Config:
        orm_mode = True


async def get_current_user(token: str = Depends(oauth2_scheme), db: AsyncSession = Depends(get_db)) -> User:
    """Dependency que verifica el token y retorna el `User` correspondiente.

    - Valida el JWT usando `auth.verify_token`.
    - Busca al usuario por `sub` y `company_id` contenidos en el token.
    """
    payload = auth_service.verify_token(token)
    user_id = payload.get("sub")
    company_id = payload.get("company_id")
    if user_id is None or company_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token inválido: faltan claims necesarios",
            headers={"WWW-Authenticate": "Bearer"},
        )

    result = await db.execute(select(User).where(User.id == int(user_id), User.company_id == int(company_id)))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Usuario no encontrado")
    return user


@router.post("/auth/login", response_model=TokenResponse)
async def login(form_data: OAuth2PasswordRequestForm = Depends(), db: AsyncSession = Depends(get_db)):
    """Login usando email (form.username) y password.

    Devuelve `access_token` y `token_type`.
    """
    # OAuth2PasswordRequestForm usa `username` para el identificador.
    email = form_data.username
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Credenciales incorrectas")

    if not auth_service.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Credenciales incorrectas")

    # Crear token con claims útiles: sub=user.id y company_id
    access_token_expires = timedelta(minutes=60)
    token_data = {"sub": str(user.id), "company_id": str(user.company_id)}
    access_token = auth_service.create_access_token(token_data, expires_delta=access_token_expires)

    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/auth/register", response_model=UserOut, status_code=status.HTTP_201_CREATED)
async def register(payload: UserCreate, db: AsyncSession = Depends(get_db)):
    """Crea un nuevo usuario. Si `company_id` no se proporciona, crea una Company por defecto.

    La contraseña se guarda como hash usando bcrypt.
    """
    # Verificar email único antes de crear recursos adicionales
    res2 = await db.execute(select(User).where(User.email == payload.email))
    exists = res2.scalars().first()
    if exists:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="El email ya está registrado")

    if payload.company_id is None:
        demo_company = Company(name="Empresa Demo")
        db.add(demo_company)
        await db.flush()
        company_id = demo_company.id
    else:
        res = await db.execute(select(Company).where(Company.id == payload.company_id))
        company = res.scalars().first()
        if not company:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="La compañía indicada no existe")
        company_id = payload.company_id

    hashed = auth_service.get_password_hash(payload.password)
    new_user = User(
        email=payload.email,
        hashed_password=hashed,
        company_id=company_id,
        role=payload.role or "technician",
    )
    db.add(new_user)
    await db.commit()
    await db.refresh(new_user)

    return new_user


@router.get("/auth/me", response_model=UserOut)
async def me(current_user: User = Depends(get_current_user)):
    """Retorna los datos del usuario autenticado.

    Dado que `get_current_user` ya verifica `company_id`, aquí ya está filtrado.
    """
    return current_user
