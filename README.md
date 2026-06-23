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
- **Invitaciones por email** a colaboradores con token de un solo uso
- **Calendario compartido** sincronizado con Google Calendar
- **Exportación a Google Sheets** de OT, repuestos, equipos y planes
- **Integración Google Workspace** (Drive, Calendar, Sheets)

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

## 📧 Invitaciones por Email

El admin invita colaboradores por email. El invitado recibe un link con token y completa su registro.

### Flujo
```
Admin → POST /invitations (email + rol) → Email con link → Invitado acepta → Usuario creado + auto-login
```

### Endpoints
| Método | URL | Descripción |
|---|---|---|
| POST | `/invitations` | Enviar invitación (admin/hr) |
| GET | `/invitations` | Listar invitaciones (admin/hr) |
| POST | `/invitations/{id}/revoke` | Revocar (admin/hr) |
| GET | `/invitations/{token}` | Validar token (público) |
| POST | `/invitations/{token}/accept` | Aceptar y crear cuenta (público) |

### Configuración SMTP
```env
SMTP_ENABLED=true
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=tu_email@gmail.com
SMTP_PASSWORD=app_password_de_16_caracteres
```
> En desarrollo (`SMTP_ENABLED=false`) los emails se loguean en consola.

---

## 📅 Calendario Compartido + Google Calendar

Sincronización de planes de mantenimiento con Google Calendar del admin.

### Flujo
```
Admin → POST /calendar/company (crea calendario Google) → Comparte con colaboradores
Admin → POST /maintenance-plans/{id}/sync → Crea evento en Google Calendar
Colaboradores ven el calendario compartido en su Google Calendar
```

### Endpoints
| Método | URL | Descripción |
|---|---|---|
| GET | `/calendar/events` | Eventos de la empresa (rango de fechas) |
| POST | `/calendar/company` | Crear calendario Google (admin) |
| POST | `/calendar/share/{user_id}` | Compartir con usuario (admin) |
| POST | `/maintenance-plans/{id}/sync` | Sincronizar plan con Calendar |
| DELETE | `/calendar/events/{id}` | Eliminar evento |

---

## 📊 Exportación a Google Sheets

Exporta datos tabulares a una hoja de cálculo de Google Sheets compartida con el admin.

### Endpoints
| Método | URL | Descripción |
|---|---|---|
| POST | `/export/work-orders/sheets` | Exportar OT |
| POST | `/export/spare-parts/sheets` | Exportar repuestos |
| POST | `/export/equipments/sheets` | Exportar equipos |
| POST | `/export/maintenance-plans/sheets` | Exportar planes |

Cada exportación crea una nueva hoja en el Drive del admin, con encabezados formateados y compartida con permisos de escritor.

---

## 🔧 Configuración Google Workspace

Para habilitar Calendar, Sheets y Drive:

1. **Google Cloud Console** → Crear proyecto → Habilitar APIs:
   - Google Calendar API
   - Google Sheets API
   - Google Drive API

2. **Service Account** → IAM → Service Accounts → Crear → Descargar JSON

3. **Compartir calendario** con el email de la service account (`xxx@project.iam.gserviceaccount.com`)

4. **Variables de entorno:**
```env
GOOGLE_SERVICE_ACCOUNT_FILE=/ruta/al/service-account.json
GOOGLE_DRIVE_DOMAIN=miempresa.com
```

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

.\start-sgm.ps1