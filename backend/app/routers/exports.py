"""
Router de exportación a Google Sheets.

Endpoints:
  POST /export/{module}/sheets  → Exporta un módulo a Google Sheets
    módulos: work-orders, spare-parts, equipments, maintenance-plans
"""
from __future__ import annotations

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.base import Company, Equipment, MaintenancePlan, SparePart, User, WorkOrder
from app.models.collaboration import ExportLog
from app.routers.auth import require_roles
from app.services import google_sheets as sheets_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/export", tags=["export"])

VALID_MODULES = {"work-orders", "spare-parts", "equipments", "maintenance-plans"}


class ExportResponse(BaseModel):
    sheet_id:      str
    sheet_url:     str
    rows_exported: int
    module:        str


# ─── Helpers ──────────────────────────────────────────────────────────────────

async def _get_company(db: AsyncSession, company_id: int) -> Company:
    result = await db.execute(select(Company).where(Company.id == company_id))
    company = result.scalars().first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")
    return company


async def _get_admin_email(db: AsyncSession, user_id: int) -> str:
    """Obtiene el email de un usuario por su ID."""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalars().first()
    return user.email if user else ""


# ─── Endpoint ─────────────────────────────────────────────────────────────────

@router.post("/{module}/sheets", response_model=ExportResponse)
async def export_module_to_sheets(
    module: str,
    current_user=Depends(require_roles("admin", "maintenance_manager", "purchasing", "warehouse")),
    db: AsyncSession = Depends(get_db),
):
    """
    Exporta un módulo a Google Sheets.
    Crea una nueva hoja en el Drive del admin y la comparte.
    """
    if module not in VALID_MODULES:
        raise HTTPException(
            status_code=400,
            detail=f"Módulo inválido: '{module}'. Válidos: {', '.join(VALID_MODULES)}"
        )

    company = await _get_company(db, current_user.company_id)
    admin_email = current_user.email

    if module == "work-orders":
        result = await db.execute(
            select(WorkOrder).where(WorkOrder.company_id == current_user.company_id)
        )
        items = [
            {
                "id": wo.id, "code": getattr(wo, "code", ""),
                "title": wo.title, "wo_type": getattr(wo, "wo_type", ""),
                "status": wo.status, "priority": getattr(wo, "priority", ""),
                "description": wo.description or "",
                "created_at": wo.created_at.strftime("%Y-%m-%d") if wo.created_at else "",
                "due_date": wo.due_date.strftime("%Y-%m-%d") if getattr(wo, "due_date", None) else "",
                "estimated_hours": getattr(wo, "estimated_hours", ""),
                "actual_hours": getattr(wo, "actual_hours", ""),
            }
            for wo in result.scalars().all()
        ]
        data = sheets_service.export_work_orders(items, company.name, admin_email)

    elif module == "spare-parts":
        result = await db.execute(
            select(SparePart).where(SparePart.company_id == current_user.company_id)
        )
        items = [
            {
                "id": sp.id, "code": sp.code, "name": sp.name,
                "brand": sp.equipment.brand if sp.equipment else "",
                "model": sp.equipment.model if sp.equipment else "",
                "current_stock": sp.stock, "min_stock": sp.min_stock,
                "location": sp.location or "",
                "unit_cost": sp.unit_cost or "",
                "is_low_stock": sp.stock <= sp.min_stock if sp.min_stock else False,
            }
            for sp in result.scalars().all()
        ]
        data = sheets_service.export_spare_parts(items, company.name, admin_email)

    elif module == "equipments":
        result = await db.execute(
            select(Equipment).where(Equipment.company_id == current_user.company_id)
        )
        items = [
            {
                "id": eq.id, "code": eq.code, "name": eq.name,
                "location": eq.location or "", "brand": eq.brand or "",
                "model": eq.model or "", "serial_number": getattr(eq, "serial_number", ""),
                "status": eq.status.value if hasattr(eq.status, "value") else str(eq.status),
                "purchase_date": eq.purchase_date.strftime("%Y-%m-%d") if getattr(eq, "purchase_date", None) else "",
                "notes": getattr(eq, "notes", ""),
            }
            for eq in result.scalars().all()
        ]
        data = sheets_service.export_equipments(items, company.name, admin_email)

    elif module == "maintenance-plans":
        result = await db.execute(
            select(MaintenancePlan)
            .join(Equipment, MaintenancePlan.equipment_id == Equipment.id)
            .where(Equipment.company_id == current_user.company_id)
        )
        items = [
            {
                "id": p.id, "title": p.title,
                "frequency": p.frequency.value if hasattr(p.frequency, "value") else str(p.frequency),
                "frequency_value": p.frequency_value,
                "next_due": p.next_due.strftime("%Y-%m-%d") if p.next_due else "",
                "is_active": p.is_active,
                "description": p.description or "",
            }
            for p in result.scalars().all()
        ]
        data = sheets_service.export_maintenance_plans(items, company.name, admin_email)

    else:
        raise HTTPException(status_code=400, detail="Módulo no soportado")

    if not data:
        raise HTTPException(
            status_code=502,
            detail="No se pudo exportar. Verificá la configuración de Google Service Account."
        )

    # Registrar exportación
    log = ExportLog(
        company_id=current_user.company_id,
        user_id=current_user.id,
        module=module,
        sheet_id=data.get("sheet_id"),
        sheet_url=data.get("sheet_url"),
        rows_exported=data.get("rows_exported"),
    )
    db.add(log)
    await db.commit()

    return ExportResponse(
        sheet_id=data["sheet_id"],
        sheet_url=data["sheet_url"],
        rows_exported=data["rows_exported"],
        module=module,
    )
