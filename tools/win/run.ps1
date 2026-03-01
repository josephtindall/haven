# run.ps1 — Start the Haven stack (database, cache, and server).
#
# USAGE (run from the repo root):
#   .\tools\win\run.ps1              # start in development mode (default)
#   .\tools\win\run.ps1 -Prod        # start in production mode
#   .\tools\win\run.ps1 -Detach      # start detached (background)
#   .\tools\win\run.ps1 -DbOnly      # start only postgres and redis
#
# WHAT THIS DOES:
#   Development mode (default):
#     - Starts PostgreSQL 16, Redis 7, and Haven with live-reload (Air).
#     - Postgres is exposed on localhost:5432, Redis on localhost:6379,
#       Haven on localhost:8080.
#     - Source code is bind-mounted — edit files and the server auto-restarts.
#     - Safe dev defaults are used when .env is missing (devpassword, zero-key JWT).
#
#   Production mode (-Prod):
#     - Starts the production stack. Haven is NOT exposed directly — it expects
#       a reverse proxy (Caddy) in the consuming project's compose file.
#     - Requires a .env file with real secrets. The server will refuse to start
#       without HAVEN_JWT_SIGNING_KEY and HAVEN_DB_PASS.
#
#   Database only (-DbOnly):
#     - Starts only postgres and redis. Useful when you want to run the Go
#       server directly on the host with `go run ./cmd/server` from src/.
#
# PREREQUISITES:
#   - Docker Desktop must be running.
#   - For production mode, copy .env.example to .env and fill in secrets:
#       copy .env.example .env
#       cd src && go run ./cmd/cli generate-secrets
#     Then paste the output into .env.

param(
    [switch]$Prod,
    [switch]$Detach,
    [switch]$DbOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot ".." "..")

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   $msg" -ForegroundColor Green }

function Assert-Tool($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Error "'$name' is not installed or not in PATH. Please install it first."
    }
}

Assert-Tool "docker"

# ── Determine compose file and services ──────────────────────────────────────

Push-Location $RepoRoot
try {
    if ($Prod) {
        $composeFile = "docker-compose.yml"
        $mode = "production"
    } else {
        $composeFile = "docker-compose.dev.yml"
        $mode = "development"
    }

    # Warn about missing .env in production mode.
    if ($Prod -and -not (Test-Path (Join-Path $RepoRoot ".env"))) {
        Write-Host "`n!! WARNING: No .env file found. Production mode requires real secrets." -ForegroundColor Red
        Write-Host "   Copy .env.example to .env and run: cd src && go run ./cmd/cli generate-secrets" -ForegroundColor Yellow
        Write-Host ""
    }

    # Build the docker compose command.
    $args_ = @("compose", "-f", $composeFile, "up")

    if ($Detach) { $args_ += "-d" }

    # If DbOnly, only start postgres and redis (not haven).
    if ($DbOnly) {
        $args_ += @("postgres", "redis")
        $mode += " (database + redis only)"
    }

    Write-Step "Starting Haven in $mode mode"
    Write-Host "   Compose file : $composeFile" -ForegroundColor DarkGray
    Write-Host "   Command      : docker $($args_ -join ' ')" -ForegroundColor DarkGray

    if (-not $Prod) {
        Write-Host ""
        Write-Host "   Endpoints (dev mode):" -ForegroundColor DarkGray
        if (-not $DbOnly) {
            Write-Host "     Haven API  : http://localhost:8080" -ForegroundColor DarkGray
        }
        Write-Host "     PostgreSQL : localhost:5432" -ForegroundColor DarkGray
        Write-Host "     Redis      : localhost:6379" -ForegroundColor DarkGray
    }

    Write-Host ""

    & docker @args_

    # Exit code 130 (or similar) is normal when the user presses Ctrl+C.
    # Only report genuine failures.
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 130) {
        Write-Error "docker compose failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
