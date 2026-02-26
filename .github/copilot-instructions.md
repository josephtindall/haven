# GitHub Copilot Instructions — Haven

Haven is a self-hosted IAM sidecar written in Go. It handles authentication, session management, device tracking, RBAC enforcement, and audit logging for any project that consumes it via HTTP. The design is intentional and opinionated — review every change against the rules below.

---

## Architecture

**Layer boundaries are strict. Flag any violation.**

- `cmd/server/main.go` wires dependencies and starts the server. Zero business logic belongs here.
- Business logic lives exclusively in `internal/{feature}/service.go`.
- Handlers parse requests, call one or more service methods, and write responses. Nothing else.
- `pkg/` contains reusable code with no imports from `internal/`.

**Dependency injection is constructor-only.**

- Every dependency is injected via a `New()` function. No global variables. No `init()` doing meaningful work.
- The service layer imports interfaces, never concrete types. Concrete implementations are wired only in `cmd/server/main.go`.
- Every cross-package dependency crosses through an interface. Repository interfaces are defined in the feature package; implementations live in `postgres/`.

**Flag as violations:**
- Any business logic in a handler (beyond parsing a request and calling a service method)
- Any business logic in `main.go`
- Any `var` at package scope that holds mutable state
- Any direct use of a concrete repository type in a service
- Any `service.go` that imports a `postgres/` package directly

---

## Error Handling

- Errors are always returned, never swallowed, never `panic`'d in business logic.
- Every error is wrapped with context: `fmt.Errorf("operation name: %w", err)`.
- Sentinel errors are defined in `pkg/errors/errors.go` and used for all domain error conditions. Handlers map these to HTTP status codes — they do not construct their own error strings.
- `panic()` is only acceptable for fatal startup configuration failures (e.g. missing JWT key at boot).

**Flag as violations:**
- `_ = someFunc()` discarding an error
- `if err != nil { return }` without wrapping
- New error strings in handlers that aren't mapped from a sentinel
- Any `panic` outside of startup configuration validation

---

## Context

- `context.Context` is always the first parameter of any function that touches a database, network, or filesystem.
- Context is never stored in a struct.

---

## Configuration

- All config is loaded and validated at startup via `pkg/config/config.go`.
- Missing or invalid security config (JWT signing key, DB password) is a fatal startup error — not a warning, not a fallback to a default.
- No silent defaults for any security-relevant value.

---

## Security — Absolute Rules

These are not style preferences. Any deviation is a bug.

### Passwords
- Argon2id only, using `golang.org/x/crypto/argon2`. Parameters: time=3, memory=65536, parallelism=2, saltLen=32, keyLen=32.
- PHC string format. Never bcrypt. Never SHA-256 or any raw hash of a password. Never MD5.

### JWT
- HMAC-SHA256, 15-minute access token lifetime exactly. No exceptions.
- Payload contains only: `sub`, `did`, `role`, `iat`, `exp`, `jti`.
- 256-bit signing key from environment. Fatal startup error if absent.

### Refresh Tokens
- 32 random bytes, base64url encoded.
- Only the SHA-256 hash is stored in the database. The raw token is never written anywhere persistent.

### Login Errors
- A failed login NEVER distinguishes "email not found" from "wrong password". Both return `ErrInvalidCredentials`. No exceptions, no logging of which case occurred at the HTTP layer.

### Token Reuse
- If a consumed refresh token is presented again, ALL sessions for that user are revoked immediately and a `token_reuse_detected` audit event is written.

### Audit Log
- The audit log is INSERT and SELECT only — no UPDATE, no DELETE, ever. This is enforced at the database level and must never be worked around in application code.

**Flag as violations:**
- Any password hashing that is not Argon2id with the exact parameters above
- Any JWT lifetime other than 15 minutes
- Any code path that stores a raw refresh token (not the hash) to the database
- Any login handler that returns different errors or messages for unknown email vs wrong password
- Any UPDATE or DELETE targeting `haven.audit_log`
- Any session revocation on token reuse that doesn't also write the audit event

---

## Bootstrap State Machine

The instance transitions through three states: `UNCLAIMED → SETUP → ACTIVE`. Each state is enforced at three independent layers: the DB column, HTTP middleware, and inside the handler. All three must pass.

- In `UNCLAIMED`: only `GET /` and `POST /api/setup/verify-token` are reachable. Everything else returns 503.
- In `SETUP`: only `GET /` and `POST /api/setup/*` are reachable. Everything else returns 503.
- In `ACTIVE`: `POST /api/setup/*` returns 410 Gone permanently.

**Flag as violations:**
- Any setup endpoint accessible in `ACTIVE` state without returning 410
- Any non-setup endpoint accessible before `ACTIVE` state
- Enforcement at fewer than all three layers (DB, middleware, handler)

---

## General Code Quality

- No over-engineering. Changes should be scoped to what was asked. No speculative abstractions, no helper functions used fewer than three times, no config flags for things that could just be constants.
- No backwards-compatibility shims for code that has been removed. If it's gone, it's gone.
- Comments only where the logic is not self-evident. No docstrings on obvious functions.
- Tests use the `-race` flag. Any test that passes only without `-race` is broken.
