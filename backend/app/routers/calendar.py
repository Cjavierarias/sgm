"""
Router de calendario y sincronización con Google Calendar.

Endpoints:
  GET  /calendar/events                → Lista eventos de la empresa (rango)
  POST /calendar/company               → Crea calendario Google para la empresa
  POST /calendar/share/{user_id}       → Comparte calendario con un usuario
  POST /maintenance-plans/{id}/sync    → Sincroniza un plan con Google Calendar
  DELETE /calendar/events/{id}         → Elimina un evento
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.base import Company, MaintenancePlan, User
from app.models.collaboration import CalendarEvent
from app.routers.auth import get_current_user, require_roles
from app.services import google_calendar as gc_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/calendar", tags=["calendar"])


# ─── Schemas ──────────────────────────────────────────────────────────────────

class CalendarEventOut(BaseModel):
    id:                  int
    title:               str
    description:         Optional[str]
    start_at:            str
    end_at:              Optional[str]
    color:               Optional[str]
    location:            Optional[str]
    maintenance_plan_id: Optional[int]
    work_order_id:       Optional[int]
    synced:              bool

    class Config:
        from_attributes = True


class CreateCalendarBody(BaseModel):
    admin_email: str


class ShareCalendarBody(BaseModel):
    user_email: str
    role: str = "reader"   # reader | writer


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _to_out(ev: CalendarEvent) -> CalendarEventOut:
    return CalendarEventOut(
        id=ev.id,
        title=ev.title,
        description=ev.description,
        start_at=ev.start_at.strftime("%Y-%m-%d %H:%M"),
        end_at=ev.end_at.strftime("%Y-%m-%d %H:%M") if ev.end_at else None,
        color=ev.color,
        location=ev.location,
        maintenance_plan_id=ev.maintenance_plan_id,
        work_order_id=ev.work_order_id,
        synced=ev.google_event_id is not None,
    )


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/events", response_model=List[CalendarEventOut])
async def list_calendar_events(
    date_from: Optional[str] = Query(None, description="YYYY-MM-DD"),
    date_to:   Optional[str] = Query(None, description="YYYY-MM-DD"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Lista eventos de calendario de la empresa en un rango de fechas."""
    now = datetime.now(timezone.utc)
    if date_from:
        try:
            dt_from = datetime.fromisoformat(date_from).replace(tzinfo=timezone.utc)
        except ValueError:
            dt_from = now - timedelta(days=30)
    else:
        dt_from = now - timedelta(days=30)

    if date_to:
        try:
            dt_to = datetime.fromisoformat(date_to).replace(tzinfo=timezone.utc) + timedelta(days=1)
        except ValueError:
            dt_to = now + timedelta(days=60)
    else:
        dt_to = now + timedelta(days=60)

    result = await db.execute(
        select(CalendarEvent)
        .where(
            CalendarEvent.company_id == current_user.company_id,
            CalendarEvent.start_at >= dt_from,
            CalendarEvent.start_at <= dt_to,
        )
        .order_by(CalendarEvent.start_at)
    )
    return [_to_out(ev) for ev in result.scalars().all()]


@router.post("/company", response_model=dict)
async def create_company_calendar(
    payload: CreateCalendarBody,
    current_user: User = Depends(require_roles("admin")),
    db: AsyncSession = Depends(get_db),
):
    """Crea un calendario compartido en Google Calendar para la empresa."""
    result = await db.execute(select(Company).where(Company.id == current_user.company_id))
    company = result.scalars().first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

    calendar_id = gc_service.create_company_calendar(company.name, payload.admin_email)
    if not calendar_id:
        raise HTTPException(
            status_code=502,
            detail="No se pudo crear el calendario. Verificá la configuración de Google Service Account."
        )

    # Guardar el calendar_id en la empresa (usamos google_workspace_id si está libre)
    if not company.google_workspace_id:
        company.google_workspace_id = calendar_id
        await db.commit()

    return {"calendar_id": calendar_id, "message": "Calendario creado y compartido con el admin"}


@router.post("/share/{user_id}", response_model=dict)
async def share_calendar_with_user(
    user_id: int,
    payload: ShareCalendarBody,
    current_user: User = Depends(require_roles("admin")),
    db: AsyncSession = Depends(get_db),
):
    """Comparte el calendario de la empresa con un usuario existente."""
    # Buscar usuario por user_id para obtener su email
    result = await db.execute(
        select(User).where(User.id == user_id, User.company_id == current_user.company_id)
    )
    target_user = result.scalars().first()
    if not target_user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado en tu empresa")

    result = await db.execute(select(Company).where(Company.id == current_user.company_id))
    company = result.scalars().first()
    if not company or not company.google_workspace_id:
        raise HTTPException(status_code=400, detail="La empresa no tiene calendario de Google configurado")

    ok = gc_service.share_calendar_with_user(
        company.google_workspace_id, target_user.email, payload.role
    )
    if not ok:
        raise HTTPException(status_code=502, detail="No se pudo compartir el calendario")

    return {"message": f"Calendario compartido con {target_user.email} como {payload.role}"}


@router.post("/maintenance-plans/{plan_id}/sync", response_model=CalendarEventOut)
async def sync_plan_to_calendar(
    plan_id: int,
    current_user: User = Depends(require_roles("admin", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    """Sincroniza un plan de mantenimiento con Google Calendar (crea o actualiza evento)."""
    result = await db.execute(
        select(MaintenancePlan)
        .join(Equipment, MaintenancePlan.equipment_id == Equipment.id)
        .where(
            MaintenancePlan.id == plan_id,
            Equipment.company_id == current_user.company_id,
        )
    )
    plan = result.scalars().first()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan no encontrado")

    result = await db.execute(select(Company).where(Company.id == current_user.company_id))
    company = result.scalars().first()
    if not company or not company.google_workspace_id:
        raise HTTPException(
            status_code=400,
            detail="La empresa no tiene calendario de Google. Crealo primero con POST /calendar/company"
        )

    # Buscar evento existente
    result = await db.execute(
        select(CalendarEvent).where(
            CalendarEvent.maintenance_plan_id == plan_id,
            CalendarEvent.company_id == current_user.company_id,
        )
    )
    existing_event = result.scalars().first()

    # Calcular próxima fecha
    next_date = plan.next_due if plan.next_due else datetime.now(timezone.utc) + timedelta(days=7)
    if hasattr(next_date, "astimezone"):
        start_at = next_date
    else:
        start_at = datetime.combine(next_date, datetime.min.time(), tzinfo=timezone.utc)

    title = f"Mantenimiento: {plan.title}"
    description = f"Plan de mantenimiento preventivo.\nFrecuencia: {plan.frequency}\nEquipo ID: {plan.equipment_id}"
    if plan.description:
        description += f"\n\n{plan.description}"

    google_event_id = gc_service.create_or_update_event(
        calendar_id=company.google_workspace_id,
        title=title,
        description=description,
        start_at=start_at,
        google_event_id=existing_event.google_event_id if existing_event else None,
    )

    if existing_event:
        existing_event.title          = title
        existing_event.description    = description
        existing_event.start_at       = start_at
        existing_event.google_event_id = google_event_id
        existing_event.synced_at      = datetime.now(timezone.utc)
        await db.commit()
        await db.refresh(existing_event)
        return _to_out(existing_event)
    else:
        new_event = CalendarEvent(
            company_id=current_user.company_id,
            maintenance_plan_id=plan_id,
            title=title,
            description=description,
            start_at=start_at,
            google_event_id=google_event_id,
            google_calendar_id=company.google_workspace_id,
            synced_at=datetime.now(timezone.utc) if google_event_id else None,
        )
        db.add(new_event)
        await db.commit()
        await db.refresh(new_event)
        return _to_out(new_event)


@router.delete("/events/{event_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_calendar_event(
    event_id: int,
    current_user: User = Depends(require_roles("admin", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    """Elimina un evento del calendario (y de Google Calendar si estaba sincronizado)."""
    result = await db.execute(
        select(CalendarEvent).where(
            CalendarEvent.id == event_id,
            CalendarEvent.company_id == current_user.company_id,
        )
    )
    ev = result.scalars().first()
    if not ev:
        raise HTTPException(status_code=404, detail="Evento no encontrado")

    if ev.google_event_id and ev.google_calendar_id:
        gc_service.delete_event(ev.google_calendar_id, ev.google_event_id)

    await db.delete(ev)
    await db.commit()
