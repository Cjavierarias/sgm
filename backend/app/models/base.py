"""
Modelos SQLAlchemy completos para SGM.

Tablas:
- Company, User, UserRole (multi-rol por usuario)
- Equipment, EquipmentPhoto, MaintenancePlan
- WorkOrder, WorkOrderComment, WorkOrderPhoto
- SparePart, StockMovement, SparePartRequest
- Supplier, PurchaseOrder, POItem, Invoice
- Notification
"""
from __future__ import annotations

from datetime import datetime
from enum import Enum as PyEnum
from typing import List, Optional

from sqlalchemy import (
    Boolean, Column, DateTime, Enum as SQLEnum,
    Float, ForeignKey, Integer, String, Text,
)
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()
Base.__allow_unmapped__ = True


# ─────────────────────────────────────────────
# ENUMS
# ─────────────────────────────────────────────

class RoleName(PyEnum):
    admin          = "admin"           # Admin Empresa
    maintenance_manager = "maintenance_manager"  # Jefe Mantenimiento
    technician     = "technician"      # Mecánico / Técnico
    warehouse      = "warehouse"       # Depósito / Almacén
    purchasing     = "purchasing"      # Compras
    hr             = "hr"              # RRHH
    viewer         = "viewer"          # Solo lectura


class EquipmentStatus(PyEnum):
    operational    = "operational"
    maintenance    = "maintenance"
    out_of_service = "out_of_service"


class WOStatus(PyEnum):
    open           = "open"
    assigned       = "assigned"
    in_progress    = "in_progress"
    waiting_parts  = "waiting_parts"
    closed         = "closed"
    cancelled      = "cancelled"


class WOPriority(PyEnum):
    low            = "low"
    medium         = "medium"
    high           = "high"
    critical       = "critical"


class WOType(PyEnum):
    corrective     = "corrective"
    preventive     = "preventive"
    predictive     = "predictive"


class MovementType(PyEnum):
    entry          = "entry"
    exit           = "exit"
    adjustment     = "adjustment"


class RequestStatus(PyEnum):
    pending        = "pending"
    approved       = "approved"
    delivered      = "delivered"
    rejected       = "rejected"


class POStatus(PyEnum):
    draft          = "draft"
    sent           = "sent"
    partially_received = "partially_received"
    received       = "received"
    cancelled      = "cancelled"


class InvoiceStatus(PyEnum):
    pending        = "pending"
    paid           = "paid"
    overdue        = "overdue"


class QuoteRequestStatus(PyEnum):
    pending        = "pending"       # Esperando cotización del proveedor
    quoted         = "quoted"        # Proveedor envió cotización
    approved       = "approved"      # Jefe/Admin aprobó la cotización
    rejected       = "rejected"      # Cotización rechazada
    converted      = "converted"     # Convertida a Orden de Compra


class MaintenanceFrequency(PyEnum):
    daily          = "daily"
    weekly         = "weekly"
    monthly        = "monthly"
    quarterly      = "quarterly"
    yearly         = "yearly"
    by_hours       = "by_hours"


# ─────────────────────────────────────────────
# COMPANY
# ─────────────────────────────────────────────

class Company(Base):
    __tablename__ = "companies"

    id                   = Column(Integer, primary_key=True, index=True)
    name                 = Column(String(255), nullable=False)
    google_workspace_id  = Column(String(255), nullable=True)
    status               = Column(String(50), default="active")
    created_at           = Column(DateTime(timezone=True), default=datetime.utcnow)

    users:       List["User"]       = relationship("User",       back_populates="company", cascade="all, delete-orphan")
    equipments:  List["Equipment"]  = relationship("Equipment",  back_populates="company", cascade="all, delete-orphan")
    work_orders: List["WorkOrder"]  = relationship("WorkOrder",  back_populates="company", cascade="all, delete-orphan")
    spare_parts: List["SparePart"]  = relationship("SparePart",  back_populates="company", cascade="all, delete-orphan")
    suppliers:   List["Supplier"]   = relationship("Supplier",   back_populates="company", cascade="all, delete-orphan")


# ─────────────────────────────────────────────
# USER + ROLES
# ─────────────────────────────────────────────

class User(Base):
    __tablename__ = "users"

    id               = Column(Integer, primary_key=True, index=True)
    company_id       = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    email            = Column(String(255), nullable=False, unique=True, index=True)
    full_name        = Column(String(255), nullable=True)
    phone            = Column(String(50), nullable=True)
    position         = Column(String(100), nullable=True)   # Cargo en la empresa
    hashed_password  = Column(String(255), nullable=False)
    is_active        = Column(Boolean, default=True)
    created_at       = Column(DateTime(timezone=True), default=datetime.utcnow)

    company:               "Company"           = relationship("Company", back_populates="users")
    user_roles:            List["UserRole"]    = relationship("UserRole", back_populates="user", cascade="all, delete-orphan")
    assigned_work_orders:  List["WorkOrder"]   = relationship("WorkOrder", back_populates="assigned_to", foreign_keys="WorkOrder.assigned_to_id")
    created_work_orders:   List["WorkOrder"]   = relationship("WorkOrder", back_populates="created_by", foreign_keys="WorkOrder.created_by_id")
    wo_comments:           List["WorkOrderComment"] = relationship("WorkOrderComment", back_populates="user")
    notifications:         List["Notification"]     = relationship("Notification", back_populates="user", cascade="all, delete-orphan")

    @property
    def roles(self) -> List[str]:
        return [ur.role for ur in self.user_roles]


class UserRole(Base):
    """Tabla intermedia: un usuario puede tener múltiples roles."""
    __tablename__ = "user_roles"

    id         = Column(Integer, primary_key=True, index=True)
    user_id    = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    role       = Column(SQLEnum(RoleName, name="rolename", native_enum=False), nullable=False)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)

    user: "User" = relationship("User", back_populates="user_roles")


# ─────────────────────────────────────────────
# EQUIPMENT
# ─────────────────────────────────────────────

class Equipment(Base):
    __tablename__ = "equipments"

    id               = Column(Integer, primary_key=True, index=True)
    company_id       = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    code             = Column(String(100), nullable=False, index=True)
    name             = Column(String(255), nullable=False)
    location         = Column(String(255), nullable=True)
    brand            = Column(String(100), nullable=True)
    model            = Column(String(100), nullable=True)
    serial_number    = Column(String(100), nullable=True)
    purchase_date    = Column(DateTime(timezone=True), nullable=True)
    status           = Column(SQLEnum(EquipmentStatus, name="equipmentstatus", native_enum=False), default=EquipmentStatus.operational)
    manual_drive_url = Column(String(1000), nullable=True)
    notes            = Column(Text, nullable=True)
    created_at       = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at       = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    company:           "Company"                = relationship("Company", back_populates="equipments")
    photos:            List["EquipmentPhoto"]   = relationship("EquipmentPhoto", back_populates="equipment", cascade="all, delete-orphan")
    work_orders:       List["WorkOrder"]        = relationship("WorkOrder", back_populates="equipment")
    maintenance_plans: List["MaintenancePlan"]  = relationship("MaintenancePlan", back_populates="equipment", cascade="all, delete-orphan")


class EquipmentPhoto(Base):
    __tablename__ = "equipment_photos"

    id            = Column(Integer, primary_key=True, index=True)
    equipment_id  = Column(Integer, ForeignKey("equipments.id", ondelete="CASCADE"), nullable=False, index=True)
    url           = Column(String(1000), nullable=False)
    filename      = Column(String(255), nullable=True)
    uploaded_by_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at    = Column(DateTime(timezone=True), default=datetime.utcnow)

    equipment:   "Equipment" = relationship("Equipment", back_populates="photos")
    uploaded_by: Optional["User"] = relationship("User")


class MaintenancePlan(Base):
    """Plan de mantenimiento preventivo para un equipo."""
    __tablename__ = "maintenance_plans"

    id             = Column(Integer, primary_key=True, index=True)
    equipment_id   = Column(Integer, ForeignKey("equipments.id", ondelete="CASCADE"), nullable=False, index=True)
    title          = Column(String(255), nullable=False)
    description    = Column(Text, nullable=True)
    frequency      = Column(SQLEnum(MaintenanceFrequency, name="maintenancefrequency", native_enum=False), nullable=False)
    frequency_value = Column(Integer, default=1)   # cada X días/horas/etc
    next_due       = Column(DateTime(timezone=True), nullable=True)
    last_done      = Column(DateTime(timezone=True), nullable=True)
    is_active      = Column(Boolean, default=True)
    created_at     = Column(DateTime(timezone=True), default=datetime.utcnow)

    equipment: "Equipment" = relationship("Equipment", back_populates="maintenance_plans")


# ─────────────────────────────────────────────
# WORK ORDERS
# ─────────────────────────────────────────────

class WorkOrder(Base):
    __tablename__ = "work_orders"

    id              = Column(Integer, primary_key=True, index=True)
    company_id      = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    equipment_id    = Column(Integer, ForeignKey("equipments.id", ondelete="SET NULL"), nullable=True, index=True)
    created_by_id   = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    assigned_to_id  = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    title           = Column(String(255), nullable=False)
    description     = Column(Text, nullable=True)
    status          = Column(SQLEnum(WOStatus, name="wostatus", native_enum=False), nullable=False, default=WOStatus.open)
    priority        = Column(SQLEnum(WOPriority, name="wopriority", native_enum=False), default=WOPriority.medium)
    wo_type         = Column(SQLEnum(WOType, name="wotype", native_enum=False), default=WOType.corrective)
    estimated_hours = Column(Float, nullable=True)
    actual_hours    = Column(Float, nullable=True)
    due_date        = Column(DateTime(timezone=True), nullable=True)
    closed_at       = Column(DateTime(timezone=True), nullable=True)
    created_at      = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at      = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    company:     "Company"              = relationship("Company", back_populates="work_orders")
    equipment:   Optional["Equipment"]  = relationship("Equipment", back_populates="work_orders")
    created_by:  Optional["User"]       = relationship("User", foreign_keys=[created_by_id], back_populates="created_work_orders")
    assigned_to: Optional["User"]       = relationship("User", foreign_keys=[assigned_to_id], back_populates="assigned_work_orders")
    comments:    List["WorkOrderComment"]  = relationship("WorkOrderComment", back_populates="work_order", cascade="all, delete-orphan")
    photos:      List["WorkOrderPhoto"]    = relationship("WorkOrderPhoto", back_populates="work_order", cascade="all, delete-orphan")
    part_requests: List["SparePartRequest"] = relationship("SparePartRequest", back_populates="work_order")


class WorkOrderComment(Base):
    __tablename__ = "work_order_comments"

    id            = Column(Integer, primary_key=True, index=True)
    work_order_id = Column(Integer, ForeignKey("work_orders.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id       = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    content       = Column(Text, nullable=False)
    created_at    = Column(DateTime(timezone=True), default=datetime.utcnow)

    work_order: "WorkOrder" = relationship("WorkOrder", back_populates="comments")
    user:       Optional["User"] = relationship("User", back_populates="wo_comments")


class WorkOrderPhoto(Base):
    __tablename__ = "work_order_photos"

    id            = Column(Integer, primary_key=True, index=True)
    work_order_id = Column(Integer, ForeignKey("work_orders.id", ondelete="CASCADE"), nullable=False, index=True)
    url           = Column(String(1000), nullable=False)
    filename      = Column(String(255), nullable=True)
    uploaded_by_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at    = Column(DateTime(timezone=True), default=datetime.utcnow)

    work_order:  "WorkOrder"     = relationship("WorkOrder", back_populates="photos")
    uploaded_by: Optional["User"] = relationship("User")


# ─────────────────────────────────────────────
# SPARE PARTS / DEPÓSITO
# ─────────────────────────────────────────────

class SparePart(Base):
    __tablename__ = "spare_parts"

    id            = Column(Integer, primary_key=True, index=True)
    company_id    = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    code          = Column(String(100), nullable=False, index=True)
    name          = Column(String(255), nullable=False)
    description   = Column(Text, nullable=True)
    unit          = Column(String(50), default="unidad")
    stock         = Column(Float, default=0)
    min_stock     = Column(Float, default=0)
    location      = Column(String(100), nullable=True)  # Ubicación en depósito
    unit_cost     = Column(Float, nullable=True)
    # Nuevos campos: asociación a equipo o sector
    equipment_id  = Column(Integer, ForeignKey("equipments.id", ondelete="SET NULL"), nullable=True, index=True)
    sector        = Column(String(100), nullable=True)  # "mecanica", "electricidad", "insumos", etc.
    created_at    = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at    = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    company:    "Company"               = relationship("Company", back_populates="spare_parts")
    equipment:  Optional["Equipment"]   = relationship("Equipment", foreign_keys=[equipment_id])
    movements:  List["StockMovement"]   = relationship("StockMovement", back_populates="spare_part", cascade="all, delete-orphan")
    requests:   List["SparePartRequest"] = relationship("SparePartRequest", back_populates="spare_part")

    @property
    def is_low_stock(self) -> bool:
        return self.stock <= self.min_stock


class StockMovement(Base):
    __tablename__ = "stock_movements"

    id             = Column(Integer, primary_key=True, index=True)
    spare_part_id  = Column(Integer, ForeignKey("spare_parts.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id        = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    movement_type  = Column(SQLEnum(MovementType, name="movementtype", native_enum=False), nullable=False)
    quantity       = Column(Float, nullable=False)
    notes          = Column(String(500), nullable=True)
    created_at     = Column(DateTime(timezone=True), default=datetime.utcnow)

    spare_part: "SparePart"   = relationship("SparePart", back_populates="movements")
    user:       Optional["User"] = relationship("User")


class SparePartRequest(Base):
    """Pedido de repuesto desde el taller al depósito."""
    __tablename__ = "spare_part_requests"

    id             = Column(Integer, primary_key=True, index=True)
    work_order_id  = Column(Integer, ForeignKey("work_orders.id", ondelete="SET NULL"), nullable=True, index=True)
    spare_part_id  = Column(Integer, ForeignKey("spare_parts.id", ondelete="CASCADE"), nullable=False, index=True)
    requested_by_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    quantity       = Column(Float, nullable=False)
    status         = Column(SQLEnum(RequestStatus, name="requeststatus", native_enum=False), default=RequestStatus.pending)
    notes          = Column(String(500), nullable=True)
    created_at     = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at     = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    work_order:    Optional["WorkOrder"] = relationship("WorkOrder", back_populates="part_requests")
    spare_part:    "SparePart"           = relationship("SparePart", back_populates="requests")
    requested_by:  Optional["User"]      = relationship("User")


# ─────────────────────────────────────────────
# COMPRAS
# ─────────────────────────────────────────────

class Supplier(Base):
    __tablename__ = "suppliers"

    id         = Column(Integer, primary_key=True, index=True)
    company_id = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    name       = Column(String(255), nullable=False)
    contact    = Column(String(255), nullable=True)
    email      = Column(String(255), nullable=True)
    phone      = Column(String(50), nullable=True)
    address    = Column(String(500), nullable=True)
    notes      = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)

    company:        "Company"             = relationship("Company", back_populates="suppliers")
    purchase_orders: List["PurchaseOrder"] = relationship("PurchaseOrder", back_populates="supplier")


class PurchaseOrder(Base):
    __tablename__ = "purchase_orders"

    id           = Column(Integer, primary_key=True, index=True)
    company_id   = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    supplier_id  = Column(Integer, ForeignKey("suppliers.id", ondelete="SET NULL"), nullable=True, index=True)
    created_by_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    po_number    = Column(String(100), nullable=True, index=True)
    status       = Column(SQLEnum(POStatus, name="postatus", native_enum=False), default=POStatus.draft)
    notes        = Column(Text, nullable=True)
    total_amount = Column(Float, nullable=True)
    created_at   = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at   = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    supplier:    Optional["Supplier"]  = relationship("Supplier", back_populates="purchase_orders")
    created_by:  Optional["User"]      = relationship("User")
    items:       List["POItem"]        = relationship("POItem", back_populates="purchase_order", cascade="all, delete-orphan")
    invoices:    List["Invoice"]       = relationship("Invoice", back_populates="purchase_order")


class POItem(Base):
    __tablename__ = "po_items"

    id                  = Column(Integer, primary_key=True, index=True)
    purchase_order_id   = Column(Integer, ForeignKey("purchase_orders.id", ondelete="CASCADE"), nullable=False, index=True)
    spare_part_id       = Column(Integer, ForeignKey("spare_parts.id", ondelete="SET NULL"), nullable=True)
    description         = Column(String(500), nullable=False)
    quantity            = Column(Float, nullable=False)
    quantity_received   = Column(Float, default=0)
    unit_price          = Column(Float, nullable=True)

    purchase_order: "PurchaseOrder"  = relationship("PurchaseOrder", back_populates="items")
    spare_part:     Optional["SparePart"] = relationship("SparePart")


class Invoice(Base):
    __tablename__ = "invoices"

    id                  = Column(Integer, primary_key=True, index=True)
    company_id          = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    purchase_order_id   = Column(Integer, ForeignKey("purchase_orders.id", ondelete="SET NULL"), nullable=True, index=True)
    invoice_number      = Column(String(100), nullable=False)
    amount              = Column(Float, nullable=False)
    status              = Column(SQLEnum(InvoiceStatus, name="invoicestatus", native_enum=False), default=InvoiceStatus.pending)
    due_date            = Column(DateTime(timezone=True), nullable=True)
    paid_at             = Column(DateTime(timezone=True), nullable=True)
    notes               = Column(Text, nullable=True)
    created_at          = Column(DateTime(timezone=True), default=datetime.utcnow)

    purchase_order: Optional["PurchaseOrder"] = relationship("PurchaseOrder", back_populates="invoices")


class QuoteRequest(Base):
    """Solicitud de cotización a proveedores (desde depósito/compras)."""
    __tablename__ = "quote_requests"

    id              = Column(Integer, primary_key=True, index=True)
    company_id      = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    spare_part_id   = Column(Integer, ForeignKey("spare_parts.id", ondelete="SET NULL"), nullable=True, index=True)
    supplier_id     = Column(Integer, ForeignKey("suppliers.id", ondelete="SET NULL"), nullable=True, index=True)
    requested_by_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    description     = Column(String(500), nullable=False)  # Descripción del repuesto/insumo
    quantity        = Column(Float, nullable=False)
    unit            = Column(String(50), default="unidad")
    status          = Column(SQLEnum(QuoteRequestStatus, name="quoterequeststatus", native_enum=False), default=QuoteRequestStatus.pending)
    quoted_price    = Column(Float, nullable=True)         # Precio cotizado por el proveedor
    notes           = Column(Text, nullable=True)
    created_at      = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at      = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    spare_part:   Optional["SparePart"]  = relationship("SparePart")
    supplier:     Optional["Supplier"]   = relationship("Supplier")
    requested_by: Optional["User"]       = relationship("User")


# ─────────────────────────────────────────────
# NOTIFICACIONES
# ─────────────────────────────────────────────

class Notification(Base):
    __tablename__ = "notifications"

    id          = Column(Integer, primary_key=True, index=True)
    user_id     = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    title       = Column(String(255), nullable=False)
    message     = Column(Text, nullable=False)
    is_read     = Column(Boolean, default=False)
    link        = Column(String(500), nullable=True)   # ej: /work-orders/42
    created_at  = Column(DateTime(timezone=True), default=datetime.utcnow)

    user: "User" = relationship("User", back_populates="notifications")
