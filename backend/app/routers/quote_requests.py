"""
Router de Solicitudes de Cotización (Quote Requests).

Flujo:
- Depósito/Compras crea una solicitud de cotización para un repuesto/insumo
- Se envía a proveedores para que coticen
- El proveedor responde con precio → estado "quoted"
- Jefe/Admin aprueba o rechaza la cotización
- Si se aprueba, se puede convertir a Orden de Compra

Endpoints:
- GET    /quote-requests              Listar solicitudes
- POST   /quote-requests              Crear solicitud
- GET    /quote-requests/{id}         Detalle
- PUT    /quote-requests/{id}/quote   Registrar cotización del proveedor
- PUT    /quote-requests/{id}/approve Aprobar cotización
- PUT    /quote-requests/{id}/reject  Rechazar cotización
- POST   /quote-requests/{id}/convert Convertir a Orden de Compra
"""
from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models.base import (
    Notification, POItem, POStatus, PurchaseOrder,
    QuoteRequest, QuoteRequestStatus, SparePart, Supplier, User,
)
from app.routers.auth import get_current_user, require_roles

router = APIRouter(prefix="/quote-requests", tags=["quote-requests"])


# ─── Schemas ──────────────────────────────────────────────────────────────────

class QuoteRequestCreate(BaseModel):
    spare_part_id: Optional[int] = None
    supplier_id: Optional[int] = None
    description: str
    quantity: float
    unit: str = "unidad"
    notes: Optional[str] = None


class QuoteRequestQuote(BaseModel):
    quoted_price: float
    notes: Optional[str] = None


class QuoteRequestOut(BaseModel):
    id: int
    spare_part_id: Optional[int]
    spare_part_name: Optional[str] = None
    spare_part_code: Optional[str] = None
    supplier_id: Optional[int]
    supplier_name: Optional[str] = None
    requested_by_id: Optional[int]
    requested_by_name: Optional[str] = None
    description: str
    quantity: float
    unit: str
    status: str
    quoted_price: Optional[float]
    notes: Optional[str]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _qr_to_out(qr: QuoteRequest) -> QuoteRequestOut:
    return QuoteRequestOut(
        id=qr.id,
        spare_part_id=qr.spare_part_id,
        spare_part_name=qr.spare_part.name if qr.spare_part else None,
        spare_part_code=qr.spare_part.code if qr.spare_part else None,
        supplier_id=qr.supplier_id,
        supplier_name=qr.supplier.name if qr.supplier else None,
        requested_by_id=qr.requested_by_id,
        requested_by_name=(qr.requested_by.full_name or qr.requested_by.email) if qr.requested_by else None,
        description=qr.description,
        quantity=qr.quantity,
        unit=qr.unit,
        status=qr.status if isinstance(qr.status, str) else qr.status.value,
        quoted_price=qr.quoted_price,
        notes=qr.notes,
        created_at=qr.created_at,
        updated_at=qr.updated_at,
    )


def _load_qr_query(company_id: int):
    return (
        select(QuoteRequest)
        .options(
            selectinload(QuoteRequest.spare_part),
            selectinload(QuoteRequest.supplier),
            selectinload(QuoteRequest.requested_by),
        )
        .where(QuoteRequest.company_id == company_id)
    )


async def _notify(db: AsyncSession, user_id: int, title: str, message: str, link: str = None):
    n = Notification(user_id=user_id, title=title, message=message, link=link)
    db.add(n)


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/", response_model=List[QuoteRequestOut])
async def list_quote_requests(
    status: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    query = _load_qr_query(current_user.company_id).order_by(QuoteRequest.created_at.desc())
    if status:
        query = query.where(QuoteRequest.status == status)
    result = await db.execute(query)
    return [_qr_to_out(r) for r in result.scalars().all()]


@router.post("/", response_model=QuoteRequestOut, status_code=201)
async def create_quote_request(
    payload: QuoteRequestCreate,
    current_user: User = Depends(require_roles("admin", "warehouse", "purchasing", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    """Crear solicitud de cotización a proveedores."""
    qr = QuoteRequest(
        company_id=current_user.company_id,
        spare_part_id=payload.spare_part_id,
        supplier_id=payload.supplier_id,
        requested_by_id=current_user.id,
        description=payload.description,
        quantity=payload.quantity,
        unit=payload.unit,
        notes=payload.notes,
        status=QuoteRequestStatus.pending,
    )
    db.add(qr)
    await db.flush()

    # Notificar a compras y admin
    users_result = await db.execute(
        select(User).join(User.user_roles).where(
            User.company_id == current_user.company_id,
            User.is_active == True,
        )
    )
    for u in users_result.scalars().all():
        roles = [ur.role.value if hasattr(ur.role, 'value') else str(ur.role) for ur in u.user_roles]
        if any(r in ('admin', 'purchasing') for r in roles):
            await _notify(
                db, u.id,
                "📋 Nueva solicitud de cotización",
                f"{current_user.full_name or current_user.email} solicita cotizar: {payload.description} x{payload.quantity}",
                "/quote-requests",
            )

    await db.commit()
    result = await db.execute(_load_qr_query(current_user.company_id).where(QuoteRequest.id == qr.id))
    return _qr_to_out(result.scalars().first())


@router.get("/{qr_id}", response_model=QuoteRequestOut)
async def get_quote_request(
    qr_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(_load_qr_query(current_user.company_id).where(QuoteRequest.id == qr_id))
    qr = result.scalars().first()
    if not qr:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")
    return _qr_to_out(qr)


@router.put("/{qr_id}/quote", response_model=QuoteRequestOut)
async def quote_request(
    qr_id: int,
    payload: QuoteRequestQuote,
    current_user: User = Depends(require_roles("admin", "purchasing")),
    db: AsyncSession = Depends(get_db),
):
    """Registrar la cotización recibida del proveedor."""
    result = await db.execute(_load_qr_query(current_user.company_id).where(QuoteRequest.id == qr_id))
    qr = result.scalars().first()
    if not qr:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")
    if qr.status != QuoteRequestStatus.pending:
        raise HTTPException(status_code=400, detail="Solo se pueden cotizar solicitudes pendientes")

    qr.quoted_price = payload.quoted_price
    qr.status = QuoteRequestStatus.quoted
    if payload.notes:
        qr.notes = (qr.notes or "") + f"\n[Cotización]: {payload.notes}"

    # Notificar al solicitante
    if qr.requested_by_id:
        await _notify(
            db, qr.requested_by_id,
            "💰 Cotización recibida",
            f"El proveedor cotizó '{qr.description}' a ${payload.quoted_price:.2f}",
            "/quote-requests",
        )

    await db.commit()
    result = await db.execute(_load_qr_query(current_user.company_id).where(QuoteRequest.id == qr_id))
    return _qr_to_out(result.scalars().first())


@router.put("/{qr_id}/approve", response_model=QuoteRequestOut)
async def approve_quote_request(
    qr_id: int,
    current_user: User = Depends(require_roles("admin", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    """Aprobar la cotización para proceder a compra."""
    result = await db.execute(_load_qr_query(current_user.company_id).where(QuoteRequest.id == qr_id))
    qr = result.scalars().first()
    if not qr:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")
    if qr.status != QuoteRequestStatus.quoted:
        raise HTTPException(status_code=400, detail="Solo se pueden aprobar cotizaciones ya cotizadas")

    qr.status = QuoteRequestStatus.approved

    # Notificar a compras
    users_result = await db.execute(
        select(User).join(User.user_roles).where(
            User.company_id == current_user.company_id,
            User.is_active == True,
        )
    )
    for u in users_result.scalars().all():
        roles = [ur.role.value if hasattr(ur.role, 'value') else str(ur.role) for ur in u.user_roles]
        if any(r in ('admin', 'purchasing') for r in roles):
            await _notify(
                db, u.id,
                "✅ Cotización aprobada",
                f"Cotización de '{qr.description}' aprobada — proceder a generar OC",
                "/quote-requests",
            )

    await db.commit()
    result = await db.execute(_load_qr_query(current_user.company_id).where(QuoteRequest.id == qr_id))
    return _qr_to_out(result.scalars().first())


@router.put("/{qr_id}/reject", response_model=QuoteRequestOut)
async def reject_quote_request(
    qr_id: int,
    current_user: User = Depends(require_roles("admin", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    """Rechazar la cotización."""
    result = await db.execute(_load_qr_query(current_user.company_id).where(QuoteRequest.id == qr_id))
    qr = result.scalars().first()
    if not qr:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")
    if qr.status not in [QuoteRequestStatus.pending, QuoteRequestStatus.quoted]:
        raise HTTPException(status_code=400, detail="Solo se pueden rechazar solicitudes pendientes o cotizadas")

    qr.status = QuoteRequestStatus.rejected

    if qr.requested_by_id:
        await _notify(
            db, qr.requested_by_id,
            "❌ Cotización rechazada",
            f"La cotización de '{qr.description}' fue rechazada",
            "/quote-requests",
        )

    await db.commit()
    result = await db.execute(_load_qr_query(current_user.company_id).where(QuoteRequest.id == qr_id))
    return _qr_to_out(result.scalars().first())


@router.post("/{qr_id}/convert", response_model=dict)
async def convert_to_purchase_order(
    qr_id: int,
    current_user: User = Depends(require_roles("admin", "purchasing")),
    db: AsyncSession = Depends(get_db),
):
    """Convertir una cotización aprobada en Orden de Compra."""
    result = await db.execute(_load_qr_query(current_user.company_id).where(QuoteRequest.id == qr_id))
    qr = result.scalars().first()
    if not qr:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")
    if qr.status != QuoteRequestStatus.approved:
        raise HTTPException(status_code=400, detail="Solo se pueden convertir cotizaciones aprobadas")

    # Crear la OC
    po = PurchaseOrder(
        company_id=current_user.company_id,
        supplier_id=qr.supplier_id,
        created_by_id=current_user.id,
        status=POStatus.draft,
        notes=f"Generada desde cotización #{qr.id}: {qr.description}",
    )
    db.add(po)
    await db.flush()

    # Agregar el ítem
    item = POItem(
        purchase_order_id=po.id,
        spare_part_id=qr.spare_part_id,
        description=qr.description,
        quantity=qr.quantity,
        unit_price=qr.quoted_price,
        quantity_received=0,
    )
    db.add(item)

    # Marcar la cotización como convertida
    qr.status = QuoteRequestStatus.converted

    await db.commit()
    return {"purchase_order_id": po.id, "message": "OC creada exitosamente"}