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
- **Sistema de cobros SaaS** con Mercado Pago (trial 30 días → mensual USD 5 / anual USD 50)

---

## 💳 Sistema de Facturación — Mercado Pago

### Modelo de negocio
| Período | Precio | Incluye |
|---|---|---|
| Prueba gratuita | USD 0 | 30 días completos |
| Mensual | USD 5/mes | 1 admin · 1 empresa · colaboradores ilimitados |
| Anual | USD 50/año | Ídem (equivale a 2 meses gratis) |

### Flujo de vida de una suscripción
```
Registro → [trial 30 días] → Vencimiento → [grace 90 días] → Suspensión + purga de datos
                ↑                               ↑
           Pago aprobado ──────────────── Pago aprobado → estado "active"
```

- **Trial**: 30 días gratis al registrarse. Acceso completo.
- **Active**: Pago al día. El período se renueva con cada pago aprobado.
- **Grace**: El pago venció pero los datos se conservan 90 días para darle oportunidad al cliente de pagar.
- **Suspended**: Pasados los 90 días sin pago, los datos operativos se purgan automáticamente.
- **Bloqueo de email**: El email del admin queda en lista negra y no puede registrar una nueva empresa hasta regularizar.

### Configuración de Mercado Pago (pasos para el operador)

1. Creá tu cuenta en [mercadopago.com.ar/developers](https://www.mercadopago.com.ar/developers/panel/app)
2. Creá una nueva **aplicación** → tipo **Checkout Pro**
3. En **Credenciales de producción** copiá:
   - `Access Token` (empieza con `APP_USR-...`) → variable `MP_ACCESS_TOKEN`
   - `Public Key` → variable `MP_PUBLIC_KEY`
4. Configurá el **Webhook** en el panel de MP:
   - URL: `https://TU_DOMINIO/billing/webhook`
   - Eventos: `payment`
   - Copiá el **Secreto** generado → variable `MP_WEBHOOK_SECRET`
5. Completá las variables en `.env` (ver `.env.example` sección Mercado Pago)

### Variables de entorno requeridas
```env
MP_ACCESS_TOKEN=APP_USR-xxxx          # Tu access token de producción
MP_PUBLIC_KEY=APP_USR-yyyy            # Tu clave pública
MP_WEBHOOK_SECRET=abc123              # Secreto del webhook (lo genera MP)
APP_BASE_URL=https://api.tudominio.com
FRONTEND_URL=https://app.tudominio.com
ADMIN_CRON_SECRET=secreto_cron
```

### Migración de base de datos
Después de actualizar, aplicar la migración de Alembic:
```bash
conda activate sgm
cd backend
alembic upgrade head
```

### Endpoints de facturación
| Método | URL | Descripción |
|---|---|---|
| GET | `/billing/status` | Estado de suscripción (todos los usuarios) |
| POST | `/billing/checkout` | Generar URL de pago Checkout Pro (solo admin) |
| POST | `/billing/subscribe` | Crear suscripción recurrente MP (solo admin) |
| POST | `/billing/webhook` | Webhook de Mercado Pago (no requiere auth) |
| GET | `/billing/history` | Historial de pagos (solo admin) |
| POST | `/billing/admin/check-subscriptions?secret=X` | Cron manual |

---

## Arranque rápido (desarrollo)

### Opción A — Script PowerShell (Windows) ⭐ recomendado
```powershell
.\start-sgm.ps1
```
> Si da error de política de ejecución, ejecutar **una sola vez**:
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
> ```

### Opción B — Doble clic (Windows)
Hacer doble clic en **`start-sgm.bat`** desde el Explorador de archivos.

### Opción C — Manual (Windows, dos terminales)
**Anaconda Prompt — Backend:**
```cmd
conda activate sgm
cd C:\Users\Javier\Documents\GitHub\sgm\backend
uvicorn app.main:app --reload --port 8000
```

**CMD normal — Frontend:**
```cmd
cd C:\Users\Javier\Documents\GitHub\sgm\frontend
flutter run -d web-server --web-port 8080 --dart-define=API_URL=http://localhost:8000
```

### Opción D — Script automático (Linux/macOS)
```bash
chmod +x start-sgm.sh
./start-sgm.sh
```

### Opción E — Docker Compose
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