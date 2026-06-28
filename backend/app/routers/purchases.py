"""
Router de Módulo de Compras.

Endpoints:
── Proveedores ────────────────────────────────────────────────
GET    /suppliers                    Lista proveedores
POST   /suppliers                    Crear proveedor
GET    /suppliers/{id}               Detalle
PUT    /suppliers/{id}               Editar
DELETE /suppliers/{id}               Eliminar (solo admin)

── Órdenes de Compra ──────────────────────────────────────────
GET    /purchase-orders              Lista OC
POST   /purchase-orders              Crear OC (con ítems)
GET    /purchase-orders/{id}         Detalle con ítems e ítems recibidos
PUT    /purchase-orders/{id}         Editar encabezado
PUT    /purchase-orders/{id}/status  Cambiar estado (enviar, cancelar)
POST   /purchase-orders/{id}/receive Registrar recepción parcial/total → ingresa stock

── Facturas ───────────────────────────────────────────────────
GET    /invoices                     Lista facturas
POST   /invoices                     Cargar factura
PUT    /invoices/{id}/pay            Marcar pagada
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
    Invoice, InvoiceStatus, MovementType, Notification, POItem,
    POStatus, PurchaseOrder, SparePart, StockMovement, Supplier, User,
)
from app.routers.auth import get_current_user, require_roles

suppliers_router = APIRouter(prefix="/suppliers", tags=["compras"])
po_router = APIRouter(prefix="/purchase-orders", tags=["compras"])
invoices_router = APIRouter(prefix="/invoices", tags=["compras"])


# ─── Schemas ──────────────────────────────────────────────────────────────────

class SupplierCreate(BaseModel):
    name: str
    contact: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    notes: Optional[str] = None


class SupplierUpdate(BaseModel):
    name: Optional[str] = None
    contact: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    notes: Optional[str] = None


class SupplierOut(BaseModel):
    id: int
    company_id: int
    name: str
    contact: Optional[str]
    email: Optional[str]
    phone: Optional[str]
    address: Optional[str]
    notes: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


class POItemCreate(BaseModel):
    spare_part_id: Optional[int] = None
    description: str
    quantity: float
    unit_price: Optional[float] = None


class POItemOut(BaseModel):
    id: int
    spare_part_id: Optional[int]
    spare_part_name: Optional[str] = None
    spare_part_code: Optional[str] = None
    description: str
    quantity: float
    quantity_received: float
    unit_price: Optional[float]
    subtotal: Optional[float] = None

    class Config:
        from_attributes = True


class POCreate(BaseModel):
    supplier_id: Optional[int] = None
    po_number: Optional[str] = None
    notes: Optional[str] = None
    items: List[POItemCreate] = []


class POUpdate(BaseModel):
    supplier_id: Optional[int] = None
    po_number: Optional[str] = None
    notes: Optional[str] = None


class POStatusUpdate(BaseModel):
    status: str   # sent | cancelled


class ReceiveItemIn(BaseModel):
    po_item_id: int
    quantity_received: float
    notes: Optional[str] = None


class POReceive(BaseModel):
    items: List[ReceiveItemIn]


class POOut(BaseModel):
    id: int
    company_id: int
    supplier_id: Optional[int]
    supplier_name: Optional[str] = None
    created_by_id: Optional[int]
    created_by_name: Optional[str] = None
    po_number: Optional[str]
    status: str
    notes: Optional[str]
    total_amount: Optional[float]
    items: List[POItemOut] = []
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class InvoiceCreate(BaseModel):
    purchase_order_id: Optional[int] = None
    invoice_number: str
    amount: float
    due_date: Optional[datetime] = None
    notes: Optional[str] = None


class InvoiceOut(BaseModel):
    id: int
    purchase_order_id: Optional[int]
    po_number: Optional[str] = None
    invoice_number: str
    amount: float
    status: str
    due_date: Optional[datetime]
    paid_at: Optional[datetime]
    notes: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _po_item_to_out(item: POItem) -> POItemOut:
    subtotal = None
    if item.unit_price is not None:
        subtotal = round(item.unit_price * item.quantity, 2)
    return POItemOut(
        id=item.id,
        spare_part_id=item.spare_part_id,
        spare_part_name=item.spare_part.name if item.spare_part else None,
        spare_part_code=item.spare_part.code if item.spare_part else None,
        description=item.description,
        quantity=item.quantity,
        quantity_received=item.quantity_received or 0,
        unit_price=item.unit_price,
        subtotal=subtotal,
    )


def _po_to_out(po: PurchaseOrder) -> POOut:
    total = None
    if po.items:
        prices = [i.unit_price * i.quantity for i in po.items if i.unit_price]
        if prices:
            total = round(sum(prices), 2)
    return POOut(
        id=po.id,
        company_id=po.company_id,
        supplier_id=po.supplier_id,
        supplier_name=po.supplier.name if po.supplier else None,
        created_by_id=po.created_by_id,
        created_by_name=(po.created_by.full_name or po.created_by.email) if po.created_by else None,
        po_number=po.po_number,
        status=po.status if isinstance(po.status, str) else po.status.value,
        notes=po.notes,
        total_amount=total,
        items=[_po_item_to_out(i) for i in po.items],
        created_at=po.created_at,
        updated_at=po.updated_at,
    )


def _load_po_query(company_id: int):
    return (
        select(PurchaseOrder)
        .options(
            selectinload(PurchaseOrder.supplier),
            selectinload(PurchaseOrder.created_by),
            selectinload(PurchaseOrder.items).selectinload(POItem.spare_part),
            selectinload(PurchaseOrder.invoices),
        )
        .where(PurchaseOrder.company_id == company_id)
    )


# ═══════════════════════════════════════════════════════════════════════════════
# PROVEEDORES
# ═══════════════════════════════════════════════════════════════════════════════

@suppliers_router.get("/", response_model=List[SupplierOut])
async def list_suppliers(
    skip: int = 0,
    limit: int = 200,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Supplier)
        .where(Supplier.company_id == current_user.company_id)
        .order_by(Supplier.name)
        .offset(skip).limit(limit)
    )
    return result.scalars().all()


@suppliers_router.post("/", response_model=SupplierOut, status_code=201)
async def create_supplier(
    payload: SupplierCreate,
    current_user: User = Depends(require_roles("admin", "purchasing", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    sup = Supplier(company_id=current_user.company_id, **payload.model_dump())
    db.add(sup)
    await db.commit()
    await db.refresh(sup)
    return sup


@suppliers_router.get("/{sup_id}", response_model=SupplierOut)
async def get_supplier(
    sup_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Supplier).where(
            Supplier.id == sup_id,
            Supplier.company_id == current_user.company_id,
        )
    )
    sup = result.scalars().first()
    if not sup:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    return sup


@suppliers_router.put("/{sup_id}", response_model=SupplierOut)
async def update_supplier(
    sup_id: int,
    payload: SupplierUpdate,
    current_user: User = Depends(require_roles("admin", "purchasing", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Supplier).where(
            Supplier.id == sup_id,
            Supplier.company_id == current_user.company_id,
        )
    )
    sup = result.scalars().first()
    if not sup:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    for k, v in payload.model_dump(exclude_none=True).items():
        setattr(sup, k, v)
    await db.commit()
    await db.refresh(sup)
    return sup


@suppliers_router.delete("/{sup_id}", status_code=204)
async def delete_supplier(
    sup_id: int,
    current_user: User = Depends(require_roles("admin")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Supplier).where(
            Supplier.id == sup_id,
            Supplier.company_id == current_user.company_id,
        )
    )
    sup = result.scalars().first()
    if not sup:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    await db.delete(sup)
    await db.commit()


# ═══════════════════════════════════════════════════════════════════════════════
# ÓRDENES DE COMPRA
# ═══════════════════════════════════════════════════════════════════════════════

@po_router.get("/", response_model=List[POOut])
async def list_purchase_orders(
    status: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    query = _load_po_query(current_user.company_id).order_by(
        PurchaseOrder.created_at.desc()
    ).offset(skip).limit(limit)
    if status:
        query = _load_po_query(current_user.company_id).where(
            PurchaseOrder.status == status
        ).order_by(PurchaseOrder.created_at.desc()).offset(skip).limit(limit)
    result = await db.execute(query)
    return [_po_to_out(po) for po in result.scalars().all()]


@po_router.post("/", response_model=POOut, status_code=201)
async def create_purchase_order(
    payload: POCreate,
    current_user: User = Depends(require_roles("admin", "purchasing", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    po = PurchaseOrder(
        company_id=current_user.company_id,
        supplier_id=payload.supplier_id,
        po_number=payload.po_number,
        notes=payload.notes,
        created_by_id=current_user.id,
        status=POStatus.draft,
    )
    db.add(po)
    await db.flush()

    for item_data in payload.items:
        item = POItem(
            purchase_order_id=po.id,
            spare_part_id=item_data.spare_part_id,
            description=item_data.description,
            quantity=item_data.quantity,
            unit_price=item_data.unit_price,
            quantity_received=0,
        )
        db.add(item)

    await db.commit()
    result = await db.execute(
        _load_po_query(current_user.company_id).where(PurchaseOrder.id == po.id)
    )
    return _po_to_out(result.scalars().first())


@po_router.get("/{po_id}", response_model=POOut)
async def get_purchase_order(
    po_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        _load_po_query(current_user.company_id).where(PurchaseOrder.id == po_id)
    )
    po = result.scalars().first()
    if not po:
        raise HTTPException(status_code=404, detail="Orden de compra no encontrada")
    return _po_to_out(po)


@po_router.put("/{po_id}", response_model=POOut)
async def update_purchase_order(
    po_id: int,
    payload: POUpdate,
    current_user: User = Depends(require_roles("admin", "purchasing", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        _load_po_query(current_user.company_id).where(PurchaseOrder.id == po_id)
    )
    po = result.scalars().first()
    if not po:
        raise HTTPException(status_code=404, detail="Orden de compra no encontrada")
    if po.status not in (POStatus.draft, "draft"):
        raise HTTPException(status_code=400, detail="Solo se puede editar OC en borrador")
    for k, v in payload.model_dump(exclude_none=True).items():
        setattr(po, k, v)
    await db.commit()
    result = await db.execute(
        _load_po_query(current_user.company_id).where(PurchaseOrder.id == po_id)
    )
    return _po_to_out(result.scalars().first())


@po_router.put("/{po_id}/status", response_model=POOut)
async def update_po_status(
    po_id: int,
    payload: POStatusUpdate,
    current_user: User = Depends(require_roles("admin", "purchasing")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        _load_po_query(current_user.company_id).where(PurchaseOrder.id == po_id)
    )
    po = result.scalars().first()
    if not po:
        raise HTTPException(status_code=404, detail="Orden de compra no encontrada")
    try:
        new_status = POStatus(payload.status)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Estado inválido: {payload.status}")

    # Validar transiciones de estado
    current = po.status.value if hasattr(po.status, 'value') else str(po.status)
    valid_transitions = {
        "draft": ["sent", "cancelled"],
        "sent": ["partially_received", "received", "cancelled"],
        "partially_received": ["received", "cancelled"],
        "received": [],  # No se puede cambiar una OC recibida
        "cancelled": [],  # No se puede reactivar una OC cancelada
    }
    allowed = valid_transitions.get(current, [])
    if new_status.value not in allowed:
        raise HTTPException(
            status_code=400,
            detail=f"No se puede cambiar de '{current}' a '{new_status.value}'. Transiciones válidas: {allowed}"
        )

    po.status = new_status

    # Notificar al depósito cuando se envía una OC (draft → sent)
    if current == "draft" and new_status.value == "sent":
        users_result = await db.execute(
            select(User).options(selectinload(User.user_roles)).join(User.user_roles).where(
                User.company_id == current_user.company_id,
                User.is_active == True,
            )
        )
        for u in users_result.scalars().all():
            roles = [ur.role.value if hasattr(ur.role, 'value') else str(ur.role) for ur in u.user_roles]
            if any(r in ('admin', 'warehouse') for r in roles):
                n = Notification(
                    user_id=u.id,
                    title="📦 Nueva Orden de Compra",
                    message=f"OC #{po.po_number or po.id} enviada. Próximamente para recibir en depósito.",
                    link="/purchase-orders",
                )
                db.add(n)

    await db.commit()
    result = await db.execute(
        _load_po_query(current_user.company_id).where(PurchaseOrder.id == po_id)
    )
    return _po_to_out(result.scalars().first())


@po_router.post("/{po_id}/receive", response_model=POOut)
async def receive_purchase_order(
    po_id: int,
    payload: POReceive,
    current_user: User = Depends(require_roles("admin", "warehouse", "purchasing")),
    db: AsyncSession = Depends(get_db),
):
    """Registra recepción de mercadería. Actualiza stock de repuestos automáticamente."""
    result = await db.execute(
        _load_po_query(current_user.company_id).where(PurchaseOrder.id == po_id)
    )
    po = result.scalars().first()
    if not po:
        raise HTTPException(status_code=404, detail="Orden de compra no encontrada")
    if po.status == POStatus.cancelled or po.status == "cancelled":
        raise HTTPException(status_code=400, detail="No se puede recibir una OC cancelada")

    items_by_id = {i.id: i for i in po.items}

    for receive in payload.items:
        item = items_by_id.get(receive.po_item_id)
        if not item:
            raise HTTPException(status_code=404, detail=f"Ítem {receive.po_item_id} no encontrado en esta OC")

        pending = item.quantity - (item.quantity_received or 0)
        if receive.quantity_received > pending:
            raise HTTPException(
                status_code=400,
                detail=f"Cantidad recibida ({receive.quantity_received}) supera lo pendiente ({pending}) en ítem '{item.description}'"
            )

        item.quantity_received = (item.quantity_received or 0) + receive.quantity_received

        # Ingresar al stock si tiene repuesto asignado
        if item.spare_part_id:
            sp_result = await db.execute(
                select(SparePart).where(
                    SparePart.id == item.spare_part_id,
                    SparePart.company_id == current_user.company_id,
                )
            )
            sp = sp_result.scalars().first()
            if sp:
                sp.stock += receive.quantity_received
                mov = StockMovement(
                    spare_part_id=sp.id,
                    user_id=current_user.id,
                    movement_type=MovementType.entry,
                    quantity=receive.quantity_received,
                    notes=receive.notes or f"Recepción OC #{po.po_number or po.id}",
                )
                db.add(mov)

    # Actualizar estado de la OC automáticamente
    all_received = all(
        (i.quantity_received or 0) >= i.quantity for i in po.items
    )
    any_received = any((i.quantity_received or 0) > 0 for i in po.items)

    if all_received:
        po.status = POStatus.received
    elif any_received:
        po.status = POStatus.partially_received

    await db.commit()
    result = await db.execute(
        _load_po_query(current_user.company_id).where(PurchaseOrder.id == po_id)
    )
    return _po_to_out(result.scalars().first())


# ═══════════════════════════════════════════════════════════════════════════════
# FACTURAS
# ═══════════════════════════════════════════════════════════════════════════════

@invoices_router.get("/", response_model=List[InvoiceOut])
async def list_invoices(
    skip: int = 0,
    limit: int = 100,
    current_user: User = Depends(require_roles("admin", "purchasing")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Invoice)
        .where(Invoice.company_id == current_user.company_id)
        .options(selectinload(Invoice.purchase_order))
        .order_by(Invoice.created_at.desc())
        .offset(skip).limit(limit)
    )
    invoices = result.scalars().all()
    return [
        InvoiceOut(
            id=inv.id,
            purchase_order_id=inv.purchase_order_id,
            po_number=inv.purchase_order.po_number if inv.purchase_order else None,
            invoice_number=inv.invoice_number,
            amount=inv.amount,
            status=inv.status if isinstance(inv.status, str) else inv.status.value,
            due_date=inv.due_date,
            paid_at=inv.paid_at,
            notes=inv.notes,
            created_at=inv.created_at,
        )
        for inv in invoices
    ]


@invoices_router.post("/", response_model=InvoiceOut, status_code=201)
async def create_invoice(
    payload: InvoiceCreate,
    current_user: User = Depends(require_roles("admin", "purchasing")),
    db: AsyncSession = Depends(get_db),
):
    # Validar que la OC (si se especifica) pertenece a la empresa del usuario
    if payload.purchase_order_id:
        po_result = await db.execute(
            select(PurchaseOrder).where(
                PurchaseOrder.id == payload.purchase_order_id,
                PurchaseOrder.company_id == current_user.company_id,
            )
        )
        if not po_result.scalars().first():
            raise HTTPException(
                status_code=400,
                detail="La orden de compra especificada no existe o no pertenece a tu empresa"
            )

    inv = Invoice(
        company_id=current_user.company_id,
        purchase_order_id=payload.purchase_order_id,
        invoice_number=payload.invoice_number,
        amount=payload.amount,
        due_date=payload.due_date,
        notes=payload.notes,
        status=InvoiceStatus.pending,
    )
    db.add(inv)
    await db.commit()
    await db.refresh(inv)
    return InvoiceOut(
        id=inv.id,
        purchase_order_id=inv.purchase_order_id,
        po_number=None,
        invoice_number=inv.invoice_number,
        amount=inv.amount,
        status=inv.status if isinstance(inv.status, str) else inv.status.value,
        due_date=inv.due_date,
        paid_at=inv.paid_at,
        notes=inv.notes,
        created_at=inv.created_at,
    )


@invoices_router.put("/{inv_id}/pay", response_model=InvoiceOut)
async def pay_invoice(
    inv_id: int,
    current_user: User = Depends(require_roles("admin", "purchasing")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Invoice)
        .options(selectinload(Invoice.purchase_order))
        .where(Invoice.id == inv_id, Invoice.company_id == current_user.company_id)
    )
    inv = result.scalars().first()
    if not inv:
        raise HTTPException(status_code=404, detail="Factura no encontrada")
    inv.status = InvoiceStatus.paid
    inv.paid_at = datetime.utcnow()
    await db.commit()
    await db.refresh(inv)
    return InvoiceOut(
        id=inv.id,
        purchase_order_id=inv.purchase_order_id,
        po_number=inv.purchase_order.po_number if inv.purchase_order else None,
        invoice_number=inv.invoice_number,
        amount=inv.amount,
        status=inv.status if isinstance(inv.status, str) else inv.status.value,
        due_date=inv.due_date,
        paid_at=inv.paid_at,
        notes=inv.notes,
        created_at=inv.created_at,
    )
