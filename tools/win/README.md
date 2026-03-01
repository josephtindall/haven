# Haven -- Windows Scripts Guide

These scripts let you build, run, clean up, and publish Haven without memorizing Docker or Go commands. Each one prints what it's doing as it goes, so you can follow along.

---

## Quick Start

Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) and make sure it's running. Then open a terminal, navigate to the project root, and run:

```powershell
cd C:\Projects\haven
PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1 -Dev -Fresh
```

That's it. This builds the dev Docker image, creates a fresh database, and starts the full stack. Haven will print a setup code to the console -- use it to complete the setup wizard.

Once you're up and running, drop the flags you no longer need:

1. **Day-to-day development** -- remove `-Fresh` so you keep your data between restarts:
   ```powershell
   PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1 -Dev
   ```

2. **After setting up `.env` with real secrets** -- remove `-Dev` too, since the image is already built:
   ```powershell
   PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1
   ```

Haven is running at **http://localhost:8080**. Press **Ctrl+C** to stop it.

---

## Before You Start

You need two things installed:

1. **Docker Desktop** -- download from [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/). After installing, open it and wait until the whale icon in your system tray says "running".

2. **PowerShell** -- you already have this on Windows. All commands in this guide use `PowerShell -ExecutionPolicy Bypass -File` so they work out of the box without changing your system policy.

All commands below are run **from the project root folder** (the `haven` folder -- the one that contains `src/`, `tools/`, and `CLAUDE.md`).

```powershell
cd C:\Projects\haven
```

---

## Running Haven

Start everything in development mode -- the database, cache, and server all come up together:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1
```

### Other ways to run

```powershell
# Build the dev image + wipe DB + start (first time or full reset)
PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1 -Dev -Fresh

# Wipe the database and start fresh (resets Haven to UNCLAIMED for the setup wizard)
PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1 -Fresh

# Run in the background (terminal stays free, containers keep running)
PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1 -Detach

# Run only the database and cache (if you want to run the Go server yourself)
PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1 -DbOnly

# Run in production mode (requires a .env file with real secrets -- see below)
PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1 -Prod
```

When using `-Fresh -Detach`, the setup code is in the container logs:

```powershell
docker compose -f docker-compose.dev.yml logs haven
```

---

## Setting Up Secrets (only needed once)

Haven needs a few secret values to run in production mode. Development mode fills these in automatically, so you can skip this section if you're just experimenting.

1. Copy the example file:
   ```powershell
   Copy-Item .env.example .env
   ```

2. Generate real secrets:
   ```powershell
   cd src
   go run ./cmd/cli generate-secrets
   cd ..
   ```

3. Paste the output into your `.env` file. Open it with any text editor -- Notepad works fine.

The `.env` file is private to your machine and is never committed to git.

---

## Building

Build the Docker image that you'd ship to a server:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\tools\win\build.ps1
```

That's it. Docker does everything -- you don't need Go installed locally.

### Other build options

```powershell
# Build the development image (used by run.ps1 -Dev automatically -- you rarely need this)
PowerShell -ExecutionPolicy Bypass -File .\tools\win\build.ps1 -Dev

# Build standalone Linux binaries and put them in the artifacts/ folder
PowerShell -ExecutionPolicy Bypass -File .\tools\win\build.ps1 -Binary

# Build everything at once
PowerShell -ExecutionPolicy Bypass -File .\tools\win\build.ps1 -All
```

---

## Cleaning Up

Remove containers and build files:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\tools\win\clean.ps1
```

This stops Haven and deletes temporary files but **keeps your database data**.

### Other clean options

```powershell
# Preview what would be deleted without actually deleting anything
PowerShell -ExecutionPolicy Bypass -File .\tools\win\clean.ps1 -WhatIf

# Also wipe the database (you'll need to set up Haven from scratch after this)
PowerShell -ExecutionPolicy Bypass -File .\tools\win\clean.ps1 -Data

# Also remove Docker images (the next build will take longer)
PowerShell -ExecutionPolicy Bypass -File .\tools\win\clean.ps1 -Images

# Remove everything -- containers, data, images, artifacts
PowerShell -ExecutionPolicy Bypass -File .\tools\win\clean.ps1 -Full
```

---

## Publishing (pushing to a server)

This builds the production image and pushes it to a container registry. You need a registry account (like GitHub Container Registry or Docker Hub) and must be logged in first:

```powershell
docker login ghcr.io
```

Then push:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\tools\win\publish.ps1 -Registry ghcr.io/yourusername -Tag v1.0.0
```

### Other publish options

```powershell
# Push without rebuilding (if you already ran build.ps1)
PowerShell -ExecutionPolicy Bypass -File .\tools\win\publish.ps1 -Registry ghcr.io/yourusername -SkipBuild

# Push and also save the binary to artifacts/ for a GitHub release
PowerShell -ExecutionPolicy Bypass -File .\tools\win\publish.ps1 -Registry ghcr.io/yourusername -WithBinaries
```

---

## Quick Reference

| I want to...                  | Command |
|-------------------------------|---------|
| Start Haven (first time)      | `PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1 -Dev -Fresh` |
| Start Haven                   | `PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1` |
| Reset and start fresh         | `PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1 -Fresh` |
| Stop Haven                    | Ctrl+C in the terminal |
| Build the Docker image        | `PowerShell -ExecutionPolicy Bypass -File .\tools\win\build.ps1` |
| Delete everything and restart | `PowerShell -ExecutionPolicy Bypass -File .\tools\win\clean.ps1 -Full` |
| See what clean would delete   | `PowerShell -ExecutionPolicy Bypass -File .\tools\win\clean.ps1 -WhatIf` |

---

## Something Went Wrong?

| Problem | Fix |
|---------|-----|
| "docker: command not found" | Open Docker Desktop and wait for it to finish starting. |
| "port 5432 already in use" | Another Postgres is running. Stop it, or run `clean.ps1` first. |
| "permission denied" | Right-click your terminal and choose "Run as Administrator". |
| Build seems stuck downloading | First build pulls base images (~300 MB). Subsequent builds are fast. |
| Want to start completely fresh | `PowerShell -ExecutionPolicy Bypass -File .\tools\win\run.ps1 -Dev -Fresh` |
| Can't find the setup code | `docker compose -f docker-compose.dev.yml logs haven` |
