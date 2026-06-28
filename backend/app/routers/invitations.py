"""
Router de invitaciones a colaboradores.

Endpoints:
  POST /invitations          → Admin envía invitación por email
  GET  /invitations          → Lista invitaciones de la empresa
  POST /invitations/{id}/revoke → Revoca una invitación
  GET  /invitations/{token}  → Valida token (público)
  POST /invitations/{token}/accept → Acepta invitación y crea usuario (público)
"""
from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models.base import Company, RoleName, User, UserRole
from app.models.collaboration import Invitation, InvitationStatus
from app.routers.auth import require_roles
from app.services import auth as auth_service
from app.services.email import send_invitation_email

router = APIRouter(prefix="/invitations", tags=["invitations"])

INVITATION_EXPIRE_DAYS = 7


# ─── Schemas ──────────────────────────────────────────────────────────────────

class InvitationCreate(BaseModel):
    email:      EmailStr
    full_name:  Optional[str] = None
    roles:      List[str] = ["technician"]


class InvitationOut(BaseModel):
    id:         int
    email:      str
    full_name:  Optional[str]
    roles:      List[str]
    status:     str
    expires_at: str
    created_at: str

    class Config:
        from_attributes = True


class InvitationTokenCheck(BaseModel):
    valid:        bool
    email:        Optional[str] = None
    company_name: Optional[str] = None
    roles:        List[str] = []
    expires_at:   Optional[str] = None
    message:      str = ""


class AcceptInvitation(BaseModel):
    password:    str
    full_name:   Optional[str] = None
    phone:       Optional[str] = None
    position:    Optional[str] = None


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _generate_token() -> str:
    return secrets.token_urlsafe(32)


def _parse_roles_csv(roles_csv: Optional[str]) -> List[str]:
    if not roles_csv:
        return []
    return [r.strip() for r in roles_csv.split(",") if r.strip()]


def _to_out(inv: Invitation) -> InvitationOut:
    return InvitationOut(
        id=inv.id,
        email=inv.email,
        full_name=inv.full_name,
        roles=_parse_roles_csv(inv.roles_csv),
        status=inv.status,
        expires_at=inv.expires_at.strftime("%Y-%m-%d %H:%M"),
        created_at=inv.created_at.strftime("%Y-%m-%d %H:%M"),
    )


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.post("", response_model=InvitationOut, status_code=status.HTTP_201_CREATED)
async def create_invitation(
    payload: InvitationCreate,
    current_user: User = Depends(require_roles("admin", "hr")),
    db: AsyncSession = Depends(get_db),
):
    """
    Envía una invitación por email a un colaborador.
    Solo admin y RRHH pueden invitar.
    """
    # Validar que no haya invitación pendiente previa
    existing_inv = await db.execute(
        select(Invitation).where(
            Invitation.email == payload.email,
            Invitation.company_id == current_user.company_id,
            Invitation.status == InvitationStatus.pending.value,
        )
    )
    if existing_inv.scalars().first():
        raise HTTPException(status_code=400, detail="Ya hay una invitación pendiente para este email")

    # Validar roles
    valid_roles = {r.value for r in RoleName}
    for r in payload.roles:
        if r not in valid_roles:
            raise HTTPException(status_code=400, detail=f"Rol inválido: {r}")

    token = _generate_token()
    inv = Invitation(
        company_id=current_user.company_id,
        created_by_id=current_user.id,
        email=payload.email,
        full_name=payload.full_name,
        token=token,
        roles_csv=",".join(payload.roles),
        status=InvitationStatus.pending.value,
        expires_at=datetime.now(timezone.utc) + timedelta(days=INVITATION_EXPIRE_DAYS),
    )
    db.add(inv)
    await db.commit()
    await db.refresh(inv)

    # Cargar info para el email
    company_result = await db.execute(select(Company).where(Company.id == current_user.company_id))
    company = company_result.scalars().first()

    # Enviar email (no bloqueante: si falla, la invitación sigue creada)
    sent = send_invitation_email(
        to_email=payload.email,
        inviter_name=current_user.full_name or current_user.email,
        company_name=company.name if company else "la empresa",
        token=token,
        roles=payload.roles,
    )
    if not sent:
        # No fallamos, pero avisamos
        return _to_out(inv)

    return _to_out(inv)


@router.get("", response_model=List[InvitationOut])
async def list_invitations(
    current_user: User = Depends(require_roles("admin", "hr")),
    db: AsyncSession = Depends(get_db),
):
    """Lista las invitaciones de la empresa."""
    result = await db.execute(
        select(Invitation)
        .where(Invitation.company_id == current_user.company_id)
        .order_by(Invitation.created_at.desc())
    )
    return [_to_out(inv) for inv in result.scalars().all()]


@router.post("/{invitation_id}/revoke", response_model=InvitationOut)
async def revoke_invitation(
    invitation_id: int,
    current_user: User = Depends(require_roles("admin", "hr")),
    db: AsyncSession = Depends(get_db),
):
    """Revoca una invitación pendiente."""
    result = await db.execute(
        select(Invitation).where(
            Invitation.id == invitation_id,
            Invitation.company_id == current_user.company_id,
        )
    )
    inv = result.scalars().first()
    if not inv:
        raise HTTPException(status_code=404, detail="Invitación no encontrada")
    if inv.status != InvitationStatus.pending.value:
        raise HTTPException(status_code=400, detail=f"La invitación ya está {inv.status}")

    inv.status = InvitationStatus.revoked.value
    await db.commit()
    await db.refresh(inv)
    return _to_out(inv)


@router.get("/{token}", response_model=InvitationTokenCheck)
async def check_invitation_token(
    token: str,
    db: AsyncSession = Depends(get_db),
):
    """
    Valida un token de invitación (endpoint público, no requiere auth).
    El frontend lo usa para mostrar la pantalla de aceptación.
    """
    result = await db.execute(
        select(Invitation).where(Invitation.token == token)
    )
    inv = result.scalars().first()
    if not inv:
        return InvitationTokenCheck(valid=False, message="Token de invitación inválido")

    if inv.status == InvitationStatus.accepted.value:
        return InvitationTokenCheck(valid=False, message="Esta invitación ya fue aceptada")
    if inv.status == InvitationStatus.revoked.value:
        return InvitationTokenCheck(valid=False, message="Esta invitación fue revocada")
    if inv.status == InvitationStatus.expired.value or inv.expires_at < datetime.now(timezone.utc):
        return InvitationTokenCheck(valid=False, message="Esta invitación ha expirado")

    company_result = await db.execute(select(Company).where(Company.id == inv.company_id))
    company = company_result.scalars().first()

    return InvitationTokenCheck(
        valid=True,
        email=inv.email,
        company_name=company.name if company else None,
        roles=_parse_roles_csv(inv.roles_csv),
        expires_at=inv.expires_at.strftime("%Y-%m-%d %H:%M"),
        message="Invitación válida",
    )


@router.post("/{token}/accept", response_model=dict, status_code=status.HTTP_201_CREATED)
async def accept_invitation(
    token: str,
    payload: AcceptInvitation,
    db: AsyncSession = Depends(get_db),
):
    """
    Acepta una invitación y crea el usuario.
    Endpoint público (no requiere auth) — el token valida el acceso.
    """
    result = await db.execute(
        select(Invitation).where(Invitation.token == token)
    )
    inv = result.scalars().first()
    if not inv:
        raise HTTPException(status_code=404, detail="Token inválido")

    if inv.status != InvitationStatus.pending.value:
        raise HTTPException(status_code=400, detail=f"La invitación está {inv.status}")
    if inv.expires_at < datetime.now(timezone.utc):
        inv.status = InvitationStatus.expired.value
        await db.commit()
        raise HTTPException(status_code=400, detail="La invitación ha expirado")

    # Verificar si el usuario ya existe (multi-empresa)
    existing = await db.execute(select(User).where(User.email == inv.email))
    existing_user = existing.scalars().first()

    if existing_user:
        # Usuario ya existe en otra empresa → reutilizarlo, asignarle nuevos roles
        user = existing_user
    else:
        # Crear usuario nuevo en la empresa de la invitación
        hashed = auth_service.get_password_hash(payload.password)
        user = User(
            email=inv.email,
            full_name=payload.full_name or inv.full_name,
            phone=payload.phone,
            position=payload.position,
            hashed_password=hashed,
            company_id=inv.company_id,
            is_active=True,
        )
        db.add(user)
        await db.flush()

    # Asignar roles de la invitación
    roles_to_assign = _parse_roles_csv(inv.roles_csv) or ["technician"]
    for role_str in roles_to_assign:
        try:
            role_enum = RoleName(role_str)
            db.add(UserRole(user_id=user.id, role=role_enum))
        except ValueError:
            pass

    # Marcar invitación como aceptada
    inv.status = InvitationStatus.accepted.value
    inv.accepted_at = datetime.now(timezone.utc)
    inv.accepted_user_id = user.id

    await db.commit()

    # Generar token de sesión para auto-login (usando company_id de la invitación)
    token_data = {
        "sub": str(user.id),
        "company_id": str(inv.company_id),
        "roles": roles_to_assign,
    }
    access_token = auth_service.create_access_token(token_data)

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user_id": user.id,
        "email": user.email,
        "company_id": inv.company_id,
        "roles": roles_to_assign,
    }
