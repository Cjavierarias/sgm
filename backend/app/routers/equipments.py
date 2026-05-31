"""
Router para endpoints de `Equipment`.

Incluye:
- POST /equipments/{equipment_id}/photo

El endpoint valida pertenencia por `company_id`, acepta multipart file,
valida tipo/size, sube a Google Drive y guarda `EquipmentPhoto` en la BD.
"""
from __future__ import annotations

import io
from datetime import datetime

from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.app.database import get_db
from backend.app.models.base import Equipment, EquipmentPhoto
from backend.app.routers.auth import get_current_user
from backend.app.services.google_drive import upload_to_drive


router = APIRouter()

# Limites y tipos
MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024  # 5 MB
ALLOWED_MIME_PREFIX = "image/"


@router.post("/equipments/{equipment_id}/photo")
async def upload_equipment_photo(
    equipment_id: int,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Sube una foto para un equipo específico.

    - Valida que el equipo pertenezca a la misma `company_id` que `current_user`.
    - Acepta solo MIME types que comiencen con `image/`.
    - Límite de tamaño definido en `MAX_FILE_SIZE_BYTES`.
    - Usa `upload_to_drive` para subir y guarda `EquipmentPhoto`.
    """
    # Verificar que el equipo existe y pertenece al tenant del usuario
    result = await db.execute(
        select(Equipment).where(Equipment.id == equipment_id, Equipment.company_id == int(current_user.company_id))
    )
    equipment = result.scalars().first()
    if not equipment:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Equipo no encontrado en la compañía del usuario")

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
