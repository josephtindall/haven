# Haven

Haven is a self-hosted IAM sidecar. Any project that needs authentication adds one block to its `docker-compose.yml` and gets a complete identity layer without building one.

## What it provides

- Registration, login, and session management
- Short-lived JWT access tokens (15 min) with rotating refresh tokens
- Multi-device tracking with remote revocation
- Role-based access control with a four-dimension policy evaluator
- Invitation system for closed-registration instances
- Full audit log (insert-only, enforced at the database level)
- Bootstrap wizard — a setup token printed to stdout on first start gates the entire API until an owner account is created

## How it works

Haven runs as a separate container alongside your application. Your app calls two endpoints on every authenticated request:

- `GET /api/haven/validate` — verifies a Bearer token and returns the user's ID, role, and device ID
- `POST /api/haven/authz/check` — evaluates whether a user may perform a given action on a given resource

Haven never calls your application. The dependency is strictly one-directional.

## Documentation

- `docs/haven-design.md` — complete specification: bootstrap state machine, database schema, security requirements, full API surface
- `docs/rbac-design.md` — permission model, action taxonomy, authz API
- `docs/testing-guide.md` — manual and integration testing procedures