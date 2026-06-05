"""
Punto de entrada de la API FastAPI.

Este archivo configura la aplicación, registra routers y define un healthcheck.
"""
from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.database import engine
from app.models.base import Base
from app.routers.auth import router as auth_router
from app.routers.equipments import router as equipments_router


app = FastAPI(title="SGM API", version="0.1.0")

# CORS para permitir que el frontend Flutter consuma la API desde otros orígenes.
# En producción deberías restringir `allow_origins` a los dominios de tu app.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup_event() -> None:
    """Evento de arranque que verifica que la base de datos responde correctamente y crea tablas en desarrollo."""
    async with engine.begin() as connection:
        # Verificar conexión
        await connection.execute(text("SELECT 1"))
        # Crear tablas si no existen (útil en desarrollo/local)
        await connection.run_sync(Base.metadata.create_all)


# Registrar routers existentes.
app.include_router(auth_router)
app.include_router(equipments_router)


@app.get("/health")
async def health_check() -> dict[str, str]:
    """Healthcheck usado por Docker y Nginx para validar que la API está viva."""
    return {"status": "ok"}
