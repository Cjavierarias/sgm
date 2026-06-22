# ============================================================
#  SGM — BSA Consultora
#  Script de inicio para Windows (PowerShell)
#
#  CÓMO EJECUTAR (desde PowerShell):
#    .\start-sgm.ps1
#
#  Si da error de política de ejecución, primero correr:
#    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
# ============================================================

$Root          = Split-Path -Parent $MyInvocation.MyCommand.Path
$CondaBase     = "C:\Users\Javier\anaconda3"
$CondaEnv      = "sgm"
$FlutterExe    = "C:\desarrollador\flutter\flutter\bin\flutter.bat"
$BackendPort   = 8000
$FrontendPort  = 8080

# ── Colores ──────────────────────────────────────────────────
function Info  ($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function OK    ($msg) { Write-Host "  OK $msg" -ForegroundColor Green }
function Warn  ($msg) { Write-Host "  !! $msg" -ForegroundColor Yellow }
function Err   ($msg) { Write-Host "  XX $msg" -ForegroundColor Red }

Clear-Host
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Blue
Write-Host "   SGM  |  BSA Consultora  |  Iniciando..." -ForegroundColor Blue
Write-Host "  ============================================================" -ForegroundColor Blue
Write-Host ""

# ── 1. Liberar puertos ───────────────────────────────────────
Info "Liberando puertos $BackendPort y $FrontendPort..."
foreach ($port in @($BackendPort, $FrontendPort)) {
    $pids = netstat -aon | Select-String ":$port\s" | ForEach-Object {
        ($_ -split "\s+")[-1]
    } | Sort-Object -Unique
    foreach ($p in $pids) {
        if ($p -match '^\d+$' -and $p -ne '0') {
            try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}
OK "Puertos liberados."

# ── 2. Iniciar Backend en nueva ventana CMD ───────────────────
Info "Iniciando Backend FastAPI (puerto $BackendPort)..."

$backendCmd = "title SGM Backend & call `"$CondaBase\Scripts\activate.bat`" $CondaEnv & cd /d `"$Root\backend`" & pip install -r requirements.txt -q & uvicorn app.main:app --reload --host 0.0.0.0 --port $BackendPort"

Start-Process "cmd.exe" -ArgumentList "/k", $backendCmd

# ── 3. Esperar a que el backend responda ──────────────────────
Info "Esperando que el backend esté listo..."
$maxWait = 60
$waited  = 0
do {
    Start-Sleep -Seconds 2
    $waited += 2
    $ok = $false
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:$BackendPort/health" -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
        $ok = ($resp.StatusCode -eq 200)
    } catch {}
    if (-not $ok) { Write-Host "    ...esperando backend ($waited s)..." -ForegroundColor DarkGray }
} while (-not $ok -and $waited -lt $maxWait)

if ($waited -ge $maxWait) {
    Warn "El backend tardó más de lo esperado. Continuando de todas formas..."
} else {
    OK "Backend listo en http://localhost:$BackendPort"
}

# ── 4. Iniciar Frontend Flutter en nueva ventana CMD ─────────
Info "Iniciando Frontend Flutter (puerto $FrontendPort)..."

$frontendCmd = "title SGM Frontend & cd /d `"$Root\frontend`" & `"$FlutterExe`" run -d web-server --web-port $FrontendPort --dart-define=API_URL=http://localhost:$BackendPort"

Start-Process "cmd.exe" -ArgumentList "/k", $frontendCmd

# ── 5. Esperar al frontend ────────────────────────────────────
Info "Esperando que el frontend esté listo..."
$waited = 0
do {
    Start-Sleep -Seconds 3
    $waited += 3
    $ok = $false
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:$FrontendPort" -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        $ok = ($resp.StatusCode -eq 200)
    } catch {}
    if (-not $ok) { Write-Host "    ...esperando frontend ($waited s)..." -ForegroundColor DarkGray }
} while (-not $ok -and $waited -lt 120)

if ($waited -ge 120) {
    Warn "El frontend tardó más de lo esperado. Abriendo navegador de todas formas..."
} else {
    OK "Frontend listo en http://localhost:$FrontendPort"
}

# ── 6. Abrir navegador ────────────────────────────────────────
Info "Abriendo navegador..."
Start-Process "http://localhost:$FrontendPort"

Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "   SGM iniciado correctamente" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "   Backend:   http://localhost:$BackendPort" -ForegroundColor White
Write-Host "   Frontend:  http://localhost:$FrontendPort" -ForegroundColor White
Write-Host "   API Docs:  http://localhost:$BackendPort/docs" -ForegroundColor White
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Esta ventana puede cerrarse. Los servicios corren en sus" -ForegroundColor DarkGray
Write-Host "  propias ventanas de CMD." -ForegroundColor DarkGray
Write-Host ""
