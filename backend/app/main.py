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
from app.routers.purchases import suppliers_router, po_router, invoices_router
from app.routers.quote_requests import router as quote_router
from app.routers.planning import router as planning_router
from app.routers.billing import router as billing_router
from app.routers.invitations import router as invitations_router
from app.routers.calendar import router as calendar_router
from app.routers.exports import router as exports_router
from app.scheduler import start_scheduler, stop_scheduler

# ─── Rate limiter global ───────────────────────────────────────────────────────
limiter = Limiter(key_func=get_remote_address)

# ─── CORS: orígenes permitidos desde variable de entorno ──────────────────────
_raw_origins = os.getenv("ALLOWED_ORIGINS", "http://localhost:8080,http://localhost:3000,http://127.0.0.1:8080,http://localhost:5173,http://127.0.0.1:5173")
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
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = "/tmp/sgm_uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")


@app.on_event("startup")
async def startup_event() -> None:
    async with engine.begin() as conn:
        await conn.execute(text("SELECT 1"))
        await conn.run_sync(Base.metadata.create_all)
    # Importar modelos de suscripción para que create_all los incluya
    from app.models import subscription  # noqa: F401
    from app.models import collaboration  # noqa: F401
    async with engine.begin() as conn:
        await conn.run_sync(subscription.Base.metadata.create_all)
        await conn.run_sync(collaboration.Base.metadata.create_all)
    start_scheduler()


@app.on_event("shutdown")
async def shutdown_event() -> None:
    stop_scheduler()


app.include_router(auth_router)
app.include_router(wo_router)
app.include_router(eq_router)
app.include_router(notif_router)
app.include_router(dashboard_router)
app.include_router(sp_router)
app.include_router(sp_req_router)
app.include_router(suppliers_router)
app.include_router(po_router)
app.include_router(invoices_router)
app.include_router(quote_router)
app.include_router(planning_router)
app.include_router(billing_router)
app.include_router(invitations_router)
app.include_router(calendar_router)
app.include_router(exports_router)


@app.get("/health")
async def health():
    return {"status": "ok", "version": "2.3.0"}
