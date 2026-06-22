"""
Router de facturación SGM — Mercado Pago.

Endpoints:
  GET  /billing/status                  → Estado de suscripción de la empresa
  POST /billing/checkout                → Generar URL de pago (Checkout Pro)
  POST /billing/subscribe               → Crear suscripción recurrente (Preaprobación)
  POST /billing/webhook                 → Recibir notificaciones de MP (IPN/Webhook)
  GET  /billing/mp/success              → Redirect de MP tras pago exitoso
  GET  /billing/mp/failure              → Redirect de MP tras pago fallido
  GET  /billing/mp/pending              → Redirect de MP pago pendiente
  GET  /billing/mp/subscription-success → Redirect tras autorizar suscripción recurrente
  GET  /billing/history                 → Historial de eventos de facturación
  POST /billing/admin/check-subscriptions → (interno) Ejecuta verificación diaria
"""
from __future__ import annotations

import logging
import os
from typing import List, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException, Query, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import BaseModel, EmailStr
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.subscription import BillingEventType, BillingPlan, SubscriptionStatus
from app.routers.auth import get_current_user, require_roles
from app.services import billing as billing_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/billing", tags=["billing"])

FRONTEND_URL = os.getenv("FRONTEND_URL", "http://localhost:8080")
ADMIN_SECRET = os.getenv("ADMIN_CRON_SECRET", "")  # Secreto para el endpoint de cron


# ─── Schemas ──────────────────────────────────────────────────────────────────

class SubscriptionStatusOut(BaseModel):
    company_id:           int
    status:               str
    plan:                 Optional[str]
    trial_end:            Optional[str]
    current_period_end:   Optional[str]
    grace_end:            Optional[str]
    days_remaining:       int
    can_use_platform:     bool
    mp_public_key:        str      # Se devuelve al frontend para inicializar el SDK

    class Config:
        from_attributes = True


class CheckoutRequest(BaseModel):
    plan: str = "monthly"   # "monthly" | "annual"


class SubscribeRequest(BaseModel):
    plan:        str = "monthly"
    payer_email: EmailStr


class BillingEventOut(BaseModel):
    id:              int
    event_type:      str
    amount_usd:      Optional[float]
    mp_payment_id:   Optional[str]
    mp_status:       Optional[str]
    notes:           Optional[str]
    created_at:      str

    class Config:
        from_attributes = True


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _fmt_dt(dt) -> Optional[str]:
    return dt.strftime("%Y-%m-%d") if dt else None


def _plan_from_str(plan_str: str) -> BillingPlan:
    try:
        return BillingPlan(plan_str)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Plan inválido: '{plan_str}'. Use 'monthly' o 'annual'.")


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/status", response_model=SubscriptionStatusOut)
async def get_subscription_status(
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Devuelve el estado de la suscripción de la empresa del usuario actual.
    Disponible para todos los usuarios autenticados.
    """
    sub = await billing_service.get_subscription_for_company(db, current_user.company_id)
    if not sub:
        raise HTTPException(status_code=404, detail="No se encontró suscripción para esta empresa")

    return SubscriptionStatusOut(
        company_id=sub.company_id,
        status=sub.status.value if hasattr(sub.status, "value") else str(sub.status),
        plan=sub.plan.value if sub.plan and hasattr(sub.plan, "value") else None,
        trial_end=_fmt_dt(sub.trial_end),
        current_period_end=_fmt_dt(sub.current_period_end),
        grace_end=_fmt_dt(sub.grace_end),
        days_remaining=billing_service.days_remaining(sub),
        can_use_platform=billing_service.subscription_is_active(sub),
        mp_public_key=billing_service.MP_PUBLIC_KEY,
    )


@router.post("/checkout")
async def create_checkout(
    payload: CheckoutRequest,
    current_user=Depends(require_roles("admin")),
    db: AsyncSession = Depends(get_db),
):
    """
    Genera una URL de pago de Mercado Pago (Checkout Pro).
    Solo el administrador puede iniciar el pago.
    Retorna init_point: la URL a la que se redirige al cliente.
    """
    plan = _plan_from_str(payload.plan)
    try:
        data = await billing_service.create_payment_preference(db, current_user.company_id, plan)
    except Exception as exc:
        logger.error("Error creando preferencia MP: %s", exc)
        raise HTTPException(status_code=502, detail=f"Error al conectar con Mercado Pago: {exc}")

    return data


@router.post("/subscribe")
async def create_subscription(
    payload: SubscribeRequest,
    current_user=Depends(require_roles("admin")),
    db: AsyncSession = Depends(get_db),
):
    """
    Crea una suscripción recurrente (preaprobación) en Mercado Pago.
    MP debitará automáticamente cada mes o año.
    Retorna init_point donde el cliente autoriza el débito.
    """
    plan = _plan_from_str(payload.plan)
    try:
        data = await billing_service.create_recurring_subscription(
            db, current_user.company_id, plan, payload.payer_email
        )
    except Exception as exc:
        logger.error("Error creando suscripción recurrente MP: %s", exc)
        raise HTTPException(status_code=502, detail=f"Error al conectar con Mercado Pago: {exc}")

    return data


@router.post("/webhook", status_code=200)
async def mercadopago_webhook(
    request: Request,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    x_signature: Optional[str] = Header(None, alias="x-signature"),
    x_request_id: Optional[str] = Header(None, alias="x-request-id"),
):
    """
    Recibe notificaciones IPN/Webhook de Mercado Pago.
    MP envía el evento y aquí consultamos el detalle del pago.
    
    MP envía POST con query params:  ?id=<payment_id>&topic=payment
    O body JSON: {"action": "payment.updated", "data": {"id": "..."}}
    
    IMPORTANTE: MP espera respuesta 200 inmediata; el procesamiento va en background.
    """
    raw_body = await request.body()

    # Validar firma si está configurado el secreto
    if x_signature and x_request_id:
        if not billing_service.verify_webhook_signature(raw_body, x_signature, x_request_id):
            logger.warning("Firma webhook inválida — rechazando")
            raise HTTPException(status_code=401, detail="Firma inválida")

    # Obtener topic e id desde query params o body
    params = dict(request.query_params)
    topic      = params.get("topic") or params.get("type", "")
    payment_id = params.get("id") or params.get("data[id]", "")

    # Si viene en body JSON
    if not payment_id:
        try:
            body_json = await request.json()
            payment_id = str(body_json.get("data", {}).get("id", ""))
            topic      = body_json.get("type", topic)
        except Exception:
            pass

    if payment_id and topic:
        background_tasks.add_task(
            billing_service.process_payment_webhook, db, payment_id, topic
        )

    # MP requiere 200 inmediato
    return {"status": "ok"}


@router.get("/mp/success", response_class=HTMLResponse)
async def mp_payment_success(
    payment_id: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    external_reference: Optional[str] = Query(None),
):
    """
    Redirect de Mercado Pago tras pago aprobado.
    Redirige al frontend con el resultado.
    """
    return RedirectResponse(
        url=f"{FRONTEND_URL}/#/billing/success?payment_id={payment_id or ''}&status={status or ''}",
        status_code=303,
    )


@router.get("/mp/failure", response_class=HTMLResponse)
async def mp_payment_failure(
    payment_id: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
):
    return RedirectResponse(
        url=f"{FRONTEND_URL}/#/billing/failure?payment_id={payment_id or ''}&status={status or ''}",
        status_code=303,
    )


@router.get("/mp/pending", response_class=HTMLResponse)
async def mp_payment_pending(
    payment_id: Optional[str] = Query(None),
):
    return RedirectResponse(
        url=f"{FRONTEND_URL}/#/billing/pending?payment_id={payment_id or ''}",
        status_code=303,
    )


@router.get("/mp/subscription-success", response_class=HTMLResponse)
async def mp_subscription_success(
    preapproval_id: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
):
    return RedirectResponse(
        url=f"{FRONTEND_URL}/#/billing/subscribed?preapproval_id={preapproval_id or ''}&status={status or ''}",
        status_code=303,
    )


@router.get("/history", response_model=List[BillingEventOut])
async def billing_history(
    skip: int = 0,
    limit: int = 50,
    current_user=Depends(require_roles("admin")),
    db: AsyncSession = Depends(get_db),
):
    """Historial de eventos de facturación de la empresa."""
    from sqlalchemy import select
    from app.models.subscription import BillingEvent, Subscription

    result = await db.execute(
        select(Subscription).where(Subscription.company_id == current_user.company_id)
    )
    sub = result.scalars().first()
    if not sub:
        return []

    result = await db.execute(
        select(BillingEvent)
        .where(BillingEvent.subscription_id == sub.id)
        .order_by(BillingEvent.created_at.desc())
        .offset(skip)
        .limit(min(limit, 200))
    )
    events = result.scalars().all()
    return [
        BillingEventOut(
            id=e.id,
            event_type=e.event_type.value if hasattr(e.event_type, "value") else str(e.event_type),
            amount_usd=e.amount_usd,
            mp_payment_id=e.mp_payment_id,
            mp_status=e.mp_status,
            notes=e.notes,
            created_at=e.created_at.strftime("%Y-%m-%d %H:%M:%S"),
        )
        for e in events
    ]


@router.post("/admin/check-subscriptions")
async def admin_check_subscriptions(
    background_tasks: BackgroundTasks,
    secret: str = Query(..., description="Secreto ADMIN_CRON_SECRET"),
    db: AsyncSession = Depends(get_db),
):
    """
    Endpoint interno para ejecutar la verificación diaria de suscripciones.
    Llamar desde un cron externo (cron job, scheduler, etc.) con:
      POST /billing/admin/check-subscriptions?secret=<ADMIN_CRON_SECRET>

    Protegido por secreto en query param para evitar ejecuciones no autorizadas.
    """
    if not ADMIN_SECRET or secret != ADMIN_SECRET:
        raise HTTPException(status_code=403, detail="Secreto inválido")

    background_tasks.add_task(billing_service.run_daily_subscription_check, db)
    return {"status": "verificación iniciada en background"}
