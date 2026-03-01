# Haven — Windows Scripts Guide

These scripts let you build, run, clean up, and publish Haven without memorizing Docker or Go commands. Each one prints what it's doing as it goes, so you can follow along.

---

## Before You Start

You need two things installed:

1. **Docker Desktop** — download from [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/). After installing, open it and wait until the whale icon in your system tray says "running".

2. **PowerShell 7** — you probably already have this. Open a terminal and type `pwsh`. If it opens, you're good. If not, install it from [the PowerShell GitHub releases page](https://github.com/PowerShell/PowerShell/releases).

All commands below are typed into PowerShell and run **from the project root folder** (the `haven` folder — the one that contains `src/`, `tools/`, and `CLAUDE.md`).

```powershell
cd C:\Projects\haven
```

---

## Running Haven (the most common thing you'll do)

Start everything in development mode — the database, cache, and server all come up together:

```powershell
.\tools\win\run.ps1
```

Once you see log output from the server, Haven is running at **http://localhost:8080**.

To stop it, press **Ctrl+C** in the same terminal.

### First time? Use -Dev -Fresh

If you just cloned the repo and want everything built and running in one command:

```powershell
.\tools\win\run.ps1 -Dev -Fresh
```

This builds the dev Docker image, wipes any old data, and starts the full stack from scratch. Haven will print a setup code to the console — use it to complete the setup wizard.

### Other ways to run

```powershell
# Wipe the database and start fresh (resets Haven to UNCLAIMED for the setup wizard)
.\tools\win\run.ps1 -Fresh

# Run in the background (terminal stays free, containers keep running)
.\tools\win\run.ps1 -Detach

# Run only the database and cache (if you want to run the Go server yourself)
.\tools\win\run.ps1 -DbOnly

# Run in production mode (requires a .env file with real secrets — see below)
.\tools\win\run.ps1 -Prod
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

3. Paste the output into your `.env` file. Open it with any text editor — Notepad works fine.

The `.env` file is private to your machine and is never committed to git.

---

## Building

Build the Docker image that you'd ship to a server:

```powershell
.\tools\win\build.ps1
```

That's it. Docker does everything — you don't need Go installed locally.

### Other build options

```powershell
# Build the development image (used by run.ps1 automatically — you rarely need this)
.\tools\win\build.ps1 -Dev

# Build standalone Linux binaries and put them in the artifacts/ folder
.\tools\win\build.ps1 -Binary

# Build everything at once
.\tools\win\build.ps1 -All
```

---

## Cleaning Up

Remove containers and build files:

```powershell
.\tools\win\clean.ps1
```

This stops Haven and deletes temporary files but **keeps your database data**.

### Other clean options

```powershell
# Preview what would be deleted without actually deleting anything
.\tools\win\clean.ps1 -WhatIf

# Also wipe the database (you'll need to set up Haven from scratch after this)
.\tools\win\clean.ps1 -Data

# Also remove Docker images (the next build will take longer)
.\tools\win\clean.ps1 -Images

# Remove everything — containers, data, images, artifacts
.\tools\win\clean.ps1 -Full
```

---

## Publishing (pushing to a server)

This builds the production image and pushes it to a container registry. You need a registry account (like GitHub Container Registry or Docker Hub) and must be logged in first:

```powershell
docker login ghcr.io
```

Then push:

```powershell
.\tools\win\publish.ps1 -Registry ghcr.io/yourusername -Tag v1.0.0
```

### Other publish options

```powershell
# Push without rebuilding (if you already ran build.ps1)
.\tools\win\publish.ps1 -Registry ghcr.io/yourusername -SkipBuild

# Push and also save the binary to artifacts/ for a GitHub release
.\tools\win\publish.ps1 -Registry ghcr.io/yourusername -WithBinaries
```

---

## Quick Reference

| I want to...                  | Command                                |
|-------------------------------|----------------------------------------|
| Start Haven (first time)      | `.\tools\win\run.ps1 -Dev -Fresh`      |
| Start Haven                   | `.\tools\win\run.ps1`                  |
| Reset and start fresh         | `.\tools\win\run.ps1 -Fresh`           |
| Stop Haven                    | Ctrl+C (or `.\tools\win\clean.ps1`)    |
| Build the Docker image        | `.\tools\win\build.ps1`                |
| Delete everything and restart | `.\tools\win\clean.ps1 -Full`          |
| See what clean would delete   | `.\tools\win\clean.ps1 -WhatIf`        |
| Push image to a registry      | `.\tools\win\publish.ps1 -Registry …`  |

---

## Something Went Wrong?

| Problem | Fix |
|---------|-----|
| "docker: command not found" | Open Docker Desktop and wait for it to finish starting. |
| "'pwsh' is not recognized" | Install PowerShell 7 (link above). |
| "port 5432 already in use" | Another Postgres is running. Stop it, or run `.\tools\win\clean.ps1` first. |
| "permission denied" | Right-click your terminal and choose "Run as Administrator". |
| Build seems stuck downloading | First build pulls base images (~300 MB). Subsequent builds are fast. |
| Want to start fresh | `.\tools\win\run.ps1 -Dev -Fresh` |
| Can't find the setup code | `docker compose -f docker-compose.dev.yml logs haven` |
