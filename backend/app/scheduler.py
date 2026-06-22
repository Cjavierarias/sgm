"""
Scheduler de tareas periódicas SGM.

Usa APScheduler para ejecutar tareas en segundo plano.
La tarea principal es la verificación diaria de suscripciones.

Configuración:
  SCHEDULER_ENABLED=true|false   → Activar/desactivar (default: true)
  SUBSCRIPTION_CHECK_HOUR=8      → Hora UTC en la que ejecutar (default: 8)
"""
from __future__ import annotations

import logging
import os

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

logger = logging.getLogger(__name__)

_scheduler: AsyncIOScheduler | None = None

SCHEDULER_ENABLED = os.getenv("SCHEDULER_ENABLED", "true").lower() == "true"
CHECK_HOUR        = int(os.getenv("SUBSCRIPTION_CHECK_HOUR", "8"))


async def _daily_subscription_job() -> None:
    """Tarea diaria: verifica suscripciones vencidas."""
    from app.database import AsyncSessionLocal
    from app.services.billing import run_daily_subscription_check

    logger.info("[Scheduler] Iniciando verificación diaria de suscripciones...")
    async with AsyncSessionLocal() as db:
        try:
            summary = await run_daily_subscription_check(db)
            logger.info("[Scheduler] Verificación completada: %s", summary)
        except Exception as exc:
            logger.error("[Scheduler] Error en verificación diaria: %s", exc, exc_info=True)


def start_scheduler() -> None:
    """Inicia el scheduler. Llamar en el evento startup de FastAPI."""
    global _scheduler
    if not SCHEDULER_ENABLED:
        logger.info("[Scheduler] Desactivado (SCHEDULER_ENABLED=false)")
        return

    _scheduler = AsyncIOScheduler()
    _scheduler.add_job(
        _daily_subscription_job,
        trigger=CronTrigger(hour=CHECK_HOUR, minute=0, timezone="UTC"),
        id="daily_subscription_check",
        replace_existing=True,
    )
    _scheduler.start()
    logger.info("[Scheduler] Iniciado — verificación diaria a las %s:00 UTC", CHECK_HOUR)


def stop_scheduler() -> None:
    """Detiene el scheduler. Llamar en el evento shutdown de FastAPI."""
    global _scheduler
    if _scheduler and _scheduler.running:
        _scheduler.shutdown(wait=False)
        logger.info("[Scheduler] Detenido")
