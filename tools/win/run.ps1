# run.ps1 -- Start the Haven stack (database, cache, and server).
#
# USAGE (run from the repo root):
#   .\tools\win\run.ps1              # dev mode -- live-reload Go server
#   .\tools\win\run.ps1 -Fresh       # dev mode -- wipe DB first (resets Haven to UNCLAIMED for setup wizard)
#   .\tools\win\run.ps1 -Prod        # production mode (requires .env)
#   .\tools\win\run.ps1 -Detach      # start in background (combine with -Fresh or -Prod)
#   .\tools\win\run.ps1 -DbOnly      # postgres + redis only (run Go server locally)
#
# WHAT THIS DOES:
#   Development mode (default):
#     - Starts PostgreSQL 16, Redis 7, and Haven with live-reload (Air).
#     - Go source (src/) is bind-mounted -- edit .go files and the server
#       restarts automatically. No rebuild needed.
#     - Safe dev defaults apply when .env is missing (devpassword, zero-key JWT).
#     - Exposed ports:
#         http://localhost:8080  Haven API
#         localhost:5432         PostgreSQL
#         localhost:6379         Redis
#
#   -Fresh (Full reset to UNCLAIMED -- use this to test the setup wizard):
#     - Tears down the running stack and deletes the database + Redis volumes.
#     - On restart, Haven initialises from scratch in UNCLAIMED state.
#     - A new one-time setup code is printed to Haven's startup logs.
#     - To retrieve the code after starting detached:
#         docker compose -f docker-compose.dev.yml logs haven
#
#   -Dev -Fresh (one-liner for newcomers):
#     - Builds the dev Docker image, wipes DB, and starts the full stack.
#     - Everything you need from a fresh clone in one command.
#
#   -Prod (production mode):
#     - Uses docker-compose.yml (production image, no bind mounts, no dev defaults).
#     - Requires a .env file with real secrets. The server refuses to start without
#       HAVEN_JWT_SIGNING_KEY and HAVEN_DB_PASS.
#     - Copy .env.example to .env and fill in values before using this flag.
#
#   -DbOnly (infrastructure only):
#     - Starts postgres and redis -- but not Haven itself.
#     - In a separate terminal, run Go directly on the host:
#         cd src && go run ./cmd/server
#     - Useful for fast iteration without rebuilding/restarting the Go container.
#
# PREREQUISITES:
#   - Docker Desktop must be running.
#   - Production only: copy .env.example to .env and fill in secrets.

param(
    [switch]$Fresh,
    [switch]$Dev,
    [switch]$Prod,
    [switch]$Detach,
    [switch]$DbOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path (Join-Path $PSScriptRoot "..") "..")

# -- Helpers ------------------------------------------------------------------------------------------------------------------------------------

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "   $msg" -ForegroundColor Yellow }
function Write-Info($msg) { Write-Host "   $msg" -ForegroundColor DarkGray }

function Assert-Tool($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Error "'$name' is not installed or not in PATH. Please install it first."
    }
}

Assert-Tool "docker"

# -- Compose file ------------------------------------------------------------------------------------------------------------------------

$composeFile = if ($Prod) { "docker-compose.yml" } else { "docker-compose.dev.yml" }
$mode        = if ($Prod) { "production" } else { "development" }

# -- Production: require .env ------------------------------------------------------------------------------------------------

if ($Prod -and -not (Test-Path (Join-Path $RepoRoot ".env"))) {
    Write-Host ""
    Write-Host "!! No .env file found -- production mode requires real secrets." -ForegroundColor Red
    Write-Host "   Copy .env.example to .env, then fill in:" -ForegroundColor Yellow
    Write-Host "     HAVEN_JWT_SIGNING_KEY, HAVEN_DB_PASS" -ForegroundColor Yellow
    Write-Host ""
}

Push-Location $RepoRoot
try {
    # -- -Fresh: clean data and optionally rebuild ------------------------------------------------------

    if ($Fresh) {
        $cleanScript = Join-Path $PSScriptRoot "clean.ps1"

        # 1. Wipe containers + volumes so Haven resets to UNCLAIMED.
        Write-Step "Cleaning stale containers and data"
        & PowerShell -ExecutionPolicy Bypass -File $cleanScript -Data
        if ($LASTEXITCODE -ne 0) { Write-Error "Clean failed." }

        # 2. If -Dev was also passed, rebuild the dev Docker image.
        if ($Dev) {
            $buildScript = Join-Path $PSScriptRoot "build.ps1"
            Write-Step "Rebuilding development Docker image"
            & PowerShell -ExecutionPolicy Bypass -File $buildScript -Dev
            if ($LASTEXITCODE -ne 0) { Write-Error "Dev image build failed." }
        }

        Write-Warn "Haven will generate a new setup code on startup."
        Write-Warn "Watch for it in the logs -- it looks like:"
        Write-Warn "  ==========================================="
        Write-Warn "    HAVEN SETUP CODE (expires at 5:30 PM)"
        Write-Warn "               ABCD-EF7H"
        Write-Warn "  ==========================================="
        Write-Info "Use this code to complete the setup wizard."
    }

    # -- Build compose command --------------------------------------------------------------------------------------------

    $composeArgs = @("compose", "-f", $composeFile, "up")
    if ($Detach) { $composeArgs += "-d" }
    if ($DbOnly) { $composeArgs += @("postgres", "redis") }

    $label = $mode
    if ($DbOnly) { $label += " (infrastructure only -- Haven not started)" }
    if ($Fresh)  { $label += " [FRESH -- Haven is UNCLAIMED]" }

    Write-Step "Starting Haven -- $label"
    Write-Info "Compose file : $composeFile"
    Write-Info "Command      : docker $($composeArgs -join ' ')"

    if (-not $Prod) {
        Write-Host ""
        Write-Info "Endpoints:"
        if (-not $DbOnly) {
            Write-Info "  http://localhost:8080   Haven API"
        }
        Write-Info "  localhost:5432          PostgreSQL"
        Write-Info "  localhost:6379          Redis"
    }

    if ($DbOnly) {
        Write-Host ""
        Write-Warn "Haven is not started. Run it locally in another terminal:"
        Write-Info '  cd src'
        Write-Info '  $env:HAVEN_DB_URL    = "postgres://haven_user:devpass@localhost:5432/haven?sslmode=disable&search_path=haven"'
        Write-Info '  $env:HAVEN_REDIS_URL = "redis://localhost:6379"'
        Write-Info '  go run ./cmd/server'
    }

    if ($Fresh -and $Detach) {
        Write-Host ""
        Write-Warn "Stack started in background. To find your setup code:"
        Write-Info "  docker compose -f $composeFile logs haven"
    }

    Write-Host ""

    & docker @composeArgs

    # Exit code 130 (or similar) is normal when the user presses Ctrl+C.
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 130) {
        Write-Error "docker compose failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
