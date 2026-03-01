# clean.ps1 — Remove Haven build artifacts, containers, and volumes.
#
# USAGE (run from the repo root):
#   .\tools\win\clean.ps1              # stop containers, remove artifacts
#   .\tools\win\clean.ps1 -Data        # also delete database and redis volumes
#   .\tools\win\clean.ps1 -Images      # also remove haven Docker images
#   .\tools\win\clean.ps1 -Full        # all of the above (nuclear option)
#   .\tools\win\clean.ps1 -DryRun      # preview what would be deleted
#
# WHAT THIS DOES:
#   Default (no flags):
#     - Stops and removes all Haven containers (docker compose down).
#     - Deletes the ./artifacts directory (cross-compiled binaries).
#     - Clears the Air live-reload temp directory (src/tmp/).
#
#   -Data:
#     - Everything above, PLUS deletes Docker volumes (PostgreSQL data, Redis
#       data, Go module cache). This destroys your local database — you will
#       need to re-run bootstrap after starting again.
#
#   -Images:
#     - Everything in default, PLUS removes the haven:latest and haven:dev
#       Docker images. The next build will pull base images fresh.
#
#   -Full:
#     - Combines -Data and -Images. Brings the project back to a clean slate.
#       You will need to rebuild and re-bootstrap after this.
#
# NOTE: This script never touches your .env file or source code.

param(
    [switch]$Data,
    [switch]$Images,
    [switch]$Full,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot ".." "..")
$ArtifactsDir = Join-Path $RepoRoot "artifacts"
$AirTmpDir    = Join-Path $RepoRoot "src" "tmp"

$removeData   = $Data -or $Full
$removeImages = $Images -or $Full

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "   $msg (skipped — not found)" -ForegroundColor DarkGray }

# ── Stop containers ──────────────────────────────────────────────────────────

Write-Step "Stopping Haven containers"

Push-Location $RepoRoot
try {
    foreach ($file in @("docker-compose.dev.yml", "docker-compose.yml")) {
        if (Test-Path (Join-Path $RepoRoot $file)) {
            $downArgs = @("compose", "-f", $file, "down")
            if ($removeData) { $downArgs += "-v" }

            if ($DryRun) {
                Write-Host "   [DryRun] docker $($downArgs -join ' ')" -ForegroundColor Yellow
            } else {
                & docker @downArgs 2>$null
                Write-Ok "Stopped containers from $file$(if ($removeData) { ' (volumes removed)' })"
            }
        }
    }
}
finally {
    Pop-Location
}

# ── Remove build artifacts ───────────────────────────────────────────────────

Write-Step "Removing build artifacts"

if (Test-Path $ArtifactsDir) {
    if ($DryRun) {
        Write-Host "   [DryRun] Remove $ArtifactsDir" -ForegroundColor Yellow
    } else {
        Remove-Item -Recurse -Force $ArtifactsDir
        Write-Ok "Deleted ./artifacts/"
    }
} else {
    Write-Skip "./artifacts/"
}

if (Test-Path $AirTmpDir) {
    if ($DryRun) {
        Write-Host "   [DryRun] Remove $AirTmpDir" -ForegroundColor Yellow
    } else {
        Remove-Item -Recurse -Force $AirTmpDir
        Write-Ok "Deleted src/tmp/ (Air live-reload cache)"
    }
} else {
    Write-Skip "src/tmp/"
}

# ── Remove Docker images ────────────────────────────────────────────────────

if ($removeImages) {
    Write-Step "Removing Haven Docker images"

    foreach ($tag in @("haven:latest", "haven:dev")) {
        $exists = docker images -q $tag 2>$null
        if ($exists) {
            if ($DryRun) {
                Write-Host "   [DryRun] docker rmi $tag" -ForegroundColor Yellow
            } else {
                docker rmi $tag 2>$null
                Write-Ok "Removed image $tag"
            }
        } else {
            Write-Skip $tag
        }
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete — nothing was deleted." -ForegroundColor Yellow
} else {
    Write-Host "Clean complete." -ForegroundColor Green
    if ($removeData) {
        Write-Host "   Database volumes were deleted. You will need to re-bootstrap after starting." -ForegroundColor Yellow
    }
}
Write-Host ""
