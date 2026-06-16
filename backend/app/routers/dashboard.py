"""Router de Dashboard — resumen ejecutivo para el Admin."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.base import (
    Equipment, EquipmentStatus, Notification,
    SparePart, User, WorkOrder, WOStatus,
)
from app.routers.auth import get_current_user

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/summary")
async def summary(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    cid = current_user.company_id

    # OT por estado
    wo_counts = {}
    for s in WOStatus:
        r = await db.execute(
            select(func.count(WorkOrder.id)).where(
                WorkOrder.company_id == cid,
                WorkOrder.status == s,
            )
        )
        wo_counts[s.value] = r.scalar()

    # Equipos
    eq_total = (await db.execute(
        select(func.count(Equipment.id)).where(Equipment.company_id == cid)
    )).scalar()
    eq_maintenance = (await db.execute(
        select(func.count(Equipment.id)).where(
            Equipment.company_id == cid,
            Equipment.status == EquipmentStatus.maintenance,
        )
    )).scalar()

    # Usuarios activos
    users_count = (await db.execute(
        select(func.count(User.id)).where(
            User.company_id == cid, User.is_active == True
        )
    )).scalar()

    # Repuestos con stock bajo
    low_stock = (await db.execute(
        select(func.count(SparePart.id)).where(
            SparePart.company_id == cid,
            SparePart.stock <= SparePart.min_stock,
        )
    )).scalar()

    # Notificaciones no leídas
    unread = (await db.execute(
        select(func.count(Notification.id)).where(
            Notification.user_id == current_user.id,
            Notification.is_read == False,
        )
    )).scalar()

    return {
        "work_orders": wo_counts,
        "equipment": {
            "total": eq_total,
            "in_maintenance": eq_maintenance,
            "operational": eq_total - eq_maintenance,
        },
        "users_active": users_count,
        "low_stock_parts": low_stock,
        "unread_notifications": unread,
    }
