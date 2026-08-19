# Full Docker path setup script for Windows (PowerShell)
# Qdrant server + Redis online store + Postgres offline store + bge-m3 embeddings

$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "[docker] Day 19 full Docker setup (Windows PowerShell)" -ForegroundColor Cyan
Write-Host "[docker] Stack: Qdrant (server) + Redis + Postgres + bge-m3 embeddings" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Check Docker ─────────────────────────────────────────────────────
try {
    $dockerVer = & docker --version 2>&1
    Write-Host "[docker] Found Docker: $dockerVer" -ForegroundColor Green
} catch {
    Write-Host "[docker] ERROR: Docker is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please start Docker Desktop or install Docker first." -ForegroundColor Yellow
    exit 1
}

Write-Host "[docker] Starting Docker services (Qdrant + Redis + Postgres)..." -ForegroundColor Yellow
& docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Host "[docker] ERROR: Failed to start docker compose services." -ForegroundColor Red
    exit 1
}

Write-Host "[docker] Waiting up to 30s for services to be healthy..." -ForegroundColor Yellow
$healthy = $false
for ($i = 1; $i -le 30; $i++) {
    Start-Sleep -Seconds 1
    $psOut = & docker compose ps --format json 2>&1
    if ($psOut -match '"Health":"healthy"') {
        $healthy = $true
        break
    }
}
if ($healthy) {
    Write-Host "[docker] Services are healthy!" -ForegroundColor Green
} else {
    Write-Host "[docker] Note: Service health check timed out or not supported; continuing..." -ForegroundColor Yellow
}

# ── 2. venv creation ────────────────────────────────────────────────────
$pythonCmd = "python"
try {
    & $pythonCmd --version | Out-Null
} catch {
    $pythonCmd = "py"
}

$venvDir = Join-Path $PSScriptRoot ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"

if (-not (Test-Path $venvDir)) {
    Write-Host "[docker] Creating virtual environment at .venv..." -ForegroundColor Yellow
    & $pythonCmd -m venv $venvDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[docker] ERROR: Failed to create virtual environment." -ForegroundColor Red
        exit 1
    }
}

# ── 3. Install deps ─────────────────────────────────────────────────────
Write-Host "[docker] Upgrading pip..." -ForegroundColor Yellow
& $venvPython -m pip install -q --upgrade pip

Write-Host "[docker] Installing requirements.txt + requirements-full.txt (this may take ~2-4 min)..." -ForegroundColor Yellow
& $venvPython -m pip install -r requirements.txt -r requirements-full.txt
if ($LASTEXITCODE -ne 0) {
    Write-Host "[docker] ERROR: Failed to install requirements." -ForegroundColor Red
    exit 1
}

# ── 4. Convert notebooks ────────────────────────────────────────────────
Write-Host "[docker] Converting Jupytext notebook files to .ipynb..." -ForegroundColor Yellow
Get-ChildItem -Path "$PSScriptRoot\notebooks\*.py" | Where-Object { $_.Name -match '^\d+' } | ForEach-Object {
    & $venvPython -m jupytext --to notebook --update $_.FullName
}

# ── 5. .env setup for Docker mode ───────────────────────────────────────
$envFile = Join-Path $PSScriptRoot ".env"
$envExample = Join-Path $PSScriptRoot ".env.example"
if (-not (Test-Path $envFile)) {
    Write-Host "[docker] Creating .env configured for Docker..." -ForegroundColor Yellow
    $envContent = Get-Content $envExample -Raw
    $envContent = $envContent -replace "^QDRANT_MODE=memory", "QDRANT_MODE=server"
    $envContent = $envContent -replace "^EMBEDDING_BACKEND=fastembed", "EMBEDDING_BACKEND=bge-m3"
    $envContent = $envContent -replace "^FEAST_ONLINE_STORE=sqlite", "FEAST_ONLINE_STORE=redis"
    $envContent = $envContent -replace "^FEAST_OFFLINE_STORE=file", "FEAST_OFFLINE_STORE=postgres"
    Set-Content -Path $envFile -Value $envContent -Encoding utf8
}

# ── 6. Seed corpus + golden set + advanced data ─────────────────────────
Write-Host "[docker] Seeding corpus and golden set..." -ForegroundColor Yellow
& $venvPython scripts/seed_corpus.py

Write-Host "[docker] Seeding advanced-mission data (NB6 + NB8)..." -ForegroundColor Yellow
& $venvPython scripts/gen_agent_queries.py
& $venvPython scripts/gen_spend.py

# ── 7. Verify docker stack ──────────────────────────────────────────────
Write-Host "[docker] Verifying docker connectivity..." -ForegroundColor Yellow
& $venvPython scripts/verify_docker.py

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=========================================================" -ForegroundColor Green
    Write-Host "[docker] Setup completed! Services running:" -ForegroundColor Green
    Write-Host "  Qdrant   -> http://localhost:6333 (dashboard: /dashboard)" -ForegroundColor Cyan
    Write-Host "  Redis    -> redis://localhost:6379" -ForegroundColor Cyan
    Write-Host "  Postgres -> postgresql://feast:feast@localhost:5432/feast_offline" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Run commands via .\run.ps1:" -ForegroundColor Cyan
    Write-Host "  .\run.ps1 api           # Start FastAPI search server on :8000" -ForegroundColor White
    Write-Host "  .\run.ps1 lab           # Open Jupyter Lab on :8888" -ForegroundColor White
    Write-Host "  .\run.ps1 benchmark     # Run Precision@10 & Latency benchmark" -ForegroundColor White
    Write-Host "  .\run.ps1 docker-down   # Stop Docker services" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "[docker] Verification failed. Please check the logs above." -ForegroundColor Red
}
