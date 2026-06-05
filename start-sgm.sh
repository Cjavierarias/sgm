#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Colores ANSI para una salida más clara.
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
BOLD="\033[1m"
RESET="\033[0m"

info() {
  printf "%b %b%s%b\n" "${BLUE}▶" "${BOLD}" "$1" "${RESET}"
}

success() {
  printf "%b %b%s%b\n" "${GREEN}✔" "${BOLD}" "$1" "${RESET}"
}

warn() {
  printf "%b %b%s%b\n" "${YELLOW}!" "${BOLD}" "$1" "${RESET}"
}

error_exit() {
  printf "%b %b%s%b\n" "${RED}✖" "${BOLD}" "$1" "${RESET}"
  exit 1
}

info "Iniciando SGM..."

if [[ -f "$ROOT/.env" ]]; then
  info "Cargando variables de entorno desde .env"
  export $(grep -v '^\s*#' "$ROOT/.env" | xargs) || true
fi

info "Matando procesos previos..."
pkill -f "uvicorn app.main:app" 2>/dev/null || true
pkill -f "dart:flut" 2>/dev/null || true
pkill -f "python3 -m http.server 8080" 2>/dev/null || true
pkill -f "flutter run -d web-server" 2>/dev/null || true

info "Iniciando PostgreSQL con Docker Compose..."
docker compose -f infra/docker-compose.yml up -d db
sleep 10

info "Verificando contenedor de base de datos..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep db || true

if [[ ! -f "$ROOT/.venv/bin/python" ]]; then
  info "Creando entorno virtual .venv..."
  python3 -m venv "$ROOT/.venv"
fi

info "Instalando dependencias del backend..."
"$ROOT/.venv/bin/python" -m pip install --upgrade pip
"$ROOT/.venv/bin/python" -m pip install -r backend/requirements.txt

info "Aplicando migraciones..."
cd "$ROOT/backend"
"$ROOT/.venv/bin/python" -m alembic upgrade head || warn "Migraciones no aplicadas o ya estaban al día"

info "Iniciando backend FastAPI..."
cd "$ROOT/backend"
nohup "$ROOT/.venv/bin/python" -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload > /tmp/sgm_backend.log 2>&1 &
backend_pid=$!
sleep 5
if curl -s http://localhost:8000/health | grep -q ok; then
  success "Backend levantado en http://localhost:8000"
else
  error_exit "No pudo arrancar el backend. Revisa /tmp/sgm_backend.log"
fi

cd "$ROOT/frontend"

FLUTTER_BIN=""
if command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
else
  error_exit "Flutter no encontrado en PATH"
fi

info "Instalando dependencias de Flutter..."
"$FLUTTER_BIN" pub get

API_URL="http://localhost:8000"
if [[ -f ".env" ]]; then
  if grep -q '^API_BASE_URL=' .env; then
    sed -i "s|^API_BASE_URL=.*|API_BASE_URL=$API_URL|" .env
  else
    echo "API_BASE_URL=$API_URL" >> .env
  fi
else
  echo "API_BASE_URL=$API_URL" > .env
fi

info "Compilando Flutter web..."
"$FLUTTER_BIN" build web --release

if command -v lsof >/dev/null 2>&1; then
  lsof -ti:8080 | xargs -r kill -9 || true
fi

info "Iniciando servidor estático del frontend..."
nohup python3 -m http.server 8080 --directory build/web > /tmp/sgm_frontend.log 2>&1 &
frontend_pid=$!
sleep 5
if curl -s http://127.0.0.1:8080 | grep -qi '<!DOCTYPE html>'; then
  success "Frontend levantado en http://localhost:8080"
else
  error_exit "No pudo arrancar el frontend. Revisa /tmp/sgm_frontend.log"
fi

echo ""
printf "%b" "${GREEN}${BOLD}╔════════════════════════════════════════════════════════╗\n"
printf "%b" "${GREEN}${BOLD}║  SGM arrancado correctamente                          ║\n"
printf "%b" "${GREEN}${BOLD}╠════════════════════════════════════════════════════════╣\n"
printf "%b" "${GREEN}${BOLD}║  Backend: http://localhost:8000                        ║\n"
printf "%b" "${GREEN}${BOLD}║  Frontend: http://localhost:8080                       ║\n"
printf "%b" "${GREEN}${BOLD}║                                                        ║\n"
printf "%b" "${GREEN}${BOLD}║  Logs:                                                 ║\n"
printf "%b" "${GREEN}${BOLD}║  Backend -> /tmp/sgm_backend.log                       ║\n"
printf "%b" "${GREEN}${BOLD}║  Frontend -> /tmp/sgm_frontend.log                     ║\n"
printf "%b" "${GREEN}${BOLD}╚════════════════════════════════════════════════════════╣\n"
printf "%b" "${RESET}\n"
echo "> Si estás en Codespaces, abrí los puertos 8000 y 8080."
