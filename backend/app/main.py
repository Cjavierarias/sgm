"""
Punto de entrada de la API FastAPI.

Este archivo configura la aplicación, registra routers y define un healthcheck.
"""
from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.app.database import engine
from backend.app.models.base import Base
from backend.app.routers.auth import router as auth_router
from backend.app.routers.equipments import router as equipments_router


app = FastAPI(title="SGM API", version="0.1.0")

# CORS para permitir que el frontend Flutter consuma la API desde otros orígenes.
# En producción deberías restringir `allow_origins` a los dominios de tu app.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup_event() -> None:
    """Evento de arranque que crea las tablas en la base de datos si no existen.

    Esto es útil para desarrollo rápido. En producción es mejor usar Alembic para
    manejar migraciones de manera controlada.
    """
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


# Registrar routers existentes.
app.include_router(auth_router)
app.include_router(equipments_router)

# Espacio reservado para routers adicionales.
# from backend.app.routers.work_orders import router as work_orders_router
# from backend.app.routers.calendar import router as calendar_router
# app.include_router(work_orders_router)
# app.include_router(calendar_router)


@app.get("/health")
async def health_check() -> dict[str, str]:
    """Healthcheck usado por Docker y Nginx para validar que la API está viva."""
    return {"status": "ok"}
