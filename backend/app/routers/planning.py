"""
Router de Planificación de Mantenimiento Preventivo.

Endpoints:
GET    /maintenance-plans               Lista todos los planes activos de la empresa
POST   /maintenance-plans               Crear plan para un equipo
GET    /maintenance-plans/{id}          Detalle
PUT    /maintenance-plans/{id}          Editar plan
DELETE /maintenance-plans/{id}          Eliminar plan
POST   /maintenance-plans/{id}/execute  Registrar ejecución → genera OT cerrada y actualiza next_due
GET    /maintenance-plans/upcoming      Planes con vencimiento en los próximos N días
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models.base import (
    Equipment, MaintenanceFrequency, MaintenancePlan,
    User, WorkOrder, WOPriority, WOStatus, WOType,
)
from app.routers.auth import get_current_user, require_roles

router = APIRouter(prefix="/maintenance-plans", tags=["planificacion"])


# ─── Schemas ──────────────────────────────────────────────────────────────────

class PlanCreate(BaseModel):
    equipment_id: int
    title: str
    description: Optional[str] = None
    frequency: str                    # daily | weekly | monthly | quarterly | yearly | by_hours
    frequency_value: int = 1          # cada X unidades
    next_due: Optional[datetime] = None
    assigned_to_id: Optional[int] = None   # técnico asignado por defecto


class PlanUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    frequency: Optional[str] = None
    frequency_value: Optional[int] = None
    next_due: Optional[datetime] = None
    is_active: Optional[bool] = None
    assigned_to_id: Optional[int] = None


class PlanExecute(BaseModel):
    notes: Optional[str] = None
    actual_hours: Optional[float] = None
    executed_at: Optional[datetime] = None


class PlanOut(BaseModel):
    id: int
    equipment_id: int
    equipment_name: Optional[str] = None
    equipment_code: Optional[str] = None
    title: str
    description: Optional[str]
    frequency: str
    frequency_value: int
    next_due: Optional[datetime]
    last_done: Optional[datetime]
    is_active: bool
    assigned_to_id: Optional[int] = None
    assigned_to_name: Optional[str] = None
    days_until_due: Optional[int] = None
    is_overdue: bool = False
    created_at: datetime

    class Config:
        from_attributes = True


# ─── Helper: calcular próximo vencimiento ─────────────────────────────────────

def _calc_next_due(frequency: str, freq_value: int, from_date: datetime) -> datetime:
    freq_map = {
        "daily":     timedelta(days=freq_value),
        "weekly":    timedelta(weeks=freq_value),
        "monthly":   timedelta(days=30 * freq_value),
        "quarterly": timedelta(days=90 * freq_value),
        "yearly":    timedelta(days=365 * freq_value),
        "by_hours":  timedelta(hours=freq_value),
    }
    delta = freq_map.get(frequency, timedelta(days=30 * freq_value))
    return from_date + delta


def _plan_to_out(plan: MaintenancePlan, assigned_user: Optional[User] = None) -> PlanOut:
    now = datetime.now(timezone.utc)
    days_until = None
    is_overdue = False
    if plan.next_due:
        diff = (plan.next_due - now).days
        days_until = diff
        is_overdue = diff < 0

    return PlanOut(
        id=plan.id,
        equipment_id=plan.equipment_id,
        equipment_name=plan.equipment.name if plan.equipment else None,
        equipment_code=plan.equipment.code if plan.equipment else None,
        title=plan.title,
        description=plan.description,
        frequency=plan.frequency if isinstance(plan.frequency, str) else plan.frequency.value,
        frequency_value=plan.frequency_value or 1,
        next_due=plan.next_due,
        last_done=plan.last_done,
        is_active=plan.is_active,
        assigned_to_id=getattr(plan, 'assigned_to_id', None),
        assigned_to_name=(assigned_user.full_name or assigned_user.email) if assigned_user else None,
        days_until_due=days_until,
        is_overdue=is_overdue,
        created_at=plan.created_at,
    )


def _load_plan_query(company_id: int):
    return (
        select(MaintenancePlan)
        .join(Equipment, MaintenancePlan.equipment_id == Equipment.id)
        .options(selectinload(MaintenancePlan.equipment))
        .where(Equipment.company_id == company_id)
    )


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/upcoming", response_model=List[PlanOut])
async def upcoming_plans(
    days: int = 30,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Planes con vencimiento en los próximos N días (incluye vencidos)."""
    limit_date = datetime.now(timezone.utc) + timedelta(days=days)
    result = await db.execute(
        _load_plan_query(current_user.company_id)
        .where(
            MaintenancePlan.is_active == True,
            MaintenancePlan.next_due <= limit_date,
        )
        .order_by(MaintenancePlan.next_due)
    )
    return [_plan_to_out(p) for p in result.scalars().all()]


@router.get("/", response_model=List[PlanOut])
async def list_plans(
    active_only: bool = False,
    skip: int = 0,
    limit: int = 200,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    query = _load_plan_query(current_user.company_id).order_by(MaintenancePlan.next_due)
    if active_only:
        query = query.where(MaintenancePlan.is_active == True)
    result = await db.execute(query.offset(skip).limit(limit))
    return [_plan_to_out(p) for p in result.scalars().all()]


@router.post("/", response_model=PlanOut, status_code=201)
async def create_plan(
    payload: PlanCreate,
    current_user: User = Depends(require_roles("admin", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    # Verificar que el equipo pertenece a la empresa
    eq_result = await db.execute(
        select(Equipment).where(
            Equipment.id == payload.equipment_id,
            Equipment.company_id == current_user.company_id,
        )
    )
    if not eq_result.scalars().first():
        raise HTTPException(status_code=404, detail="Equipo no encontrado")

    try:
        freq_enum = MaintenanceFrequency(payload.frequency)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Frecuencia inválida: {payload.frequency}")

    next_due = payload.next_due or _calc_next_due(
        payload.frequency, payload.frequency_value, datetime.now(timezone.utc)
    )

    plan = MaintenancePlan(
        equipment_id=payload.equipment_id,
        title=payload.title,
        description=payload.description,
        frequency=freq_enum,
        frequency_value=payload.frequency_value,
        next_due=next_due,
        is_active=True,
    )
    db.add(plan)
    await db.commit()
    result = await db.execute(
        _load_plan_query(current_user.company_id).where(MaintenancePlan.id == plan.id)
    )
    return _plan_to_out(result.scalars().first())


@router.get("/{plan_id}", response_model=PlanOut)
async def get_plan(
    plan_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        _load_plan_query(current_user.company_id).where(MaintenancePlan.id == plan_id)
    )
    plan = result.scalars().first()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan no encontrado")
    return _plan_to_out(plan)


@router.put("/{plan_id}", response_model=PlanOut)
async def update_plan(
    plan_id: int,
    payload: PlanUpdate,
    current_user: User = Depends(require_roles("admin", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        _load_plan_query(current_user.company_id).where(MaintenancePlan.id == plan_id)
    )
    plan = result.scalars().first()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan no encontrado")

    if payload.title is not None: plan.title = payload.title
    if payload.description is not None: plan.description = payload.description
    if payload.frequency_value is not None: plan.frequency_value = payload.frequency_value
    if payload.next_due is not None: plan.next_due = payload.next_due
    if payload.is_active is not None: plan.is_active = payload.is_active
    if payload.frequency is not None:
        try:
            plan.frequency = MaintenanceFrequency(payload.frequency)
        except ValueError:
            raise HTTPException(status_code=400, detail=f"Frecuencia inválida: {payload.frequency}")

    await db.commit()
    result = await db.execute(
        _load_plan_query(current_user.company_id).where(MaintenancePlan.id == plan_id)
    )
    return _plan_to_out(result.scalars().first())


@router.delete("/{plan_id}", status_code=204)
async def delete_plan(
    plan_id: int,
    current_user: User = Depends(require_roles("admin", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        _load_plan_query(current_user.company_id).where(MaintenancePlan.id == plan_id)
    )
    plan = result.scalars().first()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan no encontrado")
    await db.delete(plan)
    await db.commit()


@router.post("/{plan_id}/execute", response_model=PlanOut)
async def execute_plan(
    plan_id: int,
    payload: PlanExecute,
    current_user: User = Depends(require_roles("admin", "maintenance_manager", "technician")),
    db: AsyncSession = Depends(get_db),
):
    """
    Registra la ejecución de un mantenimiento preventivo:
    - Marca last_done = ahora
    - Calcula y actualiza next_due
    - Genera una WorkOrder de tipo preventive cerrada como registro histórico
    """
    result = await db.execute(
        _load_plan_query(current_user.company_id).where(MaintenancePlan.id == plan_id)
    )
    plan = result.scalars().first()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan no encontrado")

    executed_at = payload.executed_at or datetime.now(timezone.utc)
    plan.last_done = executed_at
    plan.next_due = _calc_next_due(
        plan.frequency if isinstance(plan.frequency, str) else plan.frequency.value,
        plan.frequency_value or 1,
        executed_at,
    )

    # Crear OT histórica cerrada
    wo = WorkOrder(
        company_id=current_user.company_id,
        equipment_id=plan.equipment_id,
        created_by_id=current_user.id,
        assigned_to_id=current_user.id,
        title=f"[Preventivo] {plan.title}",
        description=payload.notes or plan.description,
        status=WOStatus.closed,
        priority=WOPriority.medium,
        wo_type=WOType.preventive,
        actual_hours=payload.actual_hours,
        closed_at=executed_at,
    )
    db.add(wo)
    await db.commit()

    result = await db.execute(
        _load_plan_query(current_user.company_id).where(MaintenancePlan.id == plan_id)
    )
    return _plan_to_out(result.scalars().first())
