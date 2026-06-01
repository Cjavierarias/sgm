"""
Router para endpoints de `Equipment`.

Incluye:
- CRUD básico de equipos (`POST`, `GET`, `PUT`, `DELETE`)
- Subida de foto para un equipo en Google Drive

El router filtra por `company_id` del usuario autenticado para garantizar
que cada usuario solo accede a los equipos de su propia empresa.
"""
from __future__ import annotations

import io
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.base import Equipment, EquipmentPhoto, User
from app.routers.auth import get_current_user
from app.services.google_drive import upload_to_drive


router = APIRouter(prefix="/equipments", tags=["equipments"])

# Limites y tipos
MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024  # 5 MB
ALLOWED_MIME_PREFIX = "image/"


class EquipmentCreate(BaseModel):
    """Payload para crear un equipo.

    `company_id` no se envía en la petición, se toma del usuario autenticado.
    """

    code: str = Field(..., example="EQ-001")
    name: str = Field(..., example="Compresor principal")
    location: Optional[str] = Field(None, example="Planta Baja")
    brand: Optional[str] = Field(None, example="Atlas Copco")
    model: Optional[str] = Field(None, example="X123")


class EquipmentOut(BaseModel):
    """Respuesta para endpoints de equipo.

    Incluye `company_id` para que el cliente sepa a qué empresa pertenece.
    """

    id: int
    company_id: int
    code: str
    name: str
    location: Optional[str]
    brand: Optional[str]
    model: Optional[str]

    class Config:
        orm_mode = True


async def _get_equipment_for_user(
    equipment_id: int,
    current_user: User,
    db: AsyncSession,
) -> Equipment:
    """Helper que busca un equipo que pertenezca a la misma compañía que el usuario."""
    result = await db.execute(
        select(Equipment).where(Equipment.id == equipment_id, Equipment.company_id == int(current_user.company_id))
    )
    equipment = result.scalars().first()
    if not equipment:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Equipo no encontrado en la compañía del usuario")
    return equipment


@router.post("/", response_model=EquipmentOut, status_code=status.HTTP_201_CREATED)
async def create_equipment(
    payload: EquipmentCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Equipment:
    """Crear un equipo nuevo dentro de la compañía del usuario autenticado."""
    company_id = int(current_user.company_id)

    # Verificar unicidad del código dentro de la misma compañía.
    existing = await db.execute(
        select(Equipment).where(Equipment.code == payload.code, Equipment.company_id == company_id)
    )
    if existing.scalars().first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="El código del equipo ya existe para esta compañía")

    new_equipment = Equipment(
        company_id=company_id,
        code=payload.code,
        name=payload.name,
        location=payload.location,
        brand=payload.brand,
        model=payload.model,
    )
    db.add(new_equipment)
    await db.commit()
    await db.refresh(new_equipment)
    return new_equipment


@router.get("/", response_model=list[EquipmentOut])
async def list_equipments(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[Equipment]:
    """Listar todos los equipos que pertenecen a la misma compañía del usuario."""
    company_id = int(current_user.company_id)
    result = await db.execute(select(Equipment).where(Equipment.company_id == company_id).order_by(Equipment.id))
    return result.scalars().all()


@router.get("/{equipment_id}", response_model=EquipmentOut)
async def get_equipment(
    equipment_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Equipment:
    """Obtener detalle de un equipo por su ID si pertenece a la compañía del usuario."""
    return await _get_equipment_for_user(equipment_id, current_user, db)


@router.put("/{equipment_id}", response_model=EquipmentOut)
async def update_equipment(
    equipment_id: int,
    payload: EquipmentCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Equipment:
    """Actualizar campos de un equipo existente."""
    company_id = int(current_user.company_id)
    equipment = await _get_equipment_for_user(equipment_id, current_user, db)

    if equipment.code != payload.code:
        existing = await db.execute(
            select(Equipment).where(Equipment.code == payload.code, Equipment.company_id == company_id)
        )
        existing_equipment = existing.scalars().first()
        if existing_equipment and existing_equipment.id != equipment.id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="El código del equipo ya existe para esta compañía")

    equipment.code = payload.code
    equipment.name = payload.name
    equipment.location = payload.location
    equipment.brand = payload.brand
    equipment.model = payload.model

    db.add(equipment)
    await db.commit()
    await db.refresh(equipment)
    return equipment


@router.delete("/{equipment_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_equipment(
    equipment_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """Eliminar un equipo que pertenece a la compañía del usuario."""
    equipment = await _get_equipment_for_user(equipment_id, current_user, db)
    await db.delete(equipment)
    await db.commit()


@router.post("/{equipment_id}/photo")
async def upload_equipment_photo(
    equipment_id: int,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Sube una foto para un equipo específico.

    - Valida que el equipo pertenezca a la misma `company_id` que `current_user`.
    - Acepta solo MIME types que comiencen con `image/`.
    - Límite de tamaño definido en `MAX_FILE_SIZE_BYTES`.
    - Usa `upload_to_drive` para subir y guarda `EquipmentPhoto`.
    """
    equipment = await _get_equipment_for_user(equipment_id, current_user, db)

    # Validar tipo MIME
    content_type = file.content_type or ""
    if not content_type.startswith(ALLOWED_MIME_PREFIX):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Tipo de archivo no permitido. Solo imágenes.")

    # Leer contenido y validar tamaño
    contents = await file.read()
    if len(contents) == 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Archivo vacío")
    if len(contents) > MAX_FILE_SIZE_BYTES:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail=f"Archivo demasiado grande. Máx {MAX_FILE_SIZE_BYTES} bytes")

    # Subir a Google Drive
    file_obj = io.BytesIO(contents)
    try:
        web_view = upload_to_drive(file_obj, file.filename, int(current_user.company_id))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Error subiendo archivo a Google Drive") from e

    # Guardar registro en la base de datos
    photo = EquipmentPhoto(equipment_id=equipment.id, drive_url=web_view, uploaded_by_id=int(current_user.id))
    db.add(photo)
    await db.commit()
    await db.refresh(photo)

    return {"photo_id": photo.id, "url": photo.drive_url, "uploaded_at": photo.created_at.isoformat()}
