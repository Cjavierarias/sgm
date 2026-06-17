# SGM — Sistema de Gestión de Mantenimiento
### BSA Consultora

Plataforma SaaS multi-tenant para gestión de mantenimiento industrial.
Desarrollado y mantenido por **BSA Consultora**.

## Stack
- **Backend:** Python 3.11 · FastAPI · PostgreSQL 15 · SQLAlchemy 2.0 async
- **Frontend:** Flutter 3 (Android · iOS · Web)
- **Infra:** Docker Compose · Nginx (HTTPS) · Google Drive API (opcional)

## Características
- Gestión de órdenes de trabajo (correctivas/preventivas/predictivas)
- Control de equipos e historial de mantenimiento
- Inventario de repuestos y movimientos de stock
- Gestión de proveedores y órdenes de compra
- Sistema de notificaciones en tiempo real
- Multi-tenant (múltiples empresas por instancia)
- Control de acceso por roles (admin, maintenance_manager, technician, warehouse, purchasing, hr, viewer)

## Arranque rápido (desarrollo)

### Opción A — Script automático (Linux/macOS)
```bash
chmod +x start-sgm.sh && ./start-sgm.sh
```

### Opción B — Manual (Windows)
**Terminal 1 — Backend:**
```cmd
conda activate sgm
cd backend
uvicorn app.main:app --reload --port 8000
```

**Terminal 2 — Frontend:**
```cmd
cd frontend
flutter run -d web-server --web-port 8080 --dart-define=API_URL=http://localhost:8000
```

### Opción C — Docker Compose
```bash
cp .env.example .env        # Completar variables
docker compose -f infra/docker-compose.yml up --build
```

## Pruebas

Después de ejecutar `./start-sgm.sh`, puedes iniciar sesión con:

- **Email**: `test@example.com`
- **Contraseña**: `password123`

    admin@example.com     / password123  → Admin
   jefe@example.com      / password123  → Jefe Mantenimiento
   tecnico@example.com   / password123  → Técnico
   deposito@example.com  / password123  → Depósito
   compras@example.com   / password123  → Compras
   test@example.com      / password123  → Admin + Jefe

Si necesitas crear más usuarios de prueba:

```bash
.venv/bin/python create_test_user.py
```

## Estructura

## Secuencia de arranque (guardar esto)

## Terminal 1 — Anaconda Prompt:

cmdconda activate sgm
cd C:\Users\Javier\Documents\GitHub\sgm\backend
uvicorn app.main:app --reload --port 8000

## Terminal 2 — CMD normal:

cd C:\Users\Javier\Documents\GitHub\sgm\frontend
flutter run -d web-server --web-port 8080

## pegar esto en prompt de anaconcda
cd C:\Users\Javier\Documents\GitHub\sgm\backend
uvicorn app.main:app --reload --port 8000