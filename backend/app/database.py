"""
Configuración de la base de datos (async) para FastAPI + SQLAlchemy.

Este archivo crea el engine asíncrono, la fábrica de sesiones y una
dependency `get_db()` que puedes usar en tus routers de FastAPI.

Importa `Base` desde app.models.base para mantener una única definición.
"""
from __future__ import annotations

import os
from typing import AsyncGenerator

from dotenv import load_dotenv
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.models.base import Base


# Cargar variables de entorno desde .env en la raíz del backend.
load_dotenv()


DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError(
        "La variable de entorno DATABASE_URL no está definida. "
        "Define DATABASE_URL en tu .env o en el entorno de ejecución."
    )


# Crear engine asíncrono de SQLAlchemy.
engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    future=True,
    pool_pre_ping=True,
)


# Fábrica de sesiones asíncronas.
SessionLocal: async_sessionmaker[AsyncSession] = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependency de FastAPI que provee una sesión asíncrona de SQLAlchemy."""
    async with SessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()


async def shutdown_engine() -> None:
    """Cerrar el engine cuando la aplicación se apaga."""
    await engine.dispose()
