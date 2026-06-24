"""
Router de Depósito y Stock (Spare Parts).

Endpoints:
- GET    /spare-parts              Lista de repuestos con stock
- POST   /spare-parts              Crear repuesto
- GET    /spare-parts/{id}         Detalle + historial movimientos
- PUT    /spare-parts/{id}         Editar repuesto
- POST   /spare-parts/{id}/entry   Entrada de stock (compra/ajuste)
- POST   /spare-parts/{id}/exit    Salida de stock (entrega)

- GET    /spare-part-requests                Lista de pedidos
- POST   /spare-part-requests                Técnico pide repuesto
- PUT    /spare-part-requests/{id}/approve   Depósito aprueba
- PUT    /spare-part-requests/{id}/deliver   Depósito entrega (descuenta stock)
- PUT    /spare-part-requests/{id}/reject    Rechazar pedido
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
    MovementType, Notification, RequestStatus,
    SparePart, SparePartRequest, StockMovement, User,
)
from app.routers.auth import get_current_user, require_roles

router = APIRouter(prefix="/spare-parts", tags=["spare-parts"])
requests_router = APIRouter(prefix="/spare-part-requests", tags=["spare-part-requests"])


# ─── Schemas ──────────────────────────────────────────────────────────────────

class SparePartCreate(BaseModel):
    code: str
    name: str
    description: Optional[str] = None
    unit: str = "unidad"
    stock: float = 0
    min_stock: float = 0
    location: Optional[str] = None
    unit_cost: Optional[float] = None
    equipment_id: Optional[int] = None
    sector: Optional[str] = None


class SparePartUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    unit: Optional[str] = None
    min_stock: Optional[float] = None
    location: Optional[str] = None
    unit_cost: Optional[float] = None
    equipment_id: Optional[int] = None
    sector: Optional[str] = None


class StockMovementCreate(BaseModel):
    quantity: float
    notes: Optional[str] = None


class MovementOut(BaseModel):
    id: int
    movement_type: str
    quantity: float
    notes: Optional[str]
    created_at: datetime
    user_name: Optional[str] = None

    class Config:
        from_attributes = True


class SparePartOut(BaseModel):
    id: int
    company_id: int
    code: str
    name: str
    description: Optional[str]
    unit: str
    stock: float
    min_stock: float
    location: Optional[str]
    unit_cost: Optional[float]
    equipment_id: Optional[int] = None
    equipment_name: Optional[str] = None
    sector: Optional[str] = None
    is_low_stock: bool
    created_at: datetime
    movements: List[MovementOut] = []

    class Config:
        from_attributes = True


class RequestCreate(BaseModel):
    spare_part_id: int
    quantity: float
    work_order_id: Optional[int] = None
    notes: Optional[str] = None


class RequestOut(BaseModel):
    id: int
    spare_part_id: int
    spare_part_name: Optional[str] = None
    spare_part_code: Optional[str] = None
    work_order_id: Optional[int]
    work_order_title: Optional[str] = None
    requested_by_id: Optional[int]
    requested_by_name: Optional[str] = None
    quantity: float
    status: str
    notes: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _sp_to_out(sp: SparePart) -> SparePartOut:
    movements = [
        MovementOut(
            id=m.id,
            movement_type=m.movement_type if isinstance(m.movement_type, str) else m.movement_type.value,
            quantity=m.quantity,
            notes=m.notes,
            created_at=m.created_at,
            user_name=(m.user.full_name or m.user.email) if m.user else None,
        )
        for m in sorted(sp.movements or [], key=lambda x: x.created_at, reverse=True)
    ]
    return SparePartOut(
        id=sp.id,
        company_id=sp.company_id,
        code=sp.code,
        name=sp.name,
        description=sp.description,
        unit=sp.unit,
        stock=sp.stock,
        min_stock=sp.min_stock,
        location=sp.location,
        unit_cost=sp.unit_cost,
        equipment_id=sp.equipment_id,
        equipment_name=sp.equipment.name if sp.equipment else None,
        sector=sp.sector,
        is_low_stock=sp.stock <= sp.min_stock,
        created_at=sp.created_at,
        movements=movements,
    )


def _req_to_out(req: SparePartRequest) -> RequestOut:
    return RequestOut(
        id=req.id,
        spare_part_id=req.spare_part_id,
        spare_part_name=req.spare_part.name if req.spare_part else None,
        spare_part_code=req.spare_part.code if req.spare_part else None,
        work_order_id=req.work_order_id,
        work_order_title=req.work_order.title if req.work_order else None,
        requested_by_id=req.requested_by_id,
        requested_by_name=(req.requested_by.full_name or req.requested_by.email) if req.requested_by else None,
        quantity=req.quantity,
        status=req.status if isinstance(req.status, str) else req.status.value,
        notes=req.notes,
        created_at=req.created_at,
    )


async def _notify(db: AsyncSession, user_id: int, title: str, message: str, link: str = None):
    n = Notification(user_id=user_id, title=title, message=message, link=link)
    db.add(n)


def _load_sp_query(company_id: int):
    return (
        select(SparePart)
        .options(
            selectinload(SparePart.movements).selectinload(StockMovement.user),
        )
        .where(SparePart.company_id == company_id)
    )


def _load_req_query(company_id: int):
    from app.models.base import WorkOrder
    return (
        select(SparePartRequest)
        .options(
            selectinload(SparePartRequest.spare_part),
            selectinload(SparePartRequest.requested_by),
            selectinload(SparePartRequest.work_order),
        )
        .join(SparePart, SparePartRequest.spare_part_id == SparePart.id)
        .where(SparePart.company_id == company_id)
    )


# ─── Spare Parts Endpoints ────────────────────────────────────────────────────

@router.get("/", response_model=List[SparePartOut])
async def list_spare_parts(
    low_stock_only: bool = False,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    query = _load_sp_query(current_user.company_id).order_by(SparePart.name)
    result = await db.execute(query)
    parts = result.scalars().all()
    if low_stock_only:
        parts = [p for p in parts if p.stock <= p.min_stock]
    return [_sp_to_out(p) for p in parts]


@router.post("/", response_model=SparePartOut, status_code=201)
async def create_spare_part(
    payload: SparePartCreate,
    current_user: User = Depends(require_roles("admin", "warehouse", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    # Verificar código único en la empresa
    existing = await db.execute(
        select(SparePart).where(
            SparePart.company_id == current_user.company_id,
            SparePart.code == payload.code,
        )
    )
    if existing.scalars().first():
        raise HTTPException(status_code=400, detail=f"Ya existe un repuesto con código '{payload.code}'")

    sp = SparePart(
        company_id=current_user.company_id,
        code=payload.code,
        name=payload.name,
        description=payload.description,
        unit=payload.unit,
        stock=payload.stock,
        min_stock=payload.min_stock,
        location=payload.location,
        unit_cost=payload.unit_cost,
        equipment_id=payload.equipment_id,
        sector=payload.sector,
    )
    db.add(sp)

    # Si se carga stock inicial, registrar movimiento de entrada
    if payload.stock > 0:
        await db.flush()
        mov = StockMovement(
            spare_part_id=sp.id,
            user_id=current_user.id,
            movement_type=MovementType.entry,
            quantity=payload.stock,
            notes="Stock inicial al crear el repuesto",
        )
        db.add(mov)

    await db.commit()
    result = await db.execute(_load_sp_query(current_user.company_id).where(SparePart.id == sp.id))
    return _sp_to_out(result.scalars().first())


@router.get("/{sp_id}", response_model=SparePartOut)
async def get_spare_part(
    sp_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        _load_sp_query(current_user.company_id).where(SparePart.id == sp_id)
    )
    sp = result.scalars().first()
    if not sp:
        raise HTTPException(status_code=404, detail="Repuesto no encontrado")
    return _sp_to_out(sp)


@router.put("/{sp_id}", response_model=SparePartOut)
async def update_spare_part(
    sp_id: int,
    payload: SparePartUpdate,
    current_user: User = Depends(require_roles("admin", "warehouse", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        _load_sp_query(current_user.company_id).where(SparePart.id == sp_id)
    )
    sp = result.scalars().first()
    if not sp:
        raise HTTPException(status_code=404, detail="Repuesto no encontrado")

    if payload.name is not None: sp.name = payload.name
    if payload.description is not None: sp.description = payload.description
    if payload.unit is not None: sp.unit = payload.unit
    if payload.min_stock is not None: sp.min_stock = payload.min_stock
    if payload.location is not None: sp.location = payload.location
    if payload.unit_cost is not None: sp.unit_cost = payload.unit_cost
    if payload.equipment_id is not None: sp.equipment_id = payload.equipment_id
    if payload.sector is not None: sp.sector = payload.sector

    await db.commit()
    result = await db.execute(_load_sp_query(current_user.company_id).where(SparePart.id == sp_id))
    return _sp_to_out(result.scalars().first())


@router.delete("/{sp_id}", status_code=204)
async def delete_spare_part(
    sp_id: int,
    current_user: User = Depends(require_roles("admin", "warehouse")),
    db: AsyncSession = Depends(get_db),
):
    """Eliminar un repuesto (solo si no tiene movimientos asociados o forzar eliminación)."""
    result = await db.execute(
        _load_sp_query(current_user.company_id).where(SparePart.id == sp_id)
    )
    sp = result.scalars().first()
    if not sp:
        raise HTTPException(status_code=404, detail="Repuesto no encontrado")
    await db.delete(sp)
    await db.commit()


# ─── Batch operations ────────────────────────────────────────────────────────

class BatchMovementItem(BaseModel):
    spare_part_id: int
    quantity: float
    notes: Optional[str] = None


class BatchMovementIn(BaseModel):
    movement_type: str  # "entry" | "exit"
    items: List[BatchMovementItem]


class BatchMovementResult(BaseModel):
    processed: int
    errors: List[str] = []


@router.post("/batch-movement", response_model=BatchMovementResult)
async def batch_stock_movement(
    payload: BatchMovementIn,
    current_user: User = Depends(require_roles("admin", "warehouse")),
    db: AsyncSession = Depends(get_db),
):
    """Registrar entrada o salida de stock de múltiples artículos a la vez."""
    if payload.movement_type not in ("entry", "exit"):
        raise HTTPException(status_code=400, detail="Tipo de movimiento inválido. Usar 'entry' o 'exit'")

    result = BatchMovementResult(processed=0, errors=[])

    for item in payload.items:
        sp_result = await db.execute(
            _load_sp_query(current_user.company_id).where(SparePart.id == item.spare_part_id)
        )
        sp = sp_result.scalars().first()
        if not sp:
            result.errors.append(f"Repuesto ID {item.spare_part_id} no encontrado")
            continue

        if payload.movement_type == "exit" and sp.stock < item.quantity:
            result.errors.append(
                f"Stock insuficiente para '{sp.name}': disponible {sp.stock}, solicitado {item.quantity}"
            )
            continue

        if payload.movement_type == "entry":
            sp.stock += item.quantity
        else:
            sp.stock -= item.quantity

        mov = StockMovement(
            spare_part_id=sp.id,
            user_id=current_user.id,
            movement_type=MovementType.entry if payload.movement_type == "entry" else MovementType.exit,
            quantity=item.quantity,
            notes=item.notes or f"Movimiento batch ({payload.movement_type})",
        )
        db.add(mov)
        result.processed += 1

    await db.commit()
    return result


@router.post("/{sp_id}/entry", response_model=SparePartOut)
async def stock_entry(
    sp_id: int,
    payload: StockMovementCreate,
    current_user: User = Depends(require_roles("admin", "warehouse", "purchasing")),
    db: AsyncSession = Depends(get_db),
):
    """Entrada de stock: recepción de compra, devolución, ajuste positivo."""
    result = await db.execute(
        _load_sp_query(current_user.company_id).where(SparePart.id == sp_id)
    )
    sp = result.scalars().first()
    if not sp:
        raise HTTPException(status_code=404, detail="Repuesto no encontrado")

    sp.stock += payload.quantity
    mov = StockMovement(
        spare_part_id=sp.id,
        user_id=current_user.id,
        movement_type=MovementType.entry,
        quantity=payload.quantity,
        notes=payload.notes,
    )
    db.add(mov)
    await db.commit()
    result = await db.execute(_load_sp_query(current_user.company_id).where(SparePart.id == sp_id))
    return _sp_to_out(result.scalars().first())


@router.post("/{sp_id}/exit", response_model=SparePartOut)
async def stock_exit(
    sp_id: int,
    payload: StockMovementCreate,
    current_user: User = Depends(require_roles("admin", "warehouse")),
    db: AsyncSession = Depends(get_db),
):
    """Salida de stock: entrega manual, baja."""
    result = await db.execute(
        _load_sp_query(current_user.company_id).where(SparePart.id == sp_id)
    )
    sp = result.scalars().first()
    if not sp:
        raise HTTPException(status_code=404, detail="Repuesto no encontrado")

    if sp.stock < payload.quantity:
        raise HTTPException(status_code=400, detail=f"Stock insuficiente. Disponible: {sp.stock} {sp.unit}")

    sp.stock -= payload.quantity
    mov = StockMovement(
        spare_part_id=sp.id,
        user_id=current_user.id,
        movement_type=MovementType.exit,
        quantity=payload.quantity,
        notes=payload.notes,
    )
    db.add(mov)

    # Alerta si queda en stock bajo
    if sp.stock <= sp.min_stock:
        # Notificar a todos los admin/warehouse de la empresa
        admins = await db.execute(
            select(User).join(User.user_roles).where(
                User.company_id == current_user.company_id,
            )
        )
        for u in admins.scalars().all():
            roles = [ur.role for ur in u.user_roles]
            if any(r in ['admin', 'warehouse', 'purchasing'] for r in roles):
                await _notify(
                    db, u.id,
                    "⚠️ Stock bajo",
                    f"El repuesto '{sp.name}' tiene stock bajo: {sp.stock} {sp.unit} (mínimo: {sp.min_stock})",
                    "/spare-parts",
                )

    await db.commit()
    result = await db.execute(_load_sp_query(current_user.company_id).where(SparePart.id == sp_id))
    return _sp_to_out(result.scalars().first())


# ─── Spare Part Requests Endpoints ───────────────────────────────────────────

@requests_router.get("/", response_model=List[RequestOut])
async def list_requests(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    query = _load_req_query(current_user.company_id).order_by(SparePartRequest.created_at.desc())
    user_roles = [ur.role.value if hasattr(ur.role, 'value') else str(ur.role) for ur in current_user.user_roles]

    # Técnicos (sin roles de gestión) solo ven sus propios pedidos
    management_roles = {"admin", "maintenance_manager", "warehouse", "purchasing"}
    has_management = any(r in management_roles for r in user_roles)
    if not has_management and "technician" in user_roles:
        query = query.where(SparePartRequest.requested_by_id == current_user.id)

    result = await db.execute(query)
    return [_req_to_out(r) for r in result.scalars().all()]


@requests_router.post("/", response_model=RequestOut, status_code=201)
async def create_request(
    payload: RequestCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Técnico pide un repuesto al depósito."""
    # Verificar que el repuesto existe y pertenece a la empresa
    sp_result = await db.execute(
        select(SparePart).where(
            SparePart.id == payload.spare_part_id,
            SparePart.company_id == current_user.company_id,
        )
    )
    sp = sp_result.scalars().first()
    if not sp:
        raise HTTPException(status_code=404, detail="Repuesto no encontrado")

    req = SparePartRequest(
        spare_part_id=payload.spare_part_id,
        work_order_id=payload.work_order_id,
        requested_by_id=current_user.id,
        quantity=payload.quantity,
        notes=payload.notes,
        status=RequestStatus.pending,
    )
    db.add(req)
    await db.flush()

    # Notificar al depósito
    warehouse_users = await db.execute(
        select(User).join(User.user_roles).where(
            User.company_id == current_user.company_id,
        )
    )
    for u in warehouse_users.scalars().all():
        roles = [ur.role for ur in u.user_roles]
        if any(r in ['admin', 'warehouse'] for r in roles):
            await _notify(
                db, u.id,
                "📦 Nuevo pedido de repuesto",
                f"{current_user.full_name or current_user.email} solicita {payload.quantity} x {sp.name}",
                "/spare-part-requests",
            )

    await db.commit()
    result = await db.execute(
        _load_req_query(current_user.company_id).where(SparePartRequest.id == req.id)
    )
    return _req_to_out(result.scalars().first())


@requests_router.put("/{req_id}/approve", response_model=RequestOut)
async def approve_request(
    req_id: int,
    current_user: User = Depends(require_roles("admin", "warehouse", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        _load_req_query(current_user.company_id).where(SparePartRequest.id == req_id)
    )
    req = result.scalars().first()
    if not req:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")
    if req.status != RequestStatus.pending:
        raise HTTPException(status_code=400, detail="Solo se pueden aprobar pedidos pendientes")

    req.status = RequestStatus.approved

    if req.requested_by_id:
        await _notify(
            db, req.requested_by_id,
            "✅ Pedido aprobado",
            f"Tu pedido de {req.quantity} x {req.spare_part.name} fue aprobado",
            "/spare-part-requests",
        )

    await db.commit()
    result = await db.execute(_load_req_query(current_user.company_id).where(SparePartRequest.id == req_id))
    return _req_to_out(result.scalars().first())


@requests_router.put("/{req_id}/deliver", response_model=RequestOut)
async def deliver_request(
    req_id: int,
    current_user: User = Depends(require_roles("admin", "warehouse")),
    db: AsyncSession = Depends(get_db),
):
    """Entrega física del repuesto. Descuenta del stock automáticamente."""
    result = await db.execute(
        _load_req_query(current_user.company_id).where(SparePartRequest.id == req_id)
    )
    req = result.scalars().first()
    if not req:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")
    if req.status not in [RequestStatus.pending, RequestStatus.approved]:
        raise HTTPException(status_code=400, detail="Pedido ya entregado o rechazado")

    sp = req.spare_part
    if sp.stock < req.quantity:
        raise HTTPException(
            status_code=400,
            detail=f"Stock insuficiente. Disponible: {sp.stock} {sp.unit}, solicitado: {req.quantity}"
        )

    sp.stock -= req.quantity
    req.status = RequestStatus.delivered

    mov = StockMovement(
        spare_part_id=sp.id,
        user_id=current_user.id,
        movement_type=MovementType.exit,
        quantity=req.quantity,
        notes=f"Entrega por pedido #{req.id}" + (f" - OT #{req.work_order_id}" if req.work_order_id else ""),
    )
    db.add(mov)

    if req.requested_by_id:
        await _notify(
            db, req.requested_by_id,
            "📦 Repuesto entregado",
            f"Se entregaron {req.quantity} x {sp.name}",
            "/spare-part-requests",
        )

    # Alerta stock bajo
    if sp.stock <= sp.min_stock:
        await _notify(
            db, current_user.id,
            "⚠️ Stock bajo tras entrega",
            f"'{sp.name}' quedó con {sp.stock} {sp.unit} (mínimo: {sp.min_stock})",
            "/spare-parts",
        )

    await db.commit()
    result = await db.execute(_load_req_query(current_user.company_id).where(SparePartRequest.id == req_id))
    return _req_to_out(result.scalars().first())


@requests_router.put("/{req_id}/reject", response_model=RequestOut)
async def reject_request(
    req_id: int,
    current_user: User = Depends(require_roles("admin", "warehouse")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        _load_req_query(current_user.company_id).where(SparePartRequest.id == req_id)
    )
    req = result.scalars().first()
    if not req:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")
    if req.status not in [RequestStatus.pending, RequestStatus.approved]:
        raise HTTPException(status_code=400, detail="Solo se pueden rechazar pedidos pendientes o aprobados")

    req.status = RequestStatus.rejected

    if req.requested_by_id:
        await _notify(
            db, req.requested_by_id,
            "❌ Pedido rechazado",
            f"Tu pedido de {req.quantity} x {req.spare_part.name} fue rechazado",
            "/spare-part-requests",
        )

    await db.commit()
    result = await db.execute(_load_req_query(current_user.company_id).where(SparePartRequest.id == req_id))
    return _req_to_out(result.scalars().first())
