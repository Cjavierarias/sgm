"""
Modelos adicionales para SGM:
- Invitation: invitaciones por email a colaboradores
- CalendarEvent: eventos de calendario vinculados a planes de mantenimiento
- ExportLog: historial de exportaciones a Google Sheets
"""
from __future__ import annotations

from datetime import datetime
from enum import Enum as PyEnum

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import relationship

from app.models.base import Base


# ─────────────────────────────────────────────
# INVITATION
# ─────────────────────────────────────────────

class InvitationStatus(PyEnum):
    pending   = "pending"    # Enviada, esperando aceptación
    accepted  = "accepted"   # Usuario creado
    expired   = "expired"    # Venció sin aceptar
    revoked   = "revoked"    # Revocada por el admin


class Invitation(Base):
    """
    Invitación a un colaborador enviada por email.
    El admin genera una invitación con un token único; el invitado
    recibe un email con un link que incluye el token y completa su registro.
    """
    __tablename__ = "invitations"

    id              = Column(Integer, primary_key=True, index=True)
    company_id      = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    created_by_id   = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    email           = Column(String(255), nullable=False, index=True)
    token           = Column(String(64), nullable=False, unique=True, index=True)
    roles_csv       = Column(String(255), nullable=True)   # "admin,technician" etc
    full_name       = Column(String(255), nullable=True)
    status          = Column(String(20), nullable=False, default="pending", index=True)
    expires_at      = Column(DateTime(timezone=True), nullable=False)
    accepted_at     = Column(DateTime(timezone=True), nullable=True)
    accepted_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at      = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)

    company         = relationship("Company", foreign_keys=[company_id])
    created_by      = relationship("User", foreign_keys=[created_by_id])
    accepted_user   = relationship("User", foreign_keys=[accepted_user_id])


# ─────────────────────────────────────────────
# CALENDAR EVENT
# ─────────────────────────────────────────────

class CalendarEvent(Base):
    """
    Evento de calendario vinculado a un plan de mantenimiento.
    Se sincroniza con Google Calendar del admin de la empresa.
    """
    __tablename__ = "calendar_events"

    id                    = Column(Integer, primary_key=True, index=True)
    company_id            = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    maintenance_plan_id   = Column(Integer, ForeignKey("maintenance_plans.id", ondelete="CASCADE"), nullable=True)
    work_order_id         = Column(Integer, ForeignKey("work_orders.id", ondelete="CASCADE"), nullable=True)
    title                 = Column(String(255), nullable=False)
    description           = Column(Text, nullable=True)
    start_at              = Column(DateTime(timezone=True), nullable=False)
    end_at                = Column(DateTime(timezone=True), nullable=True)
    color                 = Column(String(20), nullable=True, default="#0077B6")
    location              = Column(String(255), nullable=True)
    google_event_id       = Column(String(255), nullable=True, index=True)
    google_calendar_id    = Column(String(255), nullable=True)   # ID del calendario Google
    synced_at             = Column(DateTime(timezone=True), nullable=True)
    created_at            = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at            = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    company               = relationship("Company", foreign_keys=[company_id])


# ─────────────────────────────────────────────
# EXPORT LOG
# ─────────────────────────────────────────────

class ExportLog(Base):
    """Historial de exportaciones a Google Sheets."""
    __tablename__ = "export_logs"

    id              = Column(Integer, primary_key=True, index=True)
    company_id      = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id         = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    module          = Column(String(50), nullable=False)   # work_orders, spare_parts, etc
    sheet_id        = Column(String(255), nullable=True)   # ID del sheet en Google
    sheet_url       = Column(String(1000), nullable=True)
    rows_exported   = Column(Integer, nullable=True)
    created_at      = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)

    company         = relationship("Company", foreign_keys=[company_id])
    user            = relationship("User", foreign_keys=[user_id])
