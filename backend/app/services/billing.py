"""
Servicio de facturación SGM — Mercado Pago.

Lógica de negocio:
- Crear suscripción en trial al registrar un admin
- Generar preferencia de pago (Checkout Pro o Suscripción recurrente)
- Procesar webhooks de Mercado Pago (IPN/webhook)
- Verificar y actualizar estado de suscripciones (cron diario)
- Bloquear admins sin pago tras vencimiento
- Retención de datos 90 días en estado grace
- Purga de datos tras 90 días sin pago

Variables de entorno requeridas:
  MP_ACCESS_TOKEN     → Access token de producción (tu clave secreta MP)
  MP_PUBLIC_KEY       → Clave pública MP (para el frontend)
  MP_WEBHOOK_SECRET   → Secreto para validar firmas de webhook
  APP_BASE_URL        → URL pública del backend (para URLs de retorno)
"""
from __future__ import annotations

import hashlib
import hmac
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Optional

import httpx
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.base import Company, User
from app.models.subscription import (
    BillingEvent,
    BillingEventType,
    BillingPlan,
    BlockedAdminEmail,
    Subscription,
    SubscriptionStatus,
)

logger = logging.getLogger(__name__)

# ─── Configuración MP ─────────────────────────────────────────────────────────

MP_ACCESS_TOKEN   = os.getenv("MP_ACCESS_TOKEN", "")
MP_PUBLIC_KEY     = os.getenv("MP_PUBLIC_KEY", "")
MP_WEBHOOK_SECRET = os.getenv("MP_WEBHOOK_SECRET", "")
APP_BASE_URL      = os.getenv("APP_BASE_URL", "http://localhost:8000")

MP_API_BASE       = "https://api.mercadopago.com"

# Precios en USD (Mercado Pago permite cobrar en USD con cuenta en Argentina)
PRICE_MONTHLY_USD = 5.0
PRICE_ANNUAL_USD  = 50.0

TRIAL_DAYS        = 30
GRACE_DAYS        = 90   # días que se retienen datos tras vencer


# ─── Helpers HTTP ─────────────────────────────────────────────────────────────

def _mp_headers() -> dict:
    return {
        "Authorization": f"Bearer {MP_ACCESS_TOKEN}",
        "Content-Type": "application/json",
        "X-Idempotency-Key": "",   # se sobreescribe por llamada
    }


async def _mp_post(path: str, body: dict, idempotency_key: str = "") -> dict:
    headers = _mp_headers()
    headers["X-Idempotency-Key"] = idempotency_key
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(f"{MP_API_BASE}{path}", json=body, headers=headers)
        resp.raise_for_status()
        return resp.json()


async def _mp_get(path: str) -> dict:
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(
            f"{MP_API_BASE}{path}",
            headers={"Authorization": f"Bearer {MP_ACCESS_TOKEN}"},
        )
        resp.raise_for_status()
        return resp.json()


# ─── Creación de suscripción al registrar admin ───────────────────────────────

async def create_trial_subscription(db: AsyncSession, company_id: int, admin_email: str) -> Subscription:
    """
    Crea una suscripción en estado 'trial' de 30 días.
    Se llama automáticamente al registrar un nuevo administrador.
    """
    now = datetime.now(timezone.utc)
    sub = Subscription(
        company_id=company_id,
        admin_email=admin_email,
        plan=BillingPlan.monthly,
        status=SubscriptionStatus.trial,
        trial_start=now,
        trial_end=now + timedelta(days=TRIAL_DAYS),
    )
    db.add(sub)
    await db.flush()

    event = BillingEvent(
        subscription_id=sub.id,
        event_type=BillingEventType.trial_started,
        notes=f"Trial gratuito iniciado. Vence: {sub.trial_end.strftime('%Y-%m-%d')}",
    )
    db.add(event)
    await db.commit()
    await db.refresh(sub)
    return sub


# ─── Generar preferencia de pago (Checkout Pro) ───────────────────────────────

async def create_payment_preference(
    db: AsyncSession,
    company_id: int,
    plan: BillingPlan,
) -> dict:
    """
    Genera una preferencia de pago en Mercado Pago y devuelve la init_point
    (URL a la que redirigir al usuario).

    Retorna:
        {
          "preference_id": "...",
          "init_point": "https://www.mercadopago.com.ar/checkout/v1/redirect?pref_id=...",
          "sandbox_init_point": "https://sandbox.mercadopago.com.ar/...",
          "plan": "monthly|annual",
          "amount_usd": 5.0 | 50.0,
        }
    """
    result = await db.execute(
        select(Subscription).where(Subscription.company_id == company_id)
    )
    sub = result.scalars().first()
    if not sub:
        raise ValueError("No existe suscripción para esta empresa")

    amount   = PRICE_MONTHLY_USD if plan == BillingPlan.monthly else PRICE_ANNUAL_USD
    title    = "SGM Mensual — BSA Consultora" if plan == BillingPlan.monthly else "SGM Anual — BSA Consultora"
    ik       = f"sgm-pref-{company_id}-{int(datetime.now().timestamp())}"

    body = {
        "items": [
            {
                "id":          f"sgm-{plan.value}",
                "title":       title,
                "quantity":    1,
                "unit_price":  amount,
                "currency_id": "USD",
            }
        ],
        "payer": {
            "email": sub.admin_email,
        },
        "back_urls": {
            "success": f"{APP_BASE_URL}/billing/mp/success",
            "failure": f"{APP_BASE_URL}/billing/mp/failure",
            "pending": f"{APP_BASE_URL}/billing/mp/pending",
        },
        "auto_return":           "approved",
        "notification_url":      f"{APP_BASE_URL}/billing/webhook",
        "external_reference":    str(company_id),
        "statement_descriptor":  "SGM BSA",
        "binary_mode":           True,   # Solo aprobado o rechazado, sin pendiente
        "metadata": {
            "company_id": company_id,
            "plan":        plan.value,
        },
    }

    data = await _mp_post("/checkout/preferences", body, idempotency_key=ik)

    return {
        "preference_id":      data["id"],
        "init_point":         data["init_point"],
        "sandbox_init_point": data.get("sandbox_init_point", ""),
        "plan":               plan.value,
        "amount_usd":         amount,
    }


# ─── Crear suscripción recurrente (Preaprobación MP) ──────────────────────────

async def create_recurring_subscription(
    db: AsyncSession,
    company_id: int,
    plan: BillingPlan,
    payer_email: str,
) -> dict:
    """
    Crea una suscripción recurrente en MP (preapproval).
    MP debita automáticamente cada mes/año.

    Retorna la URL de autorización donde el cliente aprueba el débito.
    """
    amount     = PRICE_MONTHLY_USD if plan == BillingPlan.monthly else PRICE_ANNUAL_USD
    frequency  = 1          # cada 1 unidad
    freq_type  = "months" if plan == BillingPlan.monthly else "years"
    title      = "SGM Mensual — BSA Consultora" if plan == BillingPlan.monthly else "SGM Anual — BSA Consultora"
    ik         = f"sgm-preapproval-{company_id}-{int(datetime.now().timestamp())}"

    body = {
        "auto_recurring": {
            "frequency":      frequency,
            "frequency_type": freq_type,
            "transaction_amount": amount,
            "currency_id":    "USD",
        },
        "back_url":           f"{APP_BASE_URL}/billing/mp/subscription-success",
        "external_reference": str(company_id),
        "payer_email":        payer_email,
        "reason":             title,
        "status":             "pending",   # El cliente debe autorizar
    }

    data = await _mp_post("/preapproval", body, idempotency_key=ik)

    # Guardar preapproval_id en la suscripción
    result = await db.execute(select(Subscription).where(Subscription.company_id == company_id))
    sub = result.scalars().first()
    if sub:
        sub.mp_preapproval_id = data["id"]
        sub.mp_payer_email    = payer_email
        sub.plan              = plan
        await db.commit()

    return {
        "preapproval_id":  data["id"],
        "init_point":      data["init_point"],
        "plan":            plan.value,
        "amount_usd":      amount,
    }


# ─── Procesar webhook de Mercado Pago ─────────────────────────────────────────

def verify_webhook_signature(raw_body: bytes, mp_signature: str, mp_request_id: str) -> bool:
    """
    Valida la firma HMAC-SHA256 que MP envía en el header x-signature.
    Formato del header: ts=<timestamp>,v1=<hash>

    Docs: https://www.mercadopago.com.ar/developers/es/docs/your-integrations/notifications/webhooks
    """
    if not MP_WEBHOOK_SECRET:
        logger.warning("MP_WEBHOOK_SECRET no configurado — omitiendo validación de firma")
        return True   # En desarrollo sin secreto se omite; en producción DEBE estar configurado

    try:
        parts   = dict(p.split("=", 1) for p in mp_signature.split(","))
        ts      = parts.get("ts", "")
        v1      = parts.get("v1", "")
        message = f"id:{mp_request_id};request-id:{mp_request_id};ts:{ts};"
        digest  = hmac.new(
            MP_WEBHOOK_SECRET.encode(),
            message.encode(),
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(digest, v1)
    except Exception as exc:
        logger.error("Error validando firma webhook MP: %s", exc)
        return False


async def process_payment_webhook(db: AsyncSession, payment_id: str, topic: str) -> None:
    """
    Consulta el pago en MP y actualiza el estado de la suscripción.
    Se llama desde el endpoint /billing/webhook.
    """
    if topic not in ("payment", "merchant_order"):
        logger.info("Webhook topic ignorado: %s", topic)
        return

    # Consultar pago en MP
    try:
        payment = await _mp_get(f"/v1/payments/{payment_id}")
    except httpx.HTTPStatusError as exc:
        logger.error("Error consultando pago %s en MP: %s", payment_id, exc)
        return

    status_mp        = payment.get("status", "")           # approved / rejected / pending
    status_detail    = payment.get("status_detail", "")
    external_ref     = payment.get("external_reference", "")   # company_id
    amount           = payment.get("transaction_amount", 0.0)
    mp_payment_id    = str(payment.get("id", payment_id))
    metadata         = payment.get("metadata", {})
    plan_str         = metadata.get("plan", "monthly")

    try:
        company_id = int(external_ref)
    except (ValueError, TypeError):
        logger.error("external_reference inválido: %s", external_ref)
        return

    result = await db.execute(select(Subscription).where(Subscription.company_id == company_id))
    sub = result.scalars().first()
    if not sub:
        logger.warning("Suscripción no encontrada para company_id %s", company_id)
        return

    now = datetime.now(timezone.utc)

    if status_mp == "approved":
        plan = BillingPlan.annual if plan_str == "annual" else BillingPlan.monthly
        months = 12 if plan == BillingPlan.annual else 1

        sub.status               = SubscriptionStatus.active
        sub.plan                 = plan
        sub.current_period_start = now
        sub.current_period_end   = now + timedelta(days=30 * months)
        sub.grace_start          = None
        sub.grace_end            = None

        event_type = BillingEventType.payment_approved

    elif status_mp == "rejected":
        event_type = BillingEventType.payment_rejected

    else:
        event_type = BillingEventType.payment_pending

    event = BillingEvent(
        subscription_id  = sub.id,
        event_type       = event_type,
        amount_usd       = amount,
        mp_payment_id    = mp_payment_id,
        mp_status        = status_mp,
        mp_detail        = status_detail,
    )
    db.add(event)
    await db.commit()
    logger.info("Webhook procesado: company=%s status=%s payment=%s", company_id, status_mp, mp_payment_id)


# ─── Tarea diaria: verificar suscripciones vencidas ───────────────────────────

async def run_daily_subscription_check(db: AsyncSession) -> dict:
    """
    Cron diario que:
    1. Pasa trial expirado → grace
    2. Pasa active expirado → grace
    3. Pasa grace expirado → suspended + purga de datos + bloquea email
    4. Registra eventos

    Retorna un resumen de las acciones tomadas.
    """
    now     = datetime.now(timezone.utc)
    summary = {"trial_expired": 0, "active_expired": 0, "suspended": 0, "purged": 0}

    # ── 1. Trials vencidos ────────────────────────────────────────────────────
    result = await db.execute(
        select(Subscription).where(
            Subscription.status == SubscriptionStatus.trial,
            Subscription.trial_end < now,
        )
    )
    for sub in result.scalars().all():
        sub.status      = SubscriptionStatus.grace
        sub.grace_start = now
        sub.grace_end   = now + timedelta(days=GRACE_DAYS)
        db.add(BillingEvent(
            subscription_id=sub.id,
            event_type=BillingEventType.trial_expired,
            notes=f"Trial vencido el {now.strftime('%Y-%m-%d')}. Grace period hasta {sub.grace_end.strftime('%Y-%m-%d')}.",
        ))
        summary["trial_expired"] += 1

    # ── 2. Activos vencidos ───────────────────────────────────────────────────
    result = await db.execute(
        select(Subscription).where(
            Subscription.status == SubscriptionStatus.active,
            Subscription.current_period_end < now,
        )
    )
    for sub in result.scalars().all():
        sub.status      = SubscriptionStatus.grace
        sub.grace_start = now
        sub.grace_end   = now + timedelta(days=GRACE_DAYS)
        db.add(BillingEvent(
            subscription_id=sub.id,
            event_type=BillingEventType.trial_expired,
            notes=f"Período de pago vencido. Grace period hasta {sub.grace_end.strftime('%Y-%m-%d')}.",
        ))
        summary["active_expired"] += 1

    # ── 3. Grace period vencido → suspender + purgar ──────────────────────────
    result = await db.execute(
        select(Subscription)
        .where(
            Subscription.status == SubscriptionStatus.grace,
            Subscription.grace_end < now,
        )
    )
    for sub in result.scalars().all():
        await _purge_company_data(db, sub.company_id)
        sub.status = SubscriptionStatus.suspended
        db.add(BillingEvent(
            subscription_id=sub.id,
            event_type=BillingEventType.data_purged,
            notes="Grace period vencido. Datos de la empresa purgados.",
        ))

        # Bloquear el email del admin
        existing_block = await db.execute(
            select(BlockedAdminEmail).where(BlockedAdminEmail.email == sub.admin_email)
        )
        if not existing_block.scalars().first():
            db.add(BlockedAdminEmail(
                email=sub.admin_email,
                reason="Suscripción suspendida por falta de pago tras grace period.",
                is_active=True,
            ))

        summary["suspended"]  += 1
        summary["purged"]     += 1

    await db.commit()
    logger.info("Verificación diaria completada: %s", summary)
    return summary


async def _purge_company_data(db: AsyncSession, company_id: int) -> None:
    """
    Elimina todos los datos operativos de la empresa (equipos, OT, repuestos, etc.)
    manteniendo la empresa y el registro de suscripción para auditoría.
    El cascade delete en las FK hace el trabajo.
    """
    from app.models.base import Equipment, WorkOrder, SparePart, Supplier, Notification

    # Basta con borrar equipos, OT, repuestos y proveedores — cascade se encarga del resto
    for Model in (Notification, WorkOrder, Equipment, SparePart, Supplier):
        result = await db.execute(
            select(Model).where(Model.company_id == company_id)
        )
        for obj in result.scalars().all():
            await db.delete(obj)

    # Desactivar todos los usuarios (no borramos — dejamos trazabilidad)
    result = await db.execute(select(User).where(User.company_id == company_id))
    for user in result.scalars().all():
        user.is_active = False

    # Marcar empresa como inactiva
    result = await db.execute(select(Company).where(Company.id == company_id))
    company = result.scalars().first()
    if company:
        company.status = "suspended"

    logger.info("Datos purgados para company_id=%s", company_id)


# ─── Verificar acceso a la plataforma ─────────────────────────────────────────

async def get_subscription_for_company(db: AsyncSession, company_id: int) -> Optional[Subscription]:
    result = await db.execute(
        select(Subscription)
        .options(selectinload(Subscription.billing_events))
        .where(Subscription.company_id == company_id)
    )
    return result.scalars().first()


def subscription_is_active(sub: Optional[Subscription]) -> bool:
    """True si la empresa puede usar la plataforma (trial o active)."""
    if not sub:
        return False
    return sub.status in (SubscriptionStatus.trial, SubscriptionStatus.active)


def days_remaining(sub: Subscription) -> int:
    """Días restantes del período actual (trial o active)."""
    now = datetime.now(timezone.utc)
    if sub.status == SubscriptionStatus.trial:
        end = sub.trial_end
    elif sub.status == SubscriptionStatus.active:
        end = sub.current_period_end
    else:
        return 0
    diff = (end - now).days
    return max(0, diff)


# ─── Verificar si un email está bloqueado ────────────────────────────────────

async def is_email_blocked_as_admin(db: AsyncSession, email: str) -> bool:
    """Retorna True si el email no puede registrarse como admin."""
    now    = datetime.now(timezone.utc)
    result = await db.execute(
        select(BlockedAdminEmail).where(
            BlockedAdminEmail.email     == email,
            BlockedAdminEmail.is_active == True,
        )
    )
    block = result.scalars().first()
    if not block:
        return False
    # Si tiene fecha de desbloqueo y ya pasó → desbloquear automáticamente
    if block.unblock_after and block.unblock_after < now:
        block.is_active = False
        await db.commit()
        return False
    return True


# ─── Consultar estado de pago en MP (polling manual) ─────────────────────────

async def fetch_payment_status(payment_id: str) -> dict:
    """Consulta el estado de un pago específico en MP."""
    return await _mp_get(f"/v1/payments/{payment_id}")
