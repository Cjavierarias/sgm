@echo off
:: ============================================================
::  SGM — BSA Consultora
::  Script de inicio para Windows
::  Abre el backend y el frontend en terminales separadas
::  y luego abre el navegador en http://localhost:8080
:: ============================================================

title SGM — BSA Consultora

set ROOT=%~dp0
set CONDA=C:\Users\Javier\anaconda3
set FLUTTER=C:\desarrollador\flutter\flutter\bin\flutter.bat
set BACKEND_PORT=8000
set FRONTEND_PORT=8080

echo.
echo  ============================================================
echo   SGM ^| BSA Consultora ^| Iniciando...
echo  ============================================================
echo.

:: ── 1. Matar procesos anteriores en los puertos 8000 y 8080 ──
echo [1/4] Liberando puertos %BACKEND_PORT% y %FRONTEND_PORT%...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":%BACKEND_PORT% " 2^>nul') do (
    taskkill /F /PID %%a >nul 2>&1
)
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":%FRONTEND_PORT% " 2^>nul') do (
    taskkill /F /PID %%a >nul 2>&1
)
echo    Puertos liberados.

:: ── 2. Iniciar Backend FastAPI en nueva terminal ──────────────
echo [2/4] Iniciando Backend FastAPI (puerto %BACKEND_PORT%)...
start "SGM Backend" cmd /k "title SGM Backend ^& call %CONDA%\Scripts\activate.bat sgm ^& cd /d %ROOT%backend ^& echo Backend iniciando... ^& uvicorn app.main:app --reload --host 0.0.0.0 --port %BACKEND_PORT%"

:: Esperar a que el backend levante
echo    Esperando que el backend este listo...
:WAIT_BACKEND
timeout /t 2 /nobreak >nul
curl -s http://localhost:%BACKEND_PORT%/health >nul 2>&1
if %errorlevel% neq 0 (
    echo    ...esperando backend...
    goto WAIT_BACKEND
)
echo    Backend listo en http://localhost:%BACKEND_PORT%

:: ── 3. Iniciar Frontend Flutter en nueva terminal ─────────────
echo [3/4] Iniciando Frontend Flutter (puerto %FRONTEND_PORT%)...
start "SGM Frontend" cmd /k "title SGM Frontend ^& cd /d %ROOT%frontend ^& echo Frontend iniciando... ^& %FLUTTER% run -d web-server --web-port %FRONTEND_PORT% --dart-define=API_URL=http://localhost:%BACKEND_PORT%"

:: Esperar a que el frontend levante
echo    Esperando que el frontend este listo...
:WAIT_FRONTEND
timeout /t 3 /nobreak >nul
curl -s http://localhost:%FRONTEND_PORT% >nul 2>&1
if %errorlevel% neq 0 (
    echo    ...esperando frontend...
    goto WAIT_FRONTEND
)
echo    Frontend listo en http://localhost:%FRONTEND_PORT%

:: ── 4. Abrir navegador ────────────────────────────────────────
echo [4/4] Abriendo navegador...
start "" "http://localhost:%FRONTEND_PORT%"

echo.
echo  ============================================================
echo   SGM iniciado correctamente
echo  ============================================================
echo   Backend:   http://localhost:%BACKEND_PORT%
echo   Frontend:  http://localhost:%FRONTEND_PORT%
echo   API Docs:  http://localhost:%BACKEND_PORT%/docs
echo  ============================================================
echo.
echo  Esta ventana puede cerrarse. Los servicios siguen corriendo
echo  en sus propias terminales.
echo.
pause
