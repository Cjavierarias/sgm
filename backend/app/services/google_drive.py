"""
Integración con Google Drive — versión con fallback local.

Si las credenciales de Google no están configuradas, guarda los archivos
localmente en /tmp/sgm_uploads y devuelve una URL relativa.
Esto permite correr el sistema sin Google Drive en desarrollo.
"""
from __future__ import annotations

import io
import os
import logging
import uuid
from typing import BinaryIO

logger = logging.getLogger(__name__)

UPLOAD_DIR = "/tmp/sgm_uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

SCOPES = ["https://www.googleapis.com/auth/drive"]


def _is_drive_configured() -> bool:
    key_file = os.getenv("GOOGLE_SERVICE_ACCOUNT_FILE", "")
    return bool(key_file) and os.path.exists(key_file)


def upload_to_drive(file_obj: BinaryIO, filename: str, company_id: int) -> str:
    """
    Sube archivo a Google Drive si está configurado, o guarda localmente.
    Devuelve la URL de acceso al archivo.
    """
    if _is_drive_configured():
        return _upload_to_drive_real(file_obj, filename, company_id)
    else:
        return _save_locally(file_obj, filename)


def _save_locally(file_obj: BinaryIO, filename: str) -> str:
    """Fallback: guarda en /tmp/sgm_uploads y devuelve URL relativa."""
    try:
        file_obj.seek(0)
    except Exception:
        pass

    ext = os.path.splitext(filename)[1] or ".bin"
    unique_name = f"{uuid.uuid4().hex}{ext}"
    path = os.path.join(UPLOAD_DIR, unique_name)

    with open(path, "wb") as f:
        f.write(file_obj.read())

    logger.info("Archivo guardado localmente: %s", path)
    return f"/uploads/{unique_name}"


def _upload_to_drive_real(file_obj: BinaryIO, filename: str, company_id: int) -> str:
    """Upload real a Google Drive (solo si las credenciales están configuradas)."""
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaIoBaseUpload
    from googleapiclient.errors import HttpError

    key_file = os.getenv("GOOGLE_SERVICE_ACCOUNT_FILE")
    creds = service_account.Credentials.from_service_account_file(key_file, scopes=SCOPES)
    service = build("drive", "v3", credentials=creds)

    folder_name = f"company_{company_id}"
    q = f"name = '{folder_name}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
    resp = service.files().list(q=q, spaces="drive", fields="files(id)", pageSize=1).execute()
    files = resp.get("files", [])
    if files:
        folder_id = files[0]["id"]
    else:
        meta = {"name": folder_name, "mimeType": "application/vnd.google-apps.folder"}
        folder_id = service.files().create(body=meta, fields="id").execute()["id"]

    try:
        file_obj.seek(0)
    except Exception:
        pass

    media = MediaIoBaseUpload(file_obj, mimetype="application/octet-stream", resumable=True)
    created = service.files().create(
        body={"name": filename, "parents": [folder_id]},
        media_body=media,
        fields="id, webViewLink",
    ).execute()

    file_id = created.get("id")
    web_view = created.get("webViewLink") or f"https://drive.google.com/file/d/{file_id}/view"

    domain = os.getenv("GOOGLE_DRIVE_DOMAIN")
    perm = {"type": "domain", "role": "reader", "domain": domain} if domain else {"type": "anyone", "role": "reader"}
    try:
        service.permissions().create(fileId=file_id, body=perm, fields="id").execute()
    except Exception:
        pass

    return web_view
