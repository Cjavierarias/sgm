"""
Modelos de suscripción y facturación SGM.

Tablas:
- Subscription       → estado de la suscripción por empresa
- BillingEvent       → historial de pagos / intentos
- BlockedAdminEmail  → emails de admins con deuda que no pueden re-registrarse
"""
from __future__ import annotations

from datetime import datetime
from enum import Enum as PyEnum

from sqlalchemy import Boolean, Column, DateTime, Enum as SQLEnum, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import relationship

from app.models.base import Base


# ─────────────────────────────────────────────
# ENUMS
# ─────────────────────────────────────────────

class SubscriptionStatus(PyEnum):
    trial       = "trial"        # Mes gratis activo
    active      = "active"       # Pago al día
    grace       = "grace"        # Pago vencido — 3 meses retención de datos
    suspended   = "suspended"    # Más de 3 meses sin pago — datos borrados
    cancelled   = "cancelled"    # Cancelado por el cliente


class BillingPlan(PyEnum):
    monthly  = "monthly"   # USD 5/mes
    annual   = "annual"    # USD 50/año


class BillingEventType(PyEnum):
    payment_pending   = "payment_pending"
    payment_approved  = "payment_approved"
    payment_rejected  = "payment_rejected"
    payment_cancelled = "payment_cancelled"
    trial_started     = "trial_started"
    trial_expired     = "trial_expired"
    subscription_cancelled = "subscription_cancelled"
    data_purged       = "data_purged"


# ─────────────────────────────────────────────
# SUBSCRIPTION
# ─────────────────────────────────────────────

class Subscription(Base):
    """
    Una suscripción por empresa. Se crea automáticamente al registrar
    el primer usuario administrador.

    Plan disponibles:
      - monthly  → USD 5 / mes
      - annual   → USD 50 / año (equivale a 2 meses gratis)

    Límites de plan actual:
      - 1 administrador
      - 1 empresa registrada
      - Sin límite de colaboradores (invited users)
    """
    __tablename__ = "subscriptions"

    id                  = Column(Integer, primary_key=True, index=True)
    company_id          = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    admin_email         = Column(String(255), nullable=False, index=True)   # Email del admin responsable del pago

    # Plan y estado
    plan                = Column(SQLEnum(BillingPlan, name="billingplan", native_enum=False), default=BillingPlan.monthly)
    status              = Column(SQLEnum(SubscriptionStatus, name="subscriptionstatus", native_enum=False), default=SubscriptionStatus.trial, nullable=False, index=True)

    # Período de prueba — 30 días desde la creación
    trial_start         = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    trial_end           = Column(DateTime(timezone=True), nullable=False)   # trial_start + 30 días

    # Período de servicio activo
    current_period_start = Column(DateTime(timezone=True), nullable=True)
    current_period_end   = Column(DateTime(timezone=True), nullable=True)

    # Grace period — cuando el pago vence, los datos se retienen 90 días
    grace_start         = Column(DateTime(timezone=True), nullable=True)
    grace_end           = Column(DateTime(timezone=True), nullable=True)    # grace_start + 90 días

    # Mercado Pago
    mp_subscription_id  = Column(String(255), nullable=True, index=True)   # ID de suscripción MP
    mp_preapproval_id   = Column(String(255), nullable=True)                # ID de preaprobación MP
    mp_payer_email      = Column(String(255), nullable=True)

    # Auditoría
    created_at          = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at          = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relaciones
    company             = relationship("Company", foreign_keys=[company_id])
    billing_events      = relationship("BillingEvent", back_populates="subscription", cascade="all, delete-orphan", order_by="BillingEvent.created_at.desc()")


# ─────────────────────────────────────────────
# BILLING EVENT (historial)
# ─────────────────────────────────────────────

class BillingEvent(Base):
    """Registro inmutable de cada evento de pago / cambio de estado."""
    __tablename__ = "billing_events"

    id               = Column(Integer, primary_key=True, index=True)
    subscription_id  = Column(Integer, ForeignKey("subscriptions.id", ondelete="CASCADE"), nullable=False, index=True)

    event_type       = Column(SQLEnum(BillingEventType, name="billingeventtype", native_enum=False), nullable=False)
    amount_usd       = Column(Float, nullable=True)
    mp_payment_id    = Column(String(255), nullable=True, index=True)
    mp_status        = Column(String(100), nullable=True)   # approved / rejected / pending
    mp_detail        = Column(Text, nullable=True)          # detalle textual de MP

    notes            = Column(Text, nullable=True)
    created_at       = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)

    subscription     = relationship("Subscription", back_populates="billing_events")


# ─────────────────────────────────────────────
# BLOCKED ADMIN EMAIL
# ─────────────────────────────────────────────

class BlockedAdminEmail(Base):
    """
    Emails de administradores cuya empresa fue suspendida por falta de pago.
    Esos emails no pueden volver a registrarse como admin en ninguna empresa nueva
    hasta que regularicen su deuda o el período sea mayor a 1 año.
    """
    __tablename__ = "blocked_admin_emails"

    id               = Column(Integer, primary_key=True, index=True)
    email            = Column(String(255), nullable=False, unique=True, index=True)
    reason           = Column(Text, nullable=True)
    blocked_at       = Column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    unblock_after    = Column(DateTime(timezone=True), nullable=True)    # Si None → bloqueo indefinido
    is_active        = Column(Boolean, default=True, nullable=False)
