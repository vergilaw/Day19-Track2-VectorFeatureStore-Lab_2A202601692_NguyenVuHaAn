# Lite path setup script for Windows (PowerShell)
# Pure Python, in-process Qdrant, SQLite Feast online store.
# No Docker, no GPU required.

$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "[lite] Day 19 lightweight setup (Windows PowerShell)" -ForegroundColor Cyan
Write-Host "[lite] Stack: fastembed + qdrant-client[memory] + rank-bm25 + feast(sqlite) + FastAPI" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Python check ─────────────────────────────────────────────────────
$pythonCmd = "python"
try {
    $verOutput = & $pythonCmd --version 2>&1
    Write-Host "[lite] Found: $verOutput" -ForegroundColor Green
} catch {
    try {
        $pythonCmd = "py"
        $verOutput = & $pythonCmd --version 2>&1
        Write-Host "[lite] Found: $verOutput" -ForegroundColor Green
    } catch {
        Write-Host "[lite] ERROR: Python 3.10+ is required but not found in PATH." -ForegroundColor Red
        Write-Host "Please install Python from https://www.python.org/ or Microsoft Store and check 'Add Python to PATH'." -ForegroundColor Yellow
        exit 1
    }
}

# ── 2. venv creation ────────────────────────────────────────────────────
$venvDir = Join-Path $PSScriptRoot ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"

if (-not (Test-Path $venvDir)) {
    Write-Host "[lite] Creating virtual environment at .venv..." -ForegroundColor Yellow
    & $pythonCmd -m venv $venvDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[lite] ERROR: Failed to create virtual environment." -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path $venvPython)) {
    Write-Host "[lite] ERROR: Virtual environment python not found at $venvPython" -ForegroundColor Red
    exit 1
}

# Keep Jupyter state inside the repo so setup also works on restricted or
# network-mounted Windows filesystems.
$jupyterRoot = Join-Path $PSScriptRoot ".jupyter-local"
$env:JUPYTER_CONFIG_DIR = Join-Path $jupyterRoot "config"
$env:JUPYTER_DATA_DIR = Join-Path $jupyterRoot "data"
$env:JUPYTER_RUNTIME_DIR = Join-Path $jupyterRoot "runtime"
$env:IPYTHONDIR = Join-Path $jupyterRoot "ipython"
$env:JUPYTER_ALLOW_INSECURE_WRITES = "1"
$env:PYTHONWARNINGS = "ignore::UserWarning"
New-Item -ItemType Directory -Force `
    $env:JUPYTER_CONFIG_DIR, $env:JUPYTER_DATA_DIR, $env:JUPYTER_RUNTIME_DIR, $env:IPYTHONDIR | Out-Null

# ── 3. Install dependencies ─────────────────────────────────────────────
Write-Host "[lite] Checking Python version in venv..." -ForegroundColor Yellow
$pyVerCheck = & $venvPython -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}'); print(1 if sys.version_info >= (3, 14) else 0)"
$lines = $pyVerCheck -split "`r?`n"
$venvPyVer = $lines[0]
$isPy314OrHigher = if ($lines.Length -gt 1) { $lines[1] } else { "0" }

Write-Host "[lite] venv Python version: $venvPyVer" -ForegroundColor Green

Write-Host "[lite] Upgrading pip..." -ForegroundColor Yellow
& $venvPython -m pip install -q --upgrade pip

Write-Host "[lite] Installing dependencies from requirements.txt (this may take ~1-2 min)..." -ForegroundColor Yellow
& $venvPython -m pip install -r requirements.txt

Write-Host "[lite] Registering Jupyter kernel for venv..." -ForegroundColor Yellow
& $venvPython -m ipykernel install --prefix $venvDir --name day19 --display-name "Python (Day 19)" --quiet

if ($isPy314OrHigher -eq "1") {
    Write-Host "[lite] Python >= 3.14 detected: applying dill>=0.4 override..." -ForegroundColor Yellow
    & $venvPython -m pip install -q --upgrade "dill>=0.4,<1.0"
}

# ── 4. Convert Jupytext sources to .ipynb ───────────────────────────────
Write-Host "[lite] Converting Jupytext notebook files to .ipynb..." -ForegroundColor Yellow
Get-ChildItem -Path "$PSScriptRoot\notebooks\*.py" | Where-Object { $_.Name -match '^\d+' } | ForEach-Object {
    & $venvPython -m jupytext --to notebook --update $_.FullName
}

# ── 5. .env scaffold ────────────────────────────────────────────────────
$envFile = Join-Path $PSScriptRoot ".env"
$envExample = Join-Path $PSScriptRoot ".env.example"
if (-not (Test-Path $envFile)) {
    Write-Host "[lite] Creating .env from .env.example..." -ForegroundColor Yellow
    Copy-Item $envExample $envFile
}

# ── 6. Seed corpus + golden set + advanced data ─────────────────────────
Write-Host "[lite] Seeding corpus and golden set..." -ForegroundColor Yellow
& $venvPython scripts/seed_corpus.py

Write-Host "[lite] Seeding advanced-mission data (NB6 + NB8)..." -ForegroundColor Yellow
& $venvPython scripts/gen_agent_queries.py
& $venvPython scripts/gen_spend.py

# ── 7. Smoke test ───────────────────────────────────────────────────────
Write-Host "[lite] Running smoke test..." -ForegroundColor Yellow
& $venvPython scripts/verify_lite.py

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=========================================================" -ForegroundColor Green
    Write-Host "[lite] Setup completed successfully! All checks passed." -ForegroundColor Green
    Write-Host "=========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can run tasks easily with .\run.ps1 or activated venv:" -ForegroundColor Cyan
    Write-Host "  .\run.ps1 api         # Start FastAPI search server on :8000" -ForegroundColor White
    Write-Host "  .\run.ps1 lab         # Open Jupyter Lab on :8888" -ForegroundColor White
    Write-Host "  .\run.ps1 benchmark   # Run Precision@10 & Latency benchmark" -ForegroundColor White
    Write-Host "  .\run.ps1 test        # Run pytest test suite" -ForegroundColor White
    Write-Host ""
    Write-Host "Or activate the venv directly in PowerShell:" -ForegroundColor Cyan
    Write-Host "  .venv\Scripts\Activate.ps1" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "[lite] Smoke test reported errors. Please review output above." -ForegroundColor Red
}
