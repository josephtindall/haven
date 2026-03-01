# build.ps1 -- Build Haven Docker images and/or Go binaries.
#
# USAGE (run from the repo root):
#   .\tools\win\build.ps1              # build the production Docker image (default)
#   .\tools\win\build.ps1 -Dev         # build the development Docker image
#   .\tools\win\build.ps1 -Binary      # cross-compile Linux binaries into ./artifacts
#   .\tools\win\build.ps1 -All         # all of the above
#
# WHAT THIS DOES:
#   Default (no flags):
#     Builds the multi-stage production Docker image (haven:latest). The image
#     contains a single static Go binary and runs as an unprivileged user.
#     This is what you ship.
#
#   -Dev:
#     Builds the development Docker image (haven:dev). This image includes the
#     full Go toolchain and Air (live-reload). It is NOT meant for production --
#     only for local development.
#
#   -Binary:
#     Cross-compiles three static Linux binaries (haven, haven-cli, haven-migrate)
#     and places them in ./artifacts/. Useful for deploying without Docker or for
#     CI pipelines.
#
#   -All:
#     Runs all three build targets.
#
# PREREQUISITES:
#   Default/-Dev  requires: docker
#   -Binary       requires: go 1.23+

param(
    [switch]$Dev,
    [switch]$Binary,
    [switch]$All
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve repo root (two levels up from this script).
$RepoRoot     = Resolve-Path (Join-Path (Join-Path $PSScriptRoot "..") "..")
$ArtifactsDir = Join-Path $RepoRoot "artifacts"
$SrcDir       = Join-Path $RepoRoot "src"

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

# -- Decide what to build ------------------------------------------------------------------------------------------------------------

$buildProd   = (-not $Dev -and -not $Binary) -or $All
$buildDev    = $Dev -or $All
$buildBinary = $Binary -or $All

# -- Production Docker image ----------------------------------------------------------------------------------------------------

if ($buildProd) {
    Write-Step "Building production Docker image (haven:latest)"
    Assert-Tool "docker"

    docker build -f "$SrcDir/Dockerfile" -t haven:latest "$SrcDir"
    if ($LASTEXITCODE -ne 0) { Write-Error "Production Docker build failed." }

    Write-Ok "haven:latest built."
    Write-Info "Deploy with:  .\tools\win\run.ps1 -Prod"
    Write-Info "Push with:    .\tools\win\publish.ps1 -Registry ghcr.io/yourname"
}

# -- Development Docker image --------------------------------------------------------------------------------------------------

if ($buildDev) {
    Write-Step "Building development Docker image (haven:dev)"
    Assert-Tool "docker"

    docker build -f "$SrcDir/Dockerfile.dev" -t haven:dev "$SrcDir"
    if ($LASTEXITCODE -ne 0) { Write-Error "Development Docker build failed." }

    Write-Ok "haven:dev built."
    Write-Info "Start dev stack with:  .\tools\win\run.ps1"
}

# -- Static Linux binaries --------------------------------------------------------------------------------------------------------

if ($buildBinary) {
    Write-Step "Cross-compiling static Linux binaries into ./artifacts"
    Assert-Tool "go"

    if (-not (Test-Path $ArtifactsDir)) { New-Item -ItemType Directory -Path $ArtifactsDir | Out-Null }

    $env:CGO_ENABLED = "0"
    $env:GOOS        = "linux"
    $env:GOARCH      = "amd64"

    $binaries = @(
        @{ Name = "haven";         Pkg = "./cmd/server"  }
        @{ Name = "haven-cli";     Pkg = "./cmd/cli"     }
        @{ Name = "haven-migrate"; Pkg = "./cmd/migrate"  }
    )

    Push-Location $SrcDir
    try {
        foreach ($bin in $binaries) {
            $outPath = Join-Path $ArtifactsDir $bin.Name
            Write-Info "Compiling $($bin.Name) -> artifacts/$($bin.Name)"
            go build -trimpath -o $outPath $bin.Pkg
            if ($LASTEXITCODE -ne 0) { Write-Error "Failed to build $($bin.Name)." }
        }
    }
    finally {
        Pop-Location
        Remove-Item Env:CGO_ENABLED -ErrorAction SilentlyContinue
        Remove-Item Env:GOOS        -ErrorAction SilentlyContinue
        Remove-Item Env:GOARCH      -ErrorAction SilentlyContinue
    }

    Write-Ok "Binaries written to ./artifacts/"
    Write-Info "These are static linux/amd64 binaries -- deploy them directly or copy into a container."
}

# -- Summary ------------------------------------------------------------------------------------------------------------------------------------

Write-Host "`nBuild complete.`n" -ForegroundColor Green
