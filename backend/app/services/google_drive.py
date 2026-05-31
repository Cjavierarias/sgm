"""
Integración con Google Drive para almacenamiento multi-tenant.

Funcionalidad:
- `get_drive_service(company_id)`: carga credenciales desde
  `GOOGLE_SERVICE_ACCOUNT_FILE` y devuelve un cliente Drive.
- `upload_to_drive(file_obj, filename, company_id)`: sube `file_obj` a una
  carpeta dedicada al `company_id`, crea la carpeta si no existe, aplica
  permisos (dominio o público) y retorna `webViewLink`.

Seguridad multi-tenant:
- Cada tenant tiene su propia carpeta (nombre: `company_{id}`).
- Evitar permisos `anyone` en producción; preferir permisos por dominio
  configurando `GOOGLE_DRIVE_DOMAIN` en el entorno.
"""
from __future__ import annotations

import io
import os
import logging
from typing import BinaryIO

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseUpload
from googleapiclient.errors import HttpError


logger = logging.getLogger(__name__)

# Scopes necesarias para subir archivos y gestionar permisos
SCOPES = ["https://www.googleapis.com/auth/drive"]


def get_drive_service(company_id: int):
    """
    Crea y retorna un cliente de Google Drive.

    Por simplicidad usamos un único Service Account (ruta en
    `GOOGLE_SERVICE_ACCOUNT_FILE`). Si necesitás credenciales por tenant,
    adaptar esta función para cargar credenciales específicas.
    """
    key_file = os.getenv("GOOGLE_SERVICE_ACCOUNT_FILE")
    if not key_file or not os.path.exists(key_file):
        logger.error("GOOGLE_SERVICE_ACCOUNT_FILE no encontrado: %s", key_file)
        raise RuntimeError("Credenciales de Google Drive no configuradas en el servidor")

    try:
        creds = service_account.Credentials.from_service_account_file(key_file, scopes=SCOPES)
        service = build("drive", "v3", credentials=creds)
        return service
    except Exception as e:
        logger.exception("Error creando cliente de Google Drive")
        raise


def _get_or_create_company_folder(service, company_id: int) -> str:
    """Busca una carpeta con nombre `company_{id}` o la crea y retorna su id."""
    folder_name = f"company_{company_id}"
    try:
        # Buscar carpeta existente
        q = (
            f"name = '{folder_name}' and mimeType = 'application/vnd.google-apps.folder'"
            " and trashed = false"
        )
        resp = service.files().list(q=q, spaces="drive", fields="files(id, name)", pageSize=1).execute()
        files = resp.get("files", [])
        if files:
            return files[0]["id"]

        # Crear carpeta si no existe
        file_metadata = {"name": folder_name, "mimeType": "application/vnd.google-apps.folder"}
        created = service.files().create(body=file_metadata, fields="id").execute()
        return created["id"]
    except HttpError as e:
        logger.exception("Error accediendo/creando carpeta para company %s: %s", company_id, e)
        raise


def upload_to_drive(file_obj: BinaryIO, filename: str, company_id: int) -> str:
    """
    Sube `file_obj` (file-like) a la carpeta del tenant y retorna `webViewLink`.

    - `file_obj` debe ser un objeto en modo binario (ej. BytesIO o open(...,'rb')).
    - Se aplica permiso de lectura según `GOOGLE_DRIVE_DOMAIN` o público por link.
    """
    if not hasattr(file_obj, "read"):
        raise ValueError("file_obj debe ser un objeto file-like con método read()")

    service = get_drive_service(company_id)

    try:
        folder_id = _get_or_create_company_folder(service, company_id)

        # Asegurar que el puntero esté al principio
        try:
            file_obj.seek(0)
        except Exception:
            pass

        media = MediaIoBaseUpload(file_obj, mimetype="application/octet-stream", resumable=True)

        file_metadata = {"name": filename, "parents": [folder_id]}
        created = service.files().create(body=file_metadata, media_body=media, fields="id, webViewLink").execute()
        file_id = created.get("id")
        web_view = created.get("webViewLink")

        # Aplicar permisos: preferir dominio si está configurado
        domain = os.getenv("GOOGLE_DRIVE_DOMAIN")
        try:
            if domain:
                perm = {"type": "domain", "role": "reader", "domain": domain}
            else:
                # WARNING: `anyone` hace el archivo accesible a cualquiera con el link.
                perm = {"type": "anyone", "role": "reader"}

            service.permissions().create(fileId=file_id, body=perm, fields="id").execute()
        except HttpError:
            # No fatal: si no se pueden aplicar permisos dejamos el archivo creado
            logger.exception("No se pudieron aplicar permisos al archivo %s", file_id)

        # Si no viene webViewLink, construir un link alternativo
        if not web_view and file_id:
            web_view = f"https://drive.google.com/file/d/{file_id}/view"

        return web_view

    except HttpError as e:
        logger.exception("Error en Google Drive API durante upload: %s", e)
        raise RuntimeError("Error subiendo archivo a Google Drive") from e
    except Exception:
        logger.exception("Error inesperado subiendo a Google Drive")
        raise
