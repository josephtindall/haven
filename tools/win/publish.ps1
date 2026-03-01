# publish.ps1 -- Build, tag, and push the Haven Docker image to a container registry.
#
# USAGE (run from the repo root):
#   .\tools\win\publish.ps1 -Registry ghcr.io/yourname                 # push as latest
#   .\tools\win\publish.ps1 -Registry ghcr.io/yourname -Tag v1.0.0     # push as v1.0.0 + latest
#   .\tools\win\publish.ps1 -Registry ghcr.io/yourname -SkipBuild      # push existing image
#   .\tools\win\publish.ps1 -Registry ghcr.io/yourname -WithBinaries   # also export binaries
#
# WHAT THIS DOES:
#   1. Builds the production Docker image (haven:latest) unless -SkipBuild is set.
#   2. Tags it as <registry>/haven:<tag> (default tag: "latest").
#   3. If a specific -Tag is given (e.g. v1.0.0), also tags and pushes as "latest".
#   4. Pushes the tagged image to the registry.
#   5. With -WithBinaries: also copies the static server binary from the image
#      into ./artifacts/ so it can be attached to a GitHub release.
#
# PREREQUISITES:
#   - Docker Desktop must be running.
#   - You must be logged in to your registry:
#       docker login ghcr.io          # GitHub Container Registry
#       docker login                  # Docker Hub
#
# EXAMPLES:
#   # Push to GitHub Container Registry with a version tag
#   .\tools\win\publish.ps1 -Registry ghcr.io/josephtindall -Tag v1.0.0
#
#   # Push to Docker Hub
#   .\tools\win\publish.ps1 -Registry docker.io/josephtindall -Tag v1.0.0
#
#   # Full release: build everything, push image, export binary for GitHub release
#   .\tools\win\build.ps1 -All
#   .\tools\win\publish.ps1 -Registry ghcr.io/josephtindall -Tag v1.0.0 -WithBinaries

param(
    [Parameter(Mandatory = $true)]
    [string]$Registry,

    [string]$Tag = "latest",

    [switch]$SkipBuild,
    [switch]$WithBinaries
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot     = Resolve-Path (Join-Path (Join-Path $PSScriptRoot "..") "..")
$SrcDir       = Join-Path $RepoRoot "src"
$ArtifactsDir = Join-Path $RepoRoot "artifacts"

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

# Normalise registry -- strip trailing slash.
$Registry  = $Registry.TrimEnd("/")
$FullTag   = "$Registry/haven:$Tag"
$LatestTag = "$Registry/haven:latest"

# -- Build ------------------------------------------------------------------------------------------------------------------------------------

if (-not $SkipBuild) {
    Write-Step "Building production Docker image (haven:latest)"

    docker build -f "$SrcDir/Dockerfile" -t haven:latest "$SrcDir"
    if ($LASTEXITCODE -ne 0) { Write-Error "Docker build failed." }

    Write-Ok "haven:latest built."
}
else {
    # Verify the image actually exists before trying to tag/push.
    $imageId = docker images -q haven:latest 2>$null
    if (-not $imageId) {
        Write-Error "haven:latest not found. Run '.\tools\win\build.ps1' first, or remove -SkipBuild."
    }
    Write-Info "Using existing haven:latest image."
}

# -- Tag ----------------------------------------------------------------------------------------------------------------------------------------

Write-Step "Tagging image"

docker tag haven:latest $FullTag
if ($LASTEXITCODE -ne 0) { Write-Error "docker tag failed." }
Write-Ok "Tagged as $FullTag"

# When a specific version is given, also push as "latest" for convenience.
$pushLatest = $Tag -ne "latest"
if ($pushLatest) {
    docker tag haven:latest $LatestTag
    if ($LASTEXITCODE -ne 0) { Write-Error "docker tag (latest) failed." }
    Write-Ok "Tagged as $LatestTag"
}

# -- Push --------------------------------------------------------------------------------------------------------------------------------------

Write-Step "Pushing to $Registry"

docker push $FullTag
if ($LASTEXITCODE -ne 0) {
    $host_ = $Registry.Split("/")[0]
    Write-Error "Push failed. Are you logged in? Try: docker login $host_"
}
Write-Ok "Pushed $FullTag"

if ($pushLatest) {
    docker push $LatestTag
    if ($LASTEXITCODE -ne 0) { Write-Error "Push of latest tag failed." }
    Write-Ok "Pushed $LatestTag"
}

# -- Extract binaries (optional) ----------------------------------------------------------------------------------------

if ($WithBinaries) {
    Write-Step "Extracting server binary from image into ./artifacts/"

    if (-not (Test-Path $ArtifactsDir)) { New-Item -ItemType Directory -Path $ArtifactsDir | Out-Null }

    # Create a temporary container from the image to copy files out.
    Write-Info "Extracting Go binary from image..."
    $container = & docker create haven:latest
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create temporary container." }

    try {
        docker cp "${container}:/app/haven" (Join-Path $ArtifactsDir "haven")
        if ($LASTEXITCODE -ne 0) { Write-Error "Failed to extract binary from container." }
        Write-Ok "artifacts/haven  (static linux/amd64 Go binary)"
    }
    finally {
        docker rm $container | Out-Null
    }

    Write-Host ""
    Write-Info "Release assets:"
    Write-Info "  artifacts/haven  -- attach to GitHub release as a Linux binary"
}

# -- Summary --------------------------------------------------------------------------------------------------------------------------------

Write-Host "`nPublish complete." -ForegroundColor Green
Write-Info "Image : $FullTag"
if ($pushLatest)   { Write-Info "Image : $LatestTag" }
if ($WithBinaries) { Write-Info "Assets: artifacts/" }
Write-Host ""
Write-Host "Next steps:" -ForegroundColor DarkGray
Write-Info "  Update the haven image reference in docker-compose.yml, then:"
Write-Info "  docker compose pull && docker compose up -d"
Write-Host ""
