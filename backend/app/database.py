"""
Configuración de la base de datos (async) para FastAPI + SQLAlchemy.

Este archivo crea el engine asíncrono, la fábrica de sesiones y una
dependency `get_db()` que puedes usar en tus routers de FastAPI.

Lectura de la variable `DATABASE_URL` desde un archivo `.env`.

Comentarios orientados a principiantes incluidos.
"""
from __future__ import annotations

import os
from typing import AsyncGenerator

from dotenv import load_dotenv
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import declarative_base


# Cargar variables de entorno desde .env (si existe) - útil en desarrollo
load_dotenv()


# Esperamos una URL como: postgresql+asyncpg://user:pass@host:port/dbname
DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError(
        "La variable de entorno DATABASE_URL no está definida. "
        "Define DATABASE_URL en tu .env o en el entorno de ejecución."
    )


# Declarative base para que los modelos la importen
Base = declarative_base()


# Crear engine asíncrono de SQLAlchemy
# - `future=True` mantiene compatibilidad con la API moderna de SQLAlchemy.
# - `pool_pre_ping=True` ayuda a recuperar conexiones muertas automáticamente.
engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    future=True,
    pool_pre_ping=True,
)


# Fábrica de sesiones asíncronas.
# - `expire_on_commit=False` evita que los objetos se marquen como expirados
#   tras el commit (comportamiento común en servicios web).
async_session: async_sessionmaker[AsyncSession] = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """
    Dependency de FastAPI que provee una sesión asíncrona de SQLAlchemy.

    Uso en un router:

        from fastapi import APIRouter, Depends
        from sqlalchemy.ext.asyncio import AsyncSession

        router = APIRouter()

        @router.get("/items")
        async def read_items(db: AsyncSession = Depends(get_db)):
            result = await db.execute(select(Item))
            return result.scalars().all()

    Notas sobre el cierre:
    - Usamos `async with async_session() as session` para asegurarnos de que
      la sesión se cierra correctamente aunque ocurra una excepción.
    - No es necesario llamar a `await session.close()` explícitamente cuando se
      usa el context manager `async with`, pero lo mostramos en el finally
      para enfatizar la intención (está protegido y es seguro).
    """
    async with async_session() as session:
        try:
            yield session
        finally:
            # El context manager ya cierra la sesión; este await es redundante
            # en la mayoría de los casos, pero no causa daño y deja claro
            # que la sesión se cierra siempre.
            await session.close()


# Opcional: función para cerrar el engine al apagar la aplicación
async def shutdown_engine() -> None:
    """Cerrar el engine de SQLAlchemy (por ejemplo, en el evento shutdown)."""
    await engine.dispose()
