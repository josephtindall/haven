# Haven — Identity & Access Management

## What This Repo Is

Haven is a standalone IAM sidecar service distributed as a Docker image. It provides authentication, session management, device tracking, RBAC enforcement, and a complete audit log for any project that consumes it. Luma is the first consumer — future projects add one block to their `docker-compose.yml` and get full IAM.

**Haven owns identity. It never owns content.**

## Design Document

Read this before writing any code:

- `docs/haven-design.md` — complete specification: bootstrap state machine, database schema, security requirements, API surface, audit events, definition of done
- `docs/rbac-design.md` — Permission model, action taxonomy, authz API calls

## Repository Structure

```
haven/                       # repo root — GitHub files and docs only
  docs/
    haven-design.md          # complete spec (read before writing code)
    rbac-design.md
    testing-guide.md
  .env.example               # copy to .env and fill in secrets
  CLAUDE.md
  README.md
  src/                       # all source code lives here
    cmd/
      server/
        main.go              # wire deps, start server — zero business logic
      cli/
        main.go              # haven-cli entrypoint
    internal/
      bootstrap/
        state.go             # UNCLAIMED | SETUP | ACTIVE state machine
        middleware.go        # BootstrapGate — enforced on every request
        handler.go           # setup wizard API handlers
      user/
        model.go             # User, Role — pure structs
        service.go           # business logic
        repository.go        # UserRepository interface
        handler.go           # HTTP handlers
        postgres/
          repository.go      # implements UserRepository
      device/
        model.go, service.go, repository.go, handler.go
        postgres/repository.go
      session/
        model.go, service.go, repository.go, handler.go
        postgres/repository.go
      audit/
        model.go             # AuditEvent
        service.go           # async write queue — never blocks request path
        repository.go        # AuditRepository interface (INSERT only)
        postgres/
          repository.go
      authz/
        authorizer.go        # evaluates all four permission dimensions
        handler.go           # POST /api/haven/authz/check
      invitation/
        model.go, service.go, repository.go, handler.go
        postgres/repository.go
      preferences/
        model.go, service.go, repository.go, handler.go
        postgres/repository.go
      integration/           # integration tests (require real PostgreSQL)
    pkg/
      crypto/
        argon2.go            # HashPassword(), VerifyPassword() — Argon2id ONLY
      token/
        jwt.go               # JWT generation and validation
        refresh.go           # refresh token generation, hashing, rotation
      middleware/
        auth.go              # Bearer token validation on protected routes
        ratelimit.go         # per-IP rate limiting on login/register
        requestid.go
        logger.go
      config/
        config.go            # all config loaded and validated at startup
      errors/
        errors.go            # sentinel errors + HTTP error response helpers
      shortid/
        shortid.go           # not used by Haven directly — included for Luma consumers
    migrations/
      0001_core_tables.sql
      0002_user_preferences.sql
      0003_rbac_tables.sql
      0004_invitations.sql
    docker-compose.yml
    docker-compose.dev.yml
    Dockerfile
    go.mod
    go.sum
```

## Technology Stack

- **Language:** Go 1.23+
- **Database:** PostgreSQL 16 — schema: `haven`
- **Cache:** Redis — rate limiting, permission cache (5-min TTL)
- **Proxy:** Caddy — TLS termination (in the consuming project's compose file)

## Go Architecture Rules — Non-Negotiable

**Structure:**
- `cmd/server/main.go` wires dependencies and starts the server — zero business logic here
- Business logic lives exclusively in `internal/{feature}/service.go`
- Handlers parse requests, call service methods, write responses — nothing else
- `pkg/` contains reusable code with no internal imports

**Dependency Injection:**
- Constructor injection via `New()` functions everywhere
- No global variables, no `init()` doing meaningful work
- Concrete implementations wired only in `cmd/server/main.go`
- Service layer imports interfaces, never concrete types

**Interfaces:**
- Every dependency that crosses a package boundary crosses through an interface
- Repository interfaces defined in the feature package, implementations in `postgres/`

**Errors:**
- Always returned, never swallowed, never panicked in business logic
- Always wrapped: `fmt.Errorf("context: %w", err)`
- Sentinel errors in `pkg/errors/errors.go`
- `panic()` only for fatal startup configuration failures

**Context:**
- `context.Context` is always the first parameter of any DB/network/filesystem function
- Never stored in a struct

**Configuration:**
- All config loaded and validated at startup via `pkg/config/config.go`
- Missing or invalid security config (JWT key, DB password) is a fatal startup error
- No silent defaults for security-relevant values

## Security Rules — Absolute

These are not guidelines. Any deviation is a bug.

- **Passwords:** Argon2id only — `golang.org/x/crypto/argon2`. Parameters: time=3, memory=65536KB, parallelism=2, saltLen=32, keyLen=32. Target ~250ms. PHC string format. Never bcrypt, never SHA-256, never MD5.
- **JWT:** HMAC-SHA256, 15-minute access token lifetime exactly. Payload: `sub`, `did`, `role`, `iat`, `exp`, `jti` only. 512-bit signing key from environment — fatal error if missing.
- **Refresh tokens:** 32 random bytes, base64url encoded. Store SHA-256 hash ONLY — the raw token is never written to the database anywhere.
- **Login errors:** NEVER distinguish "email not found" from "wrong password". Both return `INVALID_CREDENTIALS`. No exceptions.
- **Token reuse:** If a consumed refresh token is presented again, revoke ALL sessions for that user immediately and write a `token_reuse_detected` audit event.
- **Audit log:** The database user has INSERT + SELECT only on `haven.audit_log`. No UPDATE, no DELETE, ever. Verified in migration.
- **Transport:** TLS 1.3 minimum. HTTP rejected at gateway — no redirect.
- **Web cookies:** HttpOnly, Secure, SameSite=Strict, Path=/api/haven/refresh only.

## Bootstrap State Machine

The server enforces three states at three independent layers (DB column, middleware, handler). All three must pass — passing any single layer is not sufficient.

```
UNCLAIMED → (valid setup token) → SETUP → (owner created atomically) → ACTIVE
SETUP → (30 min timeout) → UNCLAIMED
```

ACTIVE is permanent via API. Factory reset requires: `haven-cli factory-reset --confirm-destroy-all-data`

In `UNCLAIMED`: only `GET /` and `POST /api/setup/verify-token` are accessible. Everything else: 503.
In `SETUP`: only `GET /` and `POST /api/setup/*` are accessible. Everything else: 503.
In `ACTIVE`: `POST /api/setup/*` returns 410 Gone permanently.

## Sentinel Errors (pkg/errors/errors.go)

```go
ErrInvalidCredentials   // 401 — used for both wrong password AND unknown email
ErrAccountLocked        // 403
ErrTokenExpired         // 401
ErrTokenInvalid         // 401
ErrTokenRevoked         // 401
ErrTokenReuseDetected   // 401 — triggers full session revocation
ErrUserNotFound         // 404
ErrEmailTaken           // 409
ErrPasswordTooShort     // 422
ErrDeviceNotFound       // 404
ErrDeviceRevoked        // 403
ErrForbidden            // 403
ErrSetupRequired        // 503
ErrSetupComplete        // 410
```

## Database Conventions

- All tables in the `haven` schema — the DB user has access only to this schema
- UUIDs for all primary keys: `gen_random_uuid()`
- All timestamps: `TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- Migrations numbered sequentially: `0001_description.sql`
- Run migrations at startup before the server accepts connections
- Never alter tables manually — always write a migration

## Commands

All Go and Docker commands are run from the `src/` directory unless noted.

```bash
# Load dev environment (PowerShell — run from repo root)
. .\src\dev.ps1

# Start full stack (postgres + redis + haven) — from repo root
docker compose -f src/docker-compose.yml up

# Start for development (with live reload) — from repo root
docker compose -f src/docker-compose.dev.yml up

# All commands below are run from src/

# Run tests (always use race detector)
go test -race ./...

# Run tests for a specific package
go test -race ./internal/user/...

# Run integration tests (requires PostgreSQL)
HAVEN_TEST_DB_URL=postgres://... go test -race -v ./internal/integration/

# Apply migrations
go run ./cmd/migrate up

# Rollback last migration
go run ./cmd/migrate down

# Generate secrets for .env
go run ./cmd/cli generate-secrets

# Validate config
go run ./cmd/cli validate-config --env-file ../.env

# Build Docker image — from repo root
docker build -f src/Dockerfile -t haven:dev src/

# Lint
golangci-lint run ./...
```

## Definition of Done — v1.0

Do not consider Haven complete until ALL of the following are simultaneously true:

1. All unit tests pass with `-race` flag, zero skips
2. All integration tests pass against real PostgreSQL (not mocks)
3. Both household users register and log in from web browser on LAN
4. Both users log in from iOS with refresh token in Keychain
5. Both users log in from Android with refresh token in EncryptedSharedPreferences
6. Device list accurate after multi-platform login
7. Remote device revocation propagates within 15 minutes
8. Token reuse detection triggers full session revocation (verified manually)
9. Brute force lockout tested manually (10 attempts → locked)
10. Audit log INSERT-only constraint verified at DB level
11. Luma successfully calls `/api/haven/validate` and `/api/haven/authz/check`
12. Both users in daily use for 7 consecutive days before Luma feature work begins
