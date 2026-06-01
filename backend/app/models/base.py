"""
Modelos SQLAlchemy (ORM) para la aplicación.

Incluye: Company, User, Equipment, WorkOrder, EquipmentPhoto.

Características implementadas:
- `company_id` en las tablas para multi-tenancy.
- Timestamps (`created_at`, `updated_at`) donde aplica.
- Relaciones bidireccionales con `back_populates`.
- `WorkOrderStatus` como `enum` de SQLAlchemy.

Comentarios para principiantes embebidos.
"""
from __future__ import annotations

from datetime import datetime
from enum import Enum as PyEnum
from typing import List, Optional

from sqlalchemy import (
    Column,
    DateTime,
    Enum as SQLEnum,
    ForeignKey,
    Integer,
    String,
    Text,
)
from sqlalchemy.orm import declarative_base, relationship


# Definimos la base de SQLAlchemy una sola vez aquí.
# Otros módulos deben importar `Base` desde este archivo.
Base = declarative_base()
Base.__allow_unmapped__ = True
Base.__allow_unmapped__ = True


class WorkOrderStatus(PyEnum):
    open = "open"
    assigned = "assigned"
    in_progress = "in_progress"
    closed = "closed"


class Company(Base):
    """Empresa / tenant principal.

    - `id`: PK
    - `name`: nombre de la empresa
    - `google_workspace_id`: id si se integra con Google Workspace
    - `status`: estado (opcional: active/inactive)
    """

    __tablename__ = "companies"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    google_workspace_id = Column(String(255), nullable=True)
    status = Column(String(50), default="active")

    # Relaciones: una company tiene muchos usuarios, equipos y órdenes
    users: List["User"] = relationship(
        "User",
        back_populates="company",
        cascade="all, delete-orphan",
    )
    equipments: List["Equipment"] = relationship(
        "Equipment",
        back_populates="company",
        cascade="all, delete-orphan",
    )
    work_orders: List["WorkOrder"] = relationship(
        "WorkOrder",
        back_populates="company",
        cascade="all, delete-orphan",
    )


class User(Base):
    """Usuario dentro de una empresa.

    Campos clave:
    - `company_id`: FK a `companies.id` (multi-tenant)
    - `email`, `hashed_password`
    - `role`: ejemplo `admin`, `technician`, `viewer`
    """

    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    company_id = Column(
        Integer,
        ForeignKey("companies.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    email = Column(String(255), nullable=False, unique=True, index=True)
    hashed_password = Column(String(255), nullable=False)
    role = Column(String(50), default="technician")
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)

    # Relaciones
    company: Company = relationship("Company", back_populates="users")
    assigned_work_orders: List["WorkOrder"] = relationship(
        "WorkOrder",
        back_populates="assigned_to",
    )
    uploaded_photos: List["EquipmentPhoto"] = relationship(
        "EquipmentPhoto",
        back_populates="uploaded_by",
    )


class Equipment(Base):
    """Equipo/activo de la compañía.

    - `manual_drive_url`: enlace en Google Drive (o donde se guarde manuales)
    """

    __tablename__ = "equipments"

    id = Column(Integer, primary_key=True, index=True)
    company_id = Column(
        Integer,
        ForeignKey("companies.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    code = Column(String(100), nullable=False, index=True)
    name = Column(String(255), nullable=False)
    location = Column(String(255), nullable=True)
    brand = Column(String(100), nullable=True)
    model = Column(String(100), nullable=True)
    manual_drive_url = Column(String(1000), nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at = Column(
        DateTime(timezone=True),
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )

    # Relaciones
    company: Company = relationship("Company", back_populates="equipments")
    photos: List["EquipmentPhoto"] = relationship(
        "EquipmentPhoto",
        back_populates="equipment",
        cascade="all, delete-orphan",
    )
    work_orders: List["WorkOrder"] = relationship(
        "WorkOrder",
        back_populates="equipment",
    )


class WorkOrder(Base):
    """Orden de trabajo asociada a un equipo.

    - `status` usa `WorkOrderStatus` enum.
    - `assigned_to` referencia a `User`.
    """

    __tablename__ = "work_orders"

    id = Column(Integer, primary_key=True, index=True)
    company_id = Column(
        Integer,
        ForeignKey("companies.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    equipment_id = Column(
        Integer,
        ForeignKey("equipments.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    assigned_to_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    status = Column(
        SQLEnum(WorkOrderStatus, name="workorderstatus", native_enum=False),
        nullable=False,
        default=WorkOrderStatus.open,
    )
    description = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at = Column(
        DateTime(timezone=True),
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )

    # Relaciones
    company: Company = relationship("Company", back_populates="work_orders")
    equipment: Optional[Equipment] = relationship("Equipment", back_populates="work_orders")
    assigned_to: Optional[User] = relationship("User", back_populates="assigned_work_orders")


class EquipmentPhoto(Base):
    """Foto de un equipo almacenada en Google Drive (u otro provider).

    - `drive_url`: enlace compartido al archivo.
    - `uploaded_by`: FK a `users.id`.
    """

    __tablename__ = "equipment_photos"

    id = Column(Integer, primary_key=True, index=True)
    equipment_id = Column(
        Integer,
        ForeignKey("equipments.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    drive_url = Column(String(1000), nullable=False)
    uploaded_by_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)

    # Relaciones
    equipment: Equipment = relationship("Equipment", back_populates="photos")
    uploaded_by: Optional[User] = relationship("User", back_populates="uploaded_photos")
