# publish.ps1 — Build, tag, and push the Haven Docker image to a container registry.
#
# USAGE (run from the repo root):
#   .\tools\win\publish.ps1 -Registry ghcr.io/yourname                 # tag as latest
#   .\tools\win\publish.ps1 -Registry ghcr.io/yourname -Tag v1.0.0     # tag as v1.0.0
#   .\tools\win\publish.ps1 -Registry ghcr.io/yourname -SkipBuild      # push existing image
#   .\tools\win\publish.ps1 -Registry ghcr.io/yourname -WithBinaries   # also export binaries
#
# WHAT THIS DOES:
#   1. Builds the production Docker image (haven:latest) unless -SkipBuild is set.
#   2. Tags it as <registry>/haven:<tag> (default tag: "latest").
#   3. Pushes the tagged image to the registry.
#   4. Optionally (-WithBinaries) copies the static binaries from the image
#      into ./artifacts/ so they can be attached to a GitHub release.
#
# PREREQUISITES:
#   - Docker Desktop must be running.
#   - You must be logged in to your registry:
#       docker login ghcr.io          # GitHub Container Registry
#       docker login                  # Docker Hub
#
# EXAMPLES:
#   # Push to GitHub Container Registry
#   .\tools\win\publish.ps1 -Registry ghcr.io/josephtindall -Tag v1.0.0
#
#   # Push to Docker Hub
#   .\tools\win\publish.ps1 -Registry docker.io/josephtindall -Tag v1.0.0
#
#   # Push latest + extract binaries for a GitHub release
#   .\tools\win\publish.ps1 -Registry ghcr.io/josephtindall -WithBinaries

param(
    [Parameter(Mandatory = $true)]
    [string]$Registry,

    [string]$Tag = "latest",

    [switch]$SkipBuild,
    [switch]$WithBinaries
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot ".." "..")
$SrcDir = Join-Path $RepoRoot "src"
$ArtifactsDir = Join-Path $RepoRoot "artifacts"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   $msg" -ForegroundColor Green }

function Assert-Tool($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Error "'$name' is not installed or not in PATH. Please install it first."
    }
}

Assert-Tool "docker"

# Normalize registry — strip trailing slash.
$Registry = $Registry.TrimEnd("/")
$FullTag = "$Registry/haven:$Tag"

# ── Build ────────────────────────────────────────────────────────────────────

if (-not $SkipBuild) {
    Write-Step "Building production Docker image"
    docker build -f "$SrcDir/Dockerfile" -t haven:latest "$SrcDir"
    if ($LASTEXITCODE -ne 0) { Write-Error "Docker build failed." }
    Write-Ok "haven:latest built."
}

# ── Tag ──────────────────────────────────────────────────────────────────────

Write-Step "Tagging image as $FullTag"
docker tag haven:latest $FullTag
if ($LASTEXITCODE -ne 0) { Write-Error "Docker tag failed." }
Write-Ok "Tagged."

# Also tag as latest if a specific version was given.
if ($Tag -ne "latest") {
    $LatestTag = "$Registry/haven:latest"
    docker tag haven:latest $LatestTag
    Write-Ok "Also tagged as $LatestTag"
}

# ── Push ─────────────────────────────────────────────────────────────────────

Write-Step "Pushing to $Registry"
docker push $FullTag
if ($LASTEXITCODE -ne 0) { Write-Error "Docker push failed. Are you logged in? Try: docker login $($Registry.Split('/')[0])" }
Write-Ok "Pushed $FullTag"

if ($Tag -ne "latest") {
    docker push $LatestTag
    if ($LASTEXITCODE -ne 0) { Write-Error "Push of latest tag failed." }
    Write-Ok "Pushed $LatestTag"
}

# ── Extract binaries (optional) ─────────────────────────────────────────────

if ($WithBinaries) {
    Write-Step "Extracting server binary from image into ./artifacts/"

    if (-not (Test-Path $ArtifactsDir)) { New-Item -ItemType Directory -Path $ArtifactsDir | Out-Null }

    # Create a temporary container from the image to copy files out.
    $container = docker create haven:latest
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create temporary container." }

    try {
        docker cp "${container}:/app/haven" "$ArtifactsDir/haven"
        Write-Ok "Extracted haven -> artifacts/haven"
    }
    finally {
        docker rm $container | Out-Null
    }

    Write-Host "   Attach these binaries to your GitHub release." -ForegroundColor DarkGray
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host "`nPublish complete." -ForegroundColor Green
Write-Host "   Image: $FullTag" -ForegroundColor DarkGray
if ($WithBinaries) {
    Write-Host "   Binaries: ./artifacts/" -ForegroundColor DarkGray
}
Write-Host ""
