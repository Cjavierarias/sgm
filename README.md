# sgm
# SGM - Sistema de Gestión de Mantenimiento

Plataforma SaaS para gestión de mantenimiento industrial.

## Stack
- Backend: Python + FastAPI + PostgreSQL
- Frontend: Flutter (Android, iOS, Web)
- Infra: Docker + Nginx + Google Workspace APIs

## Arranque rápido
1. Otorga permisos al script si no los tiene:

```bash
chmod +x start-sgm.sh
```

2. Ejecuta el script:

```bash
./start-sgm.sh
```

3. Alias opcional para arranque más directo:

```bash
alias sgm-start="/workspaces/sgm/start-sgm.sh"
```

Luego podrás usar:

```bash
sgm-start
```

## Pruebas

Después de ejecutar `./start-sgm.sh`, puedes iniciar sesión con:

- **Email**: `test@example.com`
- **Contraseña**: `password123`

Si necesitas crear más usuarios de prueba:

```bash
.venv/bin/python create_test_user.py
```

## Estructura
