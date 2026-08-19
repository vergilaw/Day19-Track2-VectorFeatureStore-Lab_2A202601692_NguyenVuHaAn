# Task runner for Day 19 Lab on Windows (PowerShell alternative to 'make')
param (
    [Parameter(Position=0)]
    [string]$Target = "help",
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs
)

$ErrorActionPreference = "Stop"

$venvDir = Join-Path $PSScriptRoot ".venv"
$pyExe = Join-Path $venvDir "Scripts\python.exe"
$uvicornExe = Join-Path $venvDir "Scripts\uvicorn.exe"
$jupyterExe = Join-Path $venvDir "Scripts\jupyter.exe"
$pytestExe = Join-Path $venvDir "Scripts\pytest.exe"

function Test-Venv {
    if (-not (Test-Path $pyExe)) {
        Write-Host "Virtual environment not found (.venv\Scripts\python.exe)." -ForegroundColor Yellow
        Write-Host "Please run .\setup-lite.ps1 or .\run.ps1 setup-lite first." -ForegroundColor Cyan
        exit 1
    }
}

function Initialize-JupyterWorkspace {
    $jupyterRoot = Join-Path $PSScriptRoot ".jupyter-local"
    $env:JUPYTER_CONFIG_DIR = Join-Path $jupyterRoot "config"
    $env:JUPYTER_DATA_DIR = Join-Path $jupyterRoot "data"
    $env:JUPYTER_RUNTIME_DIR = Join-Path $jupyterRoot "runtime"
    $env:IPYTHONDIR = Join-Path $jupyterRoot "ipython"
    $env:JUPYTER_ALLOW_INSECURE_WRITES = "1"
    $env:PYTHONWARNINGS = "ignore::UserWarning"
    New-Item -ItemType Directory -Force `
        $env:JUPYTER_CONFIG_DIR, $env:JUPYTER_DATA_DIR, $env:JUPYTER_RUNTIME_DIR, $env:IPYTHONDIR | Out-Null
}

switch ($Target.ToLower()) {
    "setup-lite" {
        & "$PSScriptRoot\setup-lite.ps1"
    }
    "verify-lite" {
        Test-Venv
        & $pyExe scripts/verify_lite.py
    }
    "seed" {
        Test-Venv
        & $pyExe scripts/seed_corpus.py
    }
    "api" {
        Test-Venv
        Write-Host "Starting FastAPI Search API on http://localhost:8000..." -ForegroundColor Cyan
        & $uvicornExe app.main:app --reload --port 8000
    }
    "lab" {
        Test-Venv
        Initialize-JupyterWorkspace
        Write-Host "Converting latest .py notebooks to .ipynb..." -ForegroundColor Yellow
        Get-ChildItem -Path "$PSScriptRoot\notebooks\*.py" | Where-Object { $_.Name -match '^\d+' } | ForEach-Object {
            & $pyExe -m jupytext --to notebook --update $_.FullName
        }
        Write-Host "Launching Jupyter Lab on http://localhost:8888..." -ForegroundColor Cyan
        & $jupyterExe lab --notebook-dir=notebooks --ServerApp.token='' --no-browser
    }
    "benchmark" {
        Test-Venv
        & $pyExe scripts/benchmark.py
    }
    "test" {
        Test-Venv
        & $pytestExe -q
    }
    "gen-advanced" {
        Test-Venv
        & $pyExe scripts/gen_agent_queries.py
        & $pyExe scripts/gen_spend.py
    }
    "notebooks" {
        Test-Venv
        Initialize-JupyterWorkspace
        Write-Host "Converting latest .py notebooks to .ipynb..." -ForegroundColor Yellow
        Get-ChildItem -Path "$PSScriptRoot\notebooks\*.py" | Where-Object { $_.Name -match '^\d+' } | ForEach-Object {
            & $pyExe -m jupytext --to notebook --update $_.FullName 2>$null
        }
        Write-Host "Executing all notebooks headlessly..." -ForegroundColor Cyan
        $pyCode = @"
import asyncio, sys, nbformat
if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
from pathlib import Path
from nbconvert.preprocessors import ExecutePreprocessor

ep = ExecutePreprocessor(timeout=900, kernel_name='day19')
all_passed = True
for nb_path in sorted(Path('notebooks').glob('[0-9]*.ipynb')):
    print(f'  {nb_path.name:<38} ... ', end='', flush=True)
    try:
        with open(nb_path, 'r', encoding='utf-8') as f:
            nb = nbformat.read(f, as_version=4)
        ep.preprocess(nb, {'metadata': {'path': str(nb_path.parent.resolve())}})
        with open(nb_path, 'w', encoding='utf-8') as f:
            nbformat.write(nb, f)
        print('PASS', flush=True)
    except Exception as exc:
        print('FAIL', flush=True)
        print(f'Error: {exc}', flush=True)
        all_passed = False

if not all_passed:
    sys.exit(1)
"@
        & $pyExe -c $pyCode
        if ($LASTEXITCODE -eq 0) {
            Write-Host "`nAll notebooks executed successfully! PASS" -ForegroundColor Green
        } else {
            Write-Host "`nSome notebooks failed execution. FAIL" -ForegroundColor Red
            exit 1
        }
    }
    "clean-lite" {
        Write-Host "Cleaning up generated files and caches..." -ForegroundColor Yellow
        $toRemove = @(
            ".venv",
            "data\corpus_vn.jsonl",
            "data\golden_set.jsonl",
            "data\agent_queries.jsonl",
            "data\qdrant_storage",
            "app\feast_repo\data",
            "app\feast_repo\registry.db",
            "app\feast_repo\online_store.db",
            "app\feast_repo_ondemand\data",
            "app\feast_repo_ondemand\registry.db",
            "app\feast_repo_ondemand\online_store.db",
            "notebooks\*.ipynb",
            "notebooks\.ipynb_checkpoints"
        )
        foreach ($item in $toRemove) {
            $path = Join-Path $PSScriptRoot $item
            if (Test-Path $path) {
                Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
            }
        }
        Write-Host "Clean completed." -ForegroundColor Green
    }
    "setup-docker" {
        & "$PSScriptRoot\setup-docker.ps1"
    }
    "verify-docker" {
        Test-Venv
        & $pyExe scripts/verify_docker.py
    }
    "docker-up" {
        docker compose up -d
    }
    "docker-down" {
        docker compose down
    }
    "docker-clean" {
        docker compose down -v
    }
    Default {
        Write-Host "=========================================================" -ForegroundColor Cyan
        Write-Host "Day 19 - Vector Store + Feature Store (Windows Runner)" -ForegroundColor Cyan
        Write-Host "=========================================================" -ForegroundColor Cyan
        Write-Host "Usage: .\run.ps1 [target]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Lightweight Path (No Docker, in-process):" -ForegroundColor Cyan
        Write-Host "  setup-lite     Create .venv + install deps + seed + smoke test" -ForegroundColor White
        Write-Host "  verify-lite    5-second smoke test (Qdrant + BM25 + Feast SQLite)" -ForegroundColor White
        Write-Host "  seed           (Re)generate data/corpus_vn.jsonl + golden_set.jsonl" -ForegroundColor White
        Write-Host "  api            Start FastAPI /search on http://localhost:8000" -ForegroundColor White
        Write-Host "  lab            Open Jupyter Lab on http://localhost:8888" -ForegroundColor White
        Write-Host "  benchmark      Precision@10 (kw/sem/hyb) + P99 latency table" -ForegroundColor White
        Write-Host "  test           Run pytest test suite" -ForegroundColor White
        Write-Host "  gen-advanced   Generate data for advanced missions (NB6 + NB8)" -ForegroundColor White
        Write-Host "  notebooks      Execute ALL notebooks headlessly (grader test)" -ForegroundColor White
        Write-Host "  clean-lite     Wipe venv + generated data + Feast registry" -ForegroundColor White
        Write-Host ""
        Write-Host "Docker Path (Full stack: Qdrant + Redis + Postgres):" -ForegroundColor Cyan
        Write-Host "  setup-docker   Bring up Docker stack + venv + seed + smoke test" -ForegroundColor White
        Write-Host "  verify-docker  Verify Qdrant/Redis/Postgres reachable" -ForegroundColor White
        Write-Host "  docker-up      Start docker compose services" -ForegroundColor White
        Write-Host "  docker-down    Stop docker services (data persists)" -ForegroundColor White
        Write-Host "  docker-clean   Stop AND wipe volumes" -ForegroundColor White
        Write-Host "=========================================================" -ForegroundColor Cyan
    }
}
