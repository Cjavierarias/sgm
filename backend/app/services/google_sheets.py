"""
Servicio de exportación a Google Sheets para SGM.

Exporta datos tabulares (órdenes de trabajo, repuestos, planes, etc.)
a una hoja de cálculo de Google Sheets en el Drive del admin.

Variables de entorno:
  GOOGLE_SERVICE_ACCOUNT_FILE → ruta al JSON de la cuenta de servicio
  GOOGLE_DRIVE_DOMAIN         → dominio para compartir el sheet automáticamente

Requiere habilitar Google Sheets API en Google Cloud Console.
"""
from __future__ import annotations

import logging
import os
from datetime import datetime
from typing import Optional

logger = logging.getLogger(__name__)

GOOGLE_SERVICE_ACCOUNT_FILE = os.getenv("GOOGLE_SERVICE_ACCOUNT_FILE", "")
GOOGLE_DRIVE_DOMAIN         = os.getenv("GOOGLE_DRIVE_DOMAIN", "")

_sheets_service = None
_drive_service  = None


def _get_sheets_service():
    global _sheets_service
    if _sheets_service is not None:
        return _sheets_service

    if not GOOGLE_SERVICE_ACCOUNT_FILE or not os.path.exists(GOOGLE_SERVICE_ACCOUNT_FILE):
        logger.warning("GOOGLE_SERVICE_ACCOUNT_FILE no configurado — Google Sheets deshabilitado")
        return None

    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build

        credentials = service_account.Credentials.from_service_account_file(
            GOOGLE_SERVICE_ACCOUNT_FILE,
            scopes=[
                "https://www.googleapis.com/auth/spreadsheets",
                "https://www.googleapis.com/auth/drive",
            ],
        )
        _sheets_service = build("sheets", "v4", credentials=credentials, cache_discovery=False)
        logger.info("Servicio Google Sheets inicializado")
        return _sheets_service
    except Exception as exc:
        logger.error("Error inicializando Google Sheets: %s", exc)
        return None


def _get_drive_service():
    global _drive_service
    if _drive_service is not None:
        return _drive_service

    if not GOOGLE_SERVICE_ACCOUNT_FILE or not os.path.exists(GOOGLE_SERVICE_ACCOUNT_FILE):
        return None

    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build

        credentials = service_account.Credentials.from_service_account_file(
            GOOGLE_SERVICE_ACCOUNT_FILE,
            scopes=["https://www.googleapis.com/auth/drive"],
        )
        _drive_service = build("drive", "v3", credentials=credentials, cache_discovery=False)
        return _drive_service
    except Exception as exc:
        logger.error("Error inicializando Google Drive: %s", exc)
        return None


def export_to_sheets(
    title: str,
    headers: list[str],
    rows: list[list],
    share_with_email: Optional[str] = None,
) -> Optional[dict]:
    """
    Crea una hoja de cálculo en Google Sheets con los datos proporcionados.

    Args:
        title:           Título de la hoja
        headers:         Lista de nombres de columna
        rows:            Lista de filas (cada fila es una lista de valores)
        share_with_email: Email del admin para compartir el sheet

    Returns:
        {"sheet_id": "...", "sheet_url": "...", "rows_exported": N}
        o None si falla.
    """
    service = _get_sheets_service()
    if not service:
        return None

    try:
        # 1. Crear la hoja
        spreadsheet_body = {
            "properties": {"title": title},
            "sheets": [{
                "properties": {
                    "title": "Datos",
                    "gridProperties": {"frozenRowCount": 1},
                }
            }],
        }
        spreadsheet = service.spreadsheets().create(body=spreadsheet_body).execute()
        sheet_id   = spreadsheet.get("spreadsheetId")
        sheet_url  = spreadsheet.get("spreadsheetUrl")

        if not sheet_id:
            logger.error("No se pudo crear la hoja")
            return None

        # 2. Escribir encabezados + datos
        values = [headers] + rows
        range_name = "Datos!A1"
        body = {"values": values}
        result = service.spreadsheets().values().update(
            spreadsheetId=sheet_id,
            range=range_name,
            valueInputOption="RAW",
            body=body,
        ).execute()
        updated_cells = result.get("updatedCells", 0)
        logger.info("Sheet creado: %s — %d celdas actualizadas", sheet_id, updated_cells)

        # 3. Formatear encabezados (negrita + color de fondo)
        requests = [{
            "repeatCell": {
                "range": {"sheetId": 0, "startRowIndex": 0, "endRowIndex": 1},
                "cell": {
                    "userEnteredFormat": {
                        "textFormat": {"bold": True},
                        "backgroundColor": {"red": 0.0, "green": 0.47, "blue": 0.71},
                    }
                },
                "fields": "userEnteredFormat(textFormat,backgroundColor)",
            }
        }]
        service.spreadsheets().batchUpdate(
            spreadsheetId=sheet_id, body={"requests": requests}
        ).execute()

        # 4. Compartir con el admin si se especifica
        if share_with_email:
            drive = _get_drive_service()
            if drive:
                try:
                    permission = {
                        "type": "user",
                        "role": "writer",
                        "emailAddress": share_with_email,
                    }
                    drive.permissions().create(
                        fileId=sheet_id, body=permission, sendNotificationEmail=False
                    ).execute()
                    logger.info("Sheet compartido con %s", share_with_email)
                except Exception as exc:
                    logger.warning("No se pudo compartir sheet con %s: %s", share_with_email, exc)

        return {
            "sheet_id":      sheet_id,
            "sheet_url":     sheet_url,
            "rows_exported": len(rows),
        }
    except Exception as exc:
        logger.error("Error exportando a Sheets: %s", exc)
        return None


# ─── Helpers por módulo ───────────────────────────────────────────────────────

def export_work_orders(work_orders: list[dict], company_name: str, admin_email: str) -> Optional[dict]:
    """Exporta órdenes de trabajo a Google Sheets."""
    headers = ["ID", "Código", "Título", "Tipo", "Estado", "Prioridad", "Equipo",
               "Asignado a", "Creado por", "Fecha creación", "Fecha vencimiento",
               "Horas estimadas", "Horas reales", "Descripción"]
    rows = []
    for wo in work_orders:
        rows.append([
            wo.get("id", ""),
            wo.get("code", ""),
            wo.get("title", ""),
            wo.get("wo_type", ""),
            wo.get("status", ""),
            wo.get("priority", ""),
            wo.get("equipment_name", ""),
            wo.get("assigned_to_name", ""),
            wo.get("created_by_name", ""),
            wo.get("created_at", ""),
            wo.get("due_date", ""),
            wo.get("estimated_hours", ""),
            wo.get("actual_hours", ""),
            wo.get("description", ""),
        ])
    title = f"SGM — OT — {company_name} — {datetime.now().strftime('%Y-%m-%d')}"
    return export_to_sheets(title, headers, rows, share_with_email=admin_email)


def export_spare_parts(spare_parts: list[dict], company_name: str, admin_email: str) -> Optional[dict]:
    """Exporta repuestos a Google Sheets."""
    headers = ["ID", "Código", "Nombre", "Marca", "Modelo", "Stock actual",
               "Stock mínimo", "Ubicación", "Costo unitario", "¿Stock bajo?"]
    rows = []
    for sp in spare_parts:
        rows.append([
            sp.get("id", ""),
            sp.get("code", ""),
            sp.get("name", ""),
            sp.get("brand", ""),
            sp.get("model", ""),
            sp.get("current_stock", ""),
            sp.get("min_stock", ""),
            sp.get("location", ""),
            sp.get("unit_cost", ""),
            "SÍ" if sp.get("is_low_stock") else "NO",
        ])
    title = f"SGM — Repuestos — {company_name} — {datetime.now().strftime('%Y-%m-%d')}"
    return export_to_sheets(title, headers, rows, share_with_email=admin_email)


def export_equipments(equipments: list[dict], company_name: str, admin_email: str) -> Optional[dict]:
    """Exporta equipos a Google Sheets."""
    headers = ["ID", "Código", "Nombre", "Ubicación", "Marca", "Modelo",
               "Número de serie", "Estado", "Fecha compra", "Notas"]
    rows = []
    for eq in equipments:
        rows.append([
            eq.get("id", ""),
            eq.get("code", ""),
            eq.get("name", ""),
            eq.get("location", ""),
            eq.get("brand", ""),
            eq.get("model", ""),
            eq.get("serial_number", ""),
            eq.get("status", ""),
            eq.get("purchase_date", ""),
            eq.get("notes", ""),
        ])
    title = f"SGM — Equipos — {company_name} — {datetime.now().strftime('%Y-%m-%d')}"
    return export_to_sheets(title, headers, rows, share_with_email=admin_email)


def export_maintenance_plans(plans: list[dict], company_name: str, admin_email: str) -> Optional[dict]:
    """Exporta planes de mantenimiento a Google Sheets."""
    headers = ["ID", "Equipo", "Título", "Frecuencia", "Intervalo",
               "Próxima fecha", "Activo", "Descripción"]
    rows = []
    for p in plans:
        rows.append([
            p.get("id", ""),
            p.get("equipment_name", ""),
            p.get("title", ""),
            p.get("frequency", ""),
            p.get("interval_value", ""),
            p.get("next_date", ""),
            "SÍ" if p.get("is_active") else "NO",
            p.get("description", ""),
        ])
    title = f"SGM — Planes — {company_name} — {datetime.now().strftime('%Y-%m-%d')}"
    return export_to_sheets(title, headers, rows, share_with_email=admin_email)
