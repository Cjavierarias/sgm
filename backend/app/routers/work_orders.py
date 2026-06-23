"""
Router de Órdenes de Trabajo (Work Orders).

Endpoints:
- GET    /work-orders          Lista OT (filtradas por rol)
- POST   /work-orders          Crear OT
- GET    /work-orders/{id}     Detalle
- PUT    /work-orders/{id}     Editar
- DELETE /work-orders/{id}     Eliminar (solo admin)
- POST   /work-orders/{id}/comments   Agregar comentario
- POST   /work-orders/{id}/photos     Subir foto (base64)
- PUT    /work-orders/{id}/status     Cambiar estado
"""
from __future__ import annotations

import base64
import os
import uuid
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models.base import (
    Notification, User, WorkOrder, WorkOrderComment,
    WorkOrderPhoto, WOPriority, WOStatus, WOType,
)
from app.routers.auth import get_current_user, require_roles

router = APIRouter(prefix="/work-orders", tags=["work-orders"])

UPLOAD_DIR = "/tmp/sgm_uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)


# ─── Schemas ──────────────────────────────────────────────────────────────────

class WOCreate(BaseModel):
    title: str
    description: Optional[str] = None
    equipment_id: Optional[int] = None
    assigned_to_id: Optional[int] = None
    priority: Optional[str] = "medium"
    wo_type: Optional[str] = "corrective"
    estimated_hours: Optional[float] = None
    due_date: Optional[datetime] = None


class WOUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    equipment_id: Optional[int] = None
    assigned_to_id: Optional[int] = None
    priority: Optional[str] = None
    wo_type: Optional[str] = None
    estimated_hours: Optional[float] = None
    actual_hours: Optional[float] = None
    due_date: Optional[datetime] = None


class WOStatusUpdate(BaseModel):
    status: str
    comment: Optional[str] = None  # Comentario automático al cambiar estado


class CommentCreate(BaseModel):
    content: str


class PhotoUpload(BaseModel):
    filename: str
    data_base64: str   # imagen en base64


class CommentOut(BaseModel):
    id: int
    content: str
    created_at: datetime
    user_name: Optional[str] = None

    class Config:
        from_attributes = True


class PhotoOut(BaseModel):
    id: int
    url: str
    filename: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


class WOOut(BaseModel):
    id: int
    company_id: int
    title: str
    description: Optional[str]
    status: str
    priority: str
    wo_type: str
    equipment_id: Optional[int]
    equipment_name: Optional[str] = None
    assigned_to_id: Optional[int]
    assigned_to_name: Optional[str] = None
    created_by_id: Optional[int]
    estimated_hours: Optional[float]
    actual_hours: Optional[float]
    due_date: Optional[datetime]
    closed_at: Optional[datetime]
    created_at: datetime
    updated_at: datetime
    comments: List[CommentOut] = []
    photos: List[PhotoOut] = []

    class Config:
        from_attributes = True


def _wo_to_out(wo: WorkOrder) -> WOOut:
    comments = [
        CommentOut(
            id=c.id,
            content=c.content,
            created_at=c.created_at,
            user_name=c.user.full_name or c.user.email if c.user else None,
        )
        for c in (wo.comments or [])
    ]
    photos = [
        PhotoOut(id=p.id, url=p.url, filename=p.filename, created_at=p.created_at)
        for p in (wo.photos or [])
    ]
    return WOOut(
        id=wo.id,
        company_id=wo.company_id,
        title=wo.title,
        description=wo.description,
        status=wo.status if isinstance(wo.status, str) else wo.status.value,
        priority=wo.priority if isinstance(wo.priority, str) else wo.priority.value,
        wo_type=wo.wo_type if isinstance(wo.wo_type, str) else wo.wo_type.value,
        equipment_id=wo.equipment_id,
        equipment_name=wo.equipment.name if wo.equipment else None,
        assigned_to_id=wo.assigned_to_id,
        assigned_to_name=(wo.assigned_to.full_name or wo.assigned_to.email) if wo.assigned_to else None,
        created_by_id=wo.created_by_id,
        estimated_hours=wo.estimated_hours,
        actual_hours=wo.actual_hours,
        due_date=wo.due_date,
        closed_at=wo.closed_at,
        created_at=wo.created_at,
        updated_at=wo.updated_at,
        comments=comments,
        photos=photos,
    )


def _load_wo_query(company_id: int):
    return (
        select(WorkOrder)
        .options(
            selectinload(WorkOrder.comments).selectinload(WorkOrderComment.user),
            selectinload(WorkOrder.photos),
            selectinload(WorkOrder.equipment),
            selectinload(WorkOrder.assigned_to),
            selectinload(WorkOrder.created_by),
        )
        .where(WorkOrder.company_id == company_id)
    )


async def _notify(db: AsyncSession, user_id: int, title: str, message: str, link: str = None):
    n = Notification(user_id=user_id, title=title, message=message, link=link)
    db.add(n)


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/", response_model=List[WOOut])
async def list_work_orders(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_roles = [ur.role.value if hasattr(ur.role, 'value') else str(ur.role) for ur in current_user.user_roles]
    query = _load_wo_query(current_user.company_id).order_by(WorkOrder.created_at.desc())

    # Si el usuario solo tiene roles de solo-lectura (technician, viewer, hr) sin roles de gestión,
    # solo ve sus propias OT (o todas si es viewer)
    management_roles = {"admin", "maintenance_manager", "warehouse", "purchasing"}
    has_management = any(r in management_roles for r in user_roles)
    if not has_management and "technician" in user_roles:
        query = query.where(WorkOrder.assigned_to_id == current_user.id)

    result = await db.execute(query)
    return [_wo_to_out(wo) for wo in result.scalars().all()]


@router.post("/", response_model=WOOut, status_code=201)
async def create_work_order(
    payload: WOCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        priority = WOPriority(payload.priority or "medium")
        wo_type = WOType(payload.wo_type or "corrective")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    wo = WorkOrder(
        company_id=current_user.company_id,
        created_by_id=current_user.id,
        title=payload.title,
        description=payload.description,
        equipment_id=payload.equipment_id,
        assigned_to_id=payload.assigned_to_id,
        priority=priority,
        wo_type=wo_type,
        estimated_hours=payload.estimated_hours,
        due_date=payload.due_date,
        status=WOStatus.open if not payload.assigned_to_id else WOStatus.assigned,
    )
    db.add(wo)
    await db.flush()

    # Notificar al técnico asignado
    if payload.assigned_to_id:
        await _notify(
            db, payload.assigned_to_id,
            "Nueva OT asignada",
            f"Se te asignó la OT: {payload.title}",
            f"/work-orders/{wo.id}",
        )

    await db.commit()
    result = await db.execute(_load_wo_query(current_user.company_id).where(WorkOrder.id == wo.id))
    return _wo_to_out(result.scalars().first())


@router.get("/{wo_id}", response_model=WOOut)
async def get_work_order(
    wo_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(_load_wo_query(current_user.company_id).where(WorkOrder.id == wo_id))
    wo = result.scalars().first()
    if not wo:
        raise HTTPException(status_code=404, detail="OT no encontrada")
    return _wo_to_out(wo)


@router.put("/{wo_id}", response_model=WOOut)
async def update_work_order(
    wo_id: int,
    payload: WOUpdate,
    current_user: User = Depends(require_roles("admin", "maintenance_manager", "technician")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(_load_wo_query(current_user.company_id).where(WorkOrder.id == wo_id))
    wo = result.scalars().first()
    if not wo:
        raise HTTPException(status_code=404, detail="OT no encontrada")

    old_assigned = wo.assigned_to_id

    if payload.title is not None:
        wo.title = payload.title
    if payload.description is not None:
        wo.description = payload.description
    if payload.equipment_id is not None:
        wo.equipment_id = payload.equipment_id
    if payload.assigned_to_id is not None:
        wo.assigned_to_id = payload.assigned_to_id
        if wo.status == WOStatus.open:
            wo.status = WOStatus.assigned
    if payload.priority is not None:
        wo.priority = WOPriority(payload.priority)
    if payload.wo_type is not None:
        wo.wo_type = WOType(payload.wo_type)
    if payload.estimated_hours is not None:
        wo.estimated_hours = payload.estimated_hours
    if payload.actual_hours is not None:
        wo.actual_hours = payload.actual_hours
    if payload.due_date is not None:
        wo.due_date = payload.due_date

    # Notificar si se reasignó
    if payload.assigned_to_id and payload.assigned_to_id != old_assigned:
        await _notify(
            db, payload.assigned_to_id,
            "OT asignada",
            f"Se te asignó la OT: {wo.title}",
            f"/work-orders/{wo.id}",
        )

    await db.commit()
    result = await db.execute(_load_wo_query(current_user.company_id).where(WorkOrder.id == wo_id))
    return _wo_to_out(result.scalars().first())


@router.put("/{wo_id}/status", response_model=WOOut)
async def update_status(
    wo_id: int,
    payload: WOStatusUpdate,
    current_user: User = Depends(require_roles("admin", "maintenance_manager", "technician")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(_load_wo_query(current_user.company_id).where(WorkOrder.id == wo_id))
    wo = result.scalars().first()
    if not wo:
        raise HTTPException(status_code=404, detail="OT no encontrada")

    try:
        new_status = WOStatus(payload.status)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Estado inválido: {payload.status}")

    old_status = wo.status
    wo.status = new_status
    if new_status == WOStatus.closed:
        wo.closed_at = datetime.utcnow()

    # Agregar comentario automático del cambio de estado
    comment_text = payload.comment or f"Estado cambiado a: {new_status.value}"
    comment = WorkOrderComment(
        work_order_id=wo.id,
        user_id=current_user.id,
        content=comment_text,
    )
    db.add(comment)

    # ── Notificaciones automáticas ──────────────────────────────────────
    # Si pasó a "waiting_parts" → avisar a depósito
    if new_status == WOStatus.waiting_parts and old_status != WOStatus.waiting_parts:
        warehouse_users = await db.execute(
            select(User).join(User.user_roles).where(
                User.company_id == current_user.company_id,
                User.is_active == True,
            )
        )
        for u in warehouse_users.scalars().all():
            user_roles = [ur.role.value if hasattr(ur.role, 'value') else str(ur.role) for ur in u.user_roles]
            if any(r in ('admin', 'warehouse') for r in user_roles):
                await _notify(
                    db, u.id,
                    "🔧 OT espera repuestos",
                    f"La OT '{wo.title}' ({wo.code if hasattr(wo, 'code') else f'#{wo.id}'}) está esperando repuestos. Revisá el pedido.",
                    f"/work-orders/{wo.id}",
                )

    # Notificar al jefe si el técnico cierra la OT
    if new_status == WOStatus.closed and wo.created_by_id and current_user.id != wo.created_by_id:
        await _notify(
            db, wo.created_by_id,
            "OT cerrada",
            f"La OT '{wo.title}' fue cerrada por {current_user.full_name or current_user.email}",
            f"/work-orders/{wo.id}",
        )
    # Notificar al creador si se cancela
    if new_status == WOStatus.cancelled and wo.created_by_id and current_user.id != wo.created_by_id:
        await _notify(
            db, wo.created_by_id,
            "OT cancelada",
            f"La OT '{wo.title}' fue cancelada por {current_user.full_name or current_user.email}",
            f"/work-orders/{wo.id}",
        )

    await db.commit()
    result = await db.execute(_load_wo_query(current_user.company_id).where(WorkOrder.id == wo_id))
    return _wo_to_out(result.scalars().first())


@router.post("/{wo_id}/comments", response_model=CommentOut, status_code=201)
async def add_comment(
    wo_id: int,
    payload: CommentCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(WorkOrder).where(WorkOrder.id == wo_id, WorkOrder.company_id == current_user.company_id)
    )
    if not result.scalars().first():
        raise HTTPException(status_code=404, detail="OT no encontrada")

    comment = WorkOrderComment(
        work_order_id=wo_id,
        user_id=current_user.id,
        content=payload.content,
    )
    db.add(comment)
    await db.commit()
    await db.refresh(comment)

    return CommentOut(
        id=comment.id,
        content=comment.content,
        created_at=comment.created_at,
        user_name=current_user.full_name or current_user.email,
    )


@router.post("/{wo_id}/photos", response_model=PhotoOut, status_code=201)
async def upload_photo(
    wo_id: int,
    payload: PhotoUpload,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(WorkOrder).where(WorkOrder.id == wo_id, WorkOrder.company_id == current_user.company_id)
    )
    if not result.scalars().first():
        raise HTTPException(status_code=404, detail="OT no encontrada")

    try:
        img_data = base64.b64decode(payload.data_base64)
    except Exception:
        raise HTTPException(status_code=400, detail="Imagen base64 inválida")

    ext = os.path.splitext(payload.filename)[1] or ".jpg"
    fname = f"{uuid.uuid4().hex}{ext}"
    fpath = os.path.join(UPLOAD_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(img_data)

    # URL relativa — en producción apuntaría a S3/Drive
    url = f"/uploads/{fname}"

    photo = WorkOrderPhoto(
        work_order_id=wo_id,
        url=url,
        filename=payload.filename,
        uploaded_by_id=current_user.id,
    )
    db.add(photo)
    await db.commit()
    await db.refresh(photo)

    return PhotoOut(id=photo.id, url=photo.url, filename=photo.filename, created_at=photo.created_at)


@router.delete("/{wo_id}", status_code=204)
async def delete_work_order(
    wo_id: int,
    current_user: User = Depends(require_roles("admin", "maintenance_manager")),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(WorkOrder).where(WorkOrder.id == wo_id, WorkOrder.company_id == current_user.company_id)
    )
    wo = result.scalars().first()
    if not wo:
        raise HTTPException(status_code=404, detail="OT no encontrada")
    await db.delete(wo)
    await db.commit()
