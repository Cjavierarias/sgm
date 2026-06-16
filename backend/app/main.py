"""Punto de entrada principal de la API SGM — BSA Consultora."""
from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI

# Cargar .env desde la raíz del repositorio (un nivel arriba de /backend)
_ENV_FILE = Path(__file__).resolve().parents[2] / ".env"
load_dotenv(dotenv_path=_ENV_FILE, override=False)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.staticfiles import StaticFiles
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from sqlalchemy import text

from app.database import engine
from app.models.base import Base
from app.routers.auth import router as auth_router
from app.routers.work_orders import router as wo_router
from app.routers.equipments import router as eq_router
from app.routers.notifications import router as notif_router
from app.routers.dashboard import router as dashboard_router
from app.routers.spare_parts import router as sp_router
from app.routers.spare_parts import requests_router as sp_req_router

# ─── Rate limiter global ───────────────────────────────────────────────────────
limiter = Limiter(key_func=get_remote_address)

# ─── CORS: orígenes permitidos desde variable de entorno ──────────────────────
_raw_origins = os.getenv("ALLOWED_ORIGINS", "http://localhost:8080,http://localhost:3000")
ALLOWED_ORIGINS: list[str] = [o.strip() for o in _raw_origins.split(",") if o.strip()]

app = FastAPI(
    title="SGM API — BSA Consultora",
    version="2.2.0",
    description="Sistema de Gestión de Mantenimiento Industrial",
    docs_url="/docs",
    redoc_url="/redoc",
)

# Rate limiter handler
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)

UPLOAD_DIR = "/tmp/sgm_uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")


@app.on_event("startup")
async def startup_event() -> None:
    async with engine.begin() as conn:
        await conn.execute(text("SELECT 1"))
        await conn.run_sync(Base.metadata.create_all)


app.include_router(auth_router)
app.include_router(wo_router)
app.include_router(eq_router)
app.include_router(notif_router)
app.include_router(dashboard_router)
app.include_router(sp_router)
app.include_router(sp_req_router)


@app.get("/health")
async def health():
    return {"status": "ok", "version": "2.1.0"}
