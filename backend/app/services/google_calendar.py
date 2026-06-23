"""
Servicio de integración con Google Calendar para SGM.

Sincroniza planes de mantenimiento y órdenes de trabajo con Google Calendar
del admin de la empresa. Permite compartir el calendario con colaboradores.

Variables de entorno:
  GOOGLE_SERVICE_ACCOUNT_FILE → ruta al JSON de la cuenta de servicio
  GOOGLE_CALENDAR_ID         → ID del calendario compartido (opcional, se crea uno por empresa)
  APP_BASE_URL               → URL del backend (para links en eventos)

Requiere habilitar Google Calendar API en Google Cloud Console y
compartir el calendario con la cuenta de servicio.
"""
from __future__ import annotations

import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Optional

logger = logging.getLogger(__name__)

GOOGLE_SERVICE_ACCOUNT_FILE = os.getenv("GOOGLE_SERVICE_ACCOUNT_FILE", "")
APP_BASE_URL                = os.getenv("APP_BASE_URL", "http://localhost:8000")

_calendar_service = None


def _get_calendar_service():
    """Obtiene el servicio de Google Calendar (singleton)."""
    global _calendar_service
    if _calendar_service is not None:
        return _calendar_service

    if not GOOGLE_SERVICE_ACCOUNT_FILE or not os.path.exists(GOOGLE_SERVICE_ACCOUNT_FILE):
        logger.warning("GOOGLE_SERVICE_ACCOUNT_FILE no configurado — Google Calendar deshabilitado")
        return None

    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build

        credentials = service_account.Credentials.from_service_account_file(
            GOOGLE_SERVICE_ACCOUNT_FILE,
            scopes=["https://www.googleapis.com/auth/calendar"],
        )
        _calendar_service = build("calendar", "v3", credentials=credentials, cache_discovery=False)
        logger.info("Servicio Google Calendar inicializado")
        return _calendar_service
    except Exception as exc:
        logger.error("Error inicializando Google Calendar: %s", exc)
        return None


def create_company_calendar(company_name: str, admin_email: str) -> Optional[str]:
    """
    Crea un calendario compartido para la empresa.
    Retorna el calendar_id o None si falla.
    """
    service = _get_calendar_service()
    if not service:
        return None

    try:
        calendar_body = {
            "summary":     f"SGM — {company_name}",
            "description": f"Calendario de mantenimiento — {company_name}. Sincronizado con SGM BSA Consultora.",
            "timeZone":    "America/Argentina/Buenos_Aires",
        }
        created = service.calendars().insert(body=calendar_body).execute()
        calendar_id = created.get("id")

        # Compartir con el admin (permiso de escritor)
        if calendar_id and admin_email:
            rule_body = {
                "scope": {
                    "type":  "user",
                    "value": admin_email,
                },
                "role": "writer",
            }
            try:
                service.acl().insert(calendarId=calendar_id, body=rule_body).execute()
                logger.info("Calendario %s compartido con %s", calendar_id, admin_email)
            except Exception as exc:
                logger.warning("No se pudo compartir calendario con %s: %s", admin_email, exc)

        logger.info("Calendario creado: %s", calendar_id)
        return calendar_id
    except Exception as exc:
        logger.error("Error creando calendario: %s", exc)
        return None


def share_calendar_with_user(calendar_id: str, user_email: str, role: str = "reader") -> bool:
    """
    Comparte un calendario con un usuario.
    role: "reader" (ver) | "writer" (editar) | "owner"
    """
    service = _get_calendar_service()
    if not service or not calendar_id:
        return False

    try:
        rule_body = {
            "scope": {"type": "user", "value": user_email},
            "role":  role,
        }
        service.acl().insert(calendarId=calendar_id, body=rule_body).execute()
        logger.info("Calendario %s compartido con %s (%s)", calendar_id, user_email, role)
        return True
    except Exception as exc:
        logger.error("Error compartiendo calendario: %s", exc)
        return False


def create_or_update_event(
    calendar_id: str,
    title: str,
    description: str,
    start_at: datetime,
    end_at: Optional[datetime] = None,
    location: Optional[str] = None,
    google_event_id: Optional[str] = None,
    color_id: Optional[str] = None,
) -> Optional[str]:
    """
    Crea o actualiza un evento en Google Calendar.
    Si google_event_id se pasa, actualiza; si no, crea.
    Retorna el google_event_id o None si falla.
    """
    service = _get_calendar_service()
    if not service or not calendar_id:
        return None

    if end_at is None:
        end_at = start_at + timedelta(hours=1)

    event_body = {
        "summary":     title,
        "description": description,
        "start": {
            "dateTime": start_at.astimezone(timezone.utc).isoformat(),
            "timeZone": "America/Argentina/Buenos_Aires",
        },
        "end": {
            "dateTime": end_at.astimezone(timezone.utc).isoformat(),
            "timeZone": "America/Argentina/Buenos_Aires",
        },
    }
    if location:
        event_body["location"] = location
    if color_id:
        event_body["colorId"] = color_id

    try:
        if google_event_id:
            updated = service.events().update(
                calendarId=calendar_id, eventId=google_event_id, body=event_body
            ).execute()
            logger.info("Evento actualizado: %s", updated.get("id"))
            return updated.get("id")
        else:
            created = service.events().insert(calendarId=calendar_id, body=event_body).execute()
            logger.info("Evento creado: %s", created.get("id"))
            return created.get("id")
    except Exception as exc:
        logger.error("Error creando/actualizando evento: %s", exc)
        return None


def delete_event(calendar_id: str, google_event_id: str) -> bool:
    """Elimina un evento de Google Calendar."""
    service = _get_calendar_service()
    if not service or not calendar_id:
        return False

    try:
        service.events().delete(calendarId=calendar_id, eventId=google_event_id).execute()
        logger.info("Evento eliminado: %s", google_event_id)
        return True
    except Exception as exc:
        logger.error("Error eliminando evento: %s", exc)
        return False


def list_events(
    calendar_id: str,
    time_min: Optional[datetime] = None,
    time_max: Optional[datetime] = None,
    max_results: int = 250,
) -> list[dict]:
    """Lista eventos de un calendario en un rango de fechas."""
    service = _get_calendar_service()
    if not service or not calendar_id:
        return []

    if time_min is None:
        time_min = datetime.now(timezone.utc)
    if time_max is None:
        time_max = time_min + timedelta(days=30)

    try:
        events_result = service.events().list(
            calendarId=calendar_id,
            timeMin=time_min.astimezone(timezone.utc).isoformat(),
            timeMax=time_max.astimezone(timezone.utc).isoformat(),
            maxResults=max_results,
            singleEvents=True,
            orderBy="startTime",
        ).execute()
        return events_result.get("items", [])
    except Exception as exc:
        logger.error("Error listando eventos: %s", exc)
        return []
