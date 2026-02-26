# Haven — Manual Testing Guide

This guide walks through every step needed to verify a working Haven build against
the **Definition of Done** checklist. Follow the sections in order — each section
builds on state created by the one before it.

---

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Docker Desktop | 4.x |
| Go | 1.23 |
| `curl` | any |
| PowerShell | 7 (for the PS snippets) or adapt to bash |

---

## 1. Environment Setup

### 1a. Generate secrets

```bash
go run ./cmd/cli generate-secrets
```

Copy the output into `.env`. At minimum these must be present and non-empty:

```
DB_URL=postgres://haven:haven@localhost:5432/haven
REDIS_URL=redis://localhost:6379
JWT_SIGNING_KEY=<64-byte hex>
```

### 1b. Validate config (CLI smoke test)

```bash
go run ./cmd/cli validate-config --env-file .env
```

Expected output ends with `config OK` and lists each key. Exit code must be **0**.

### 1c. Start the stack

```bash
docker compose -f docker-compose.dev.yml up postgres redis -d
go run ./cmd/server
```

The server logs `haven listening on :8080` and `all migrations applied`.

---

## 2. Health Endpoint (all bootstrap states)

This endpoint must respond in every state — test it now (UNCLAIMED) and again
after each state transition.

```bash
curl -s http://localhost:8080/api/haven/health | jq .
```

Expected:
```json
{ "status": "ok", "state": "unclaimed" }
```

CLI healthcheck (DoD item — exit 0):
```bash
go run ./cmd/cli healthcheck --addr http://localhost:8080
echo "exit: $?"
```

---

## 3. Bootstrap Flow (UNCLAIMED → SETUP → ACTIVE)

### 3a. Check that protected routes are blocked in UNCLAIMED state

```bash
# Must return 503
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/haven/auth/login
```

Expected: `503`

### 3b. Retrieve the setup token

The server prints the setup token to stdout on first start:
```
[haven] setup token: <TOKEN>
```

Copy `<TOKEN>`.

### 3c. Verify the setup token

```bash
curl -s -X POST http://localhost:8080/api/setup/verify-token \
  -H "Content-Type: application/json" \
  -d '{"token": "<TOKEN>"}' | jq .
```

Expected: `{"state":"setup"}`. The instance is now in **SETUP** state.

Health check now shows `"state": "setup"`:
```bash
curl -s http://localhost:8080/api/haven/health | jq .state
```

### 3d. Verify SETUP route restrictions

```bash
# Login must still be blocked in SETUP state
curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:8080/api/haven/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"x@x.com","password":"x"}'
```

Expected: `503`

### 3e. Configure the instance (Step 2 of setup wizard)

```bash
curl -s -X POST http://localhost:8080/api/setup/instance \
  -H "Content-Type: application/json" \
  -d '{"name":"Home Haven","locale":"en-US","timezone":"America/New_York"}' | jq .
```

Expected: `{"state":"setup"}` or similar success response.

### 3f. Create the owner account (Step 3 — SETUP → ACTIVE)

```bash
curl -s -X POST http://localhost:8080/api/setup/owner \
  -H "Content-Type: application/json" \
  -d '{
    "email": "owner@example.com",
    "display_name": "Alice Owner",
    "password": "supersecret123",
    "device_name": "Alice MacBook",
    "platform": "web"
  }' | jq .
```

Expected: JSON with `access_token` field. The instance is now **ACTIVE**.

```bash
# Health now shows active
curl -s http://localhost:8080/api/haven/health | jq .state
```

Expected: `"active"`

### 3g. Verify setup routes return 410 Gone in ACTIVE state

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:8080/api/setup/verify-token \
  -H "Content-Type: application/json" \
  -d '{"token":"anything"}'
```

Expected: `410`

---

## 4. Owner Login

```bash
OWNER_TOKEN=$(curl -s -X POST http://localhost:8080/api/haven/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "owner@example.com",
    "password": "supersecret123",
    "device_name": "Alice MacBook",
    "platform": "web",
    "fingerprint": "fp-alice-web"
  }' | jq -r .access_token)

echo "token: $OWNER_TOKEN"
```

A non-empty JWT must be printed.

### 4a. Validate the token (Luma integration point)

```bash
curl -s http://localhost:8080/api/haven/validate \
  -H "Authorization: Bearer $OWNER_TOKEN" | jq .
```

Expected: JSON containing `user.id`, `user.email`, `role`, `device_id`.

---

## 5. Authz Check (Luma integration point)

Retrieve the owner's user ID from the validate response:

```bash
OWNER_ID=$(curl -s http://localhost:8080/api/haven/validate \
  -H "Authorization: Bearer $OWNER_TOKEN" | jq -r .user.id)
```

Run an authz check — owner should be allowed everything:

```bash
curl -s -X POST http://localhost:8080/api/haven/authz/check \
  -H "Authorization: Bearer $OWNER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$OWNER_ID\",
    \"action\": \"user:invite\",
    \"resource_type\": \"user\",
    \"resource_id\": \"*\",
    \"vault_id\": \"\"
  }" | jq .
```

Expected: `{"allowed": true}`

Run a check for an action a member shouldn't have — confirm denial is audited:

```bash
curl -s -X POST http://localhost:8080/api/haven/authz/check \
  -H "Authorization: Bearer $OWNER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$OWNER_ID\",
    \"action\": \"nonexistent:action\",
    \"resource_type\": \"page\",
    \"resource_id\": \"*\",
    \"vault_id\": \"\"
  }" | jq .
```

Expected: `{"allowed": false}`

---

## 6. Second User — Invitation-Gated Registration

### 6a. Create an invitation

```bash
INVITE=$(curl -s -X POST http://localhost:8080/api/haven/invitations \
  -H "Authorization: Bearer $OWNER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email": "bob@example.com", "note": "Join Haven!"}')

echo "$INVITE" | jq .
INVITE_TOKEN=$(echo "$INVITE" | jq -r .token)   # raw token — share with invitee
INVITE_ID=$(echo "$INVITE" | jq -r .id)
```

### 6b. Register the second user

```bash
BOB_TOKEN=$(curl -s -X POST http://localhost:8080/api/haven/auth/register \
  -H "Content-Type: application/json" \
  -d "{
    \"invitation_token\": \"$INVITE_TOKEN\",
    \"email\": \"bob@example.com\",
    \"display_name\": \"Bob Member\",
    \"password\": \"bobspassword456\",
    \"device_name\": \"Bob iPhone\",
    \"platform\": \"ios\",
    \"fingerprint\": \"fp-bob-ios\"
  }" | jq -r .access_token)

echo "Bob token: $BOB_TOKEN"
```

Expected: HTTP 201, non-empty access token.

### 6c. Verify Bob can log in independently

```bash
BOB_TOKEN=$(curl -s -X POST http://localhost:8080/api/haven/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "bob@example.com",
    "password": "bobspassword456",
    "device_name": "Bob Android",
    "platform": "android",
    "fingerprint": "fp-bob-android"
  }' | jq -r .access_token)

echo "Bob login: $BOB_TOKEN"
```

### 6d. Verify Bob cannot perform owner actions

```bash
BOB_ID=$(curl -s http://localhost:8080/api/haven/validate \
  -H "Authorization: Bearer $BOB_TOKEN" | jq -r .user.id)

curl -s -X POST http://localhost:8080/api/haven/authz/check \
  -H "Authorization: Bearer $BOB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$BOB_ID\",
    \"action\": \"user:lock\",
    \"resource_type\": \"user\",
    \"resource_id\": \"*\",
    \"vault_id\": \"\"
  }" | jq .allowed
```

Expected: `false`

---

## 7. Token Refresh

```bash
# The refresh token is in the HttpOnly cookie set on login.
# Use a cookie jar to capture it.
curl -s -c /tmp/haven-cookies.txt -X POST http://localhost:8080/api/haven/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "owner@example.com",
    "password": "supersecret123",
    "device_name": "Refresh Test",
    "platform": "web",
    "fingerprint": "fp-refresh-test"
  }' > /dev/null

# Use the cookie to refresh.
NEW_TOKEN=$(curl -s -b /tmp/haven-cookies.txt \
  -X POST http://localhost:8080/api/haven/auth/refresh | jq -r .access_token)

echo "Refreshed token: $NEW_TOKEN"
```

A new, non-empty access token must be returned.

---

## 8. Security: Token Reuse Detection

This test verifies that presenting a consumed refresh token triggers full session revocation.

1. Log in and capture the refresh token cookie.
2. Refresh once (token is consumed).
3. Send the **old** refresh token again.
4. Expected: **401** with `TOKEN_REVOKED` code.
5. Verify in the server log: `token_reuse_detected` audit event.
6. Try using the access token from step 2 — it should still work until it expires (15 min), but after that, all sessions for this user are revoked.

```bash
# Step 1 — login, capture cookie
curl -s -c /tmp/reuse-test.txt -b /tmp/reuse-test.txt \
  -X POST http://localhost:8080/api/haven/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "owner@example.com",
    "password": "supersecret123",
    "device_name": "Reuse Test",
    "platform": "web",
    "fingerprint": "fp-reuse-test"
  }' > /dev/null

# Step 2 — first refresh (consumes the token)
curl -s -c /tmp/reuse-test.txt -b /tmp/reuse-test.txt \
  -X POST http://localhost:8080/api/haven/auth/refresh > /dev/null

# Step 3 — replay the old cookie (must fail with 401)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -b /tmp/reuse-test.txt \
  -X POST http://localhost:8080/api/haven/auth/refresh)

echo "Reuse response: $STATUS"   # expected: 401
```

Check server output for:
```
audit: token_reuse_detected  user_id=<owner-uuid>
```

---

## 9. Security: Brute-Force Lockout

After **10 consecutive failed logins** the account is locked.

```bash
for i in $(seq 1 11); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST http://localhost:8080/api/haven/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"bob@example.com","password":"WRONG","device_name":"x","platform":"web","fingerprint":"fp-bf"}')
  echo "attempt $i: $STATUS"
done
```

Responses 1–10: `401` (`INVALID_CREDENTIALS`).
Response 11 (account now locked): `403` (`ACCOUNT_LOCKED`).

Unlock Bob's account as owner:

```bash
curl -s -X POST "http://localhost:8080/api/haven/admin/users/$BOB_ID/unlock" \
  -H "Authorization: Bearer $OWNER_TOKEN" | jq .
```

Expected: 204 No Content.

---

## 10. Device Management

### 10a. List devices

```bash
curl -s http://localhost:8080/api/haven/devices \
  -H "Authorization: Bearer $OWNER_TOKEN" | jq .
```

Expected: array of devices. Each device from previous logins should appear.

### 10b. Remote device revocation

Pick a device ID from the list above:

```bash
DEVICE_ID="<paste device id>"

curl -s -X DELETE "http://localhost:8080/api/haven/devices/$DEVICE_ID" \
  -H "Authorization: Bearer $OWNER_TOKEN"
```

Expected: 204 No Content.

Verify the device no longer appears in the list. Any refresh attempt using the revoked device's token must return 403 (`DEVICE_REVOKED`).

Revocation must propagate within **15 minutes** for long-lived tokens — verify by waiting and retrying the refresh on the revoked device.

### 10c. Admin: revoke all sessions for a user

```bash
curl -s -X DELETE "http://localhost:8080/api/haven/admin/users/$BOB_ID/sessions" \
  -H "Authorization: Bearer $OWNER_TOKEN"
```

Expected: 204 No Content. Bob's next refresh must fail.

---

## 11. Audit Log

### 11a. Verify INSERT-only constraint at DB level

Connect to the database directly:

```bash
docker exec -it haven-postgres-1 psql -U haven -d haven
```

```sql
-- This must succeed:
INSERT INTO haven.audit_log (event) VALUES ('manual_test');

-- This must fail with permission denied:
UPDATE haven.audit_log SET event = 'tampered' WHERE event = 'manual_test';

-- This must fail with permission denied:
DELETE FROM haven.audit_log WHERE event = 'manual_test';
```

Expected: `UPDATE` and `DELETE` return `ERROR: permission denied for table audit_log`.

### 11b. View owner's audit log via API

```bash
curl -s "http://localhost:8080/api/haven/audit?limit=20" \
  -H "Authorization: Bearer $OWNER_TOKEN" | jq '.[] | .event'
```

Events like `login_success`, `token_refreshed`, `device_registered` should appear.

---

## 12. Unit and Integration Tests

### 12a. Unit tests (no external services needed)

```bash
go test -race ./...
```

Expected: all packages pass, zero failures, zero skips.

### 12b. Integration tests (requires PostgreSQL)

```bash
HAVEN_TEST_DB_URL=postgres://haven:haven@localhost:5432/haven \
  go test -race -v ./internal/integration/
```

Expected: all tests pass. The output will show `--- PASS:` for each test.

> **Tip:** Run integration tests against a dedicated test database, not your
> development database, to avoid state conflicts:
> ```bash
> docker exec haven-postgres-1 createdb -U haven haven_test
> HAVEN_TEST_DB_URL=postgres://haven:haven@localhost:5432/haven_test \
>   go test -race -v ./internal/integration/
> ```

---

## 13. Multi-Platform Login (DoD Items 3–6)

Verify that two users can log in from multiple platforms and the device list
accurately reflects each session.

| User | Platform | Expected device name |
|------|----------|----------------------|
| Alice (owner) | Web browser | Populated from `device_name` field |
| Alice (owner) | iOS (Keychain) | Separate device entry |
| Bob (member)  | iOS (Keychain) | Separate device entry |
| Bob (member)  | Android (EncryptedSharedPreferences) | Separate device entry |

For each login, verify:
- `GET /api/haven/devices` shows the correct number of active devices.
- The refresh token stored on the device works and produces a new access token.

---

## 14. Definition of Done — Checklist

Work through this list after completing all sections above.

- [ ] **1.** All unit tests pass with `-race`, zero skips (`go test -race ./...`)
- [ ] **2.** All integration tests pass against real PostgreSQL (`go test -race ./internal/integration/`)
- [ ] **3.** Alice (owner) registers and logs in from web browser on LAN
- [ ] **4.** Bob (member) registers and logs in from web browser on LAN
- [ ] **5.** Alice logs in from iOS with refresh token persisted in Keychain
- [ ] **6.** Bob logs in from iOS with refresh token persisted in Keychain (or Android)
- [ ] **7.** Bob logs in from Android with refresh token in EncryptedSharedPreferences
- [ ] **8.** Device list accurate — each platform login creates a distinct device entry
- [ ] **9.** Remote device revocation propagates within 15 minutes (§10b)
- [ ] **10.** Token reuse detection triggers full session revocation (§8)
- [ ] **11.** Brute-force lockout after 10 attempts (§9); unlock works (§9)
- [ ] **12.** Audit log INSERT-only constraint verified at DB level (§11a)
- [ ] **13.** Luma calls `/api/haven/validate` successfully (§4a)
- [ ] **14.** Luma calls `/api/haven/authz/check` and gets `allowed: true` for owner (§5)
- [ ] **15.** Both users in daily use for 7 consecutive days before Luma feature work begins

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Server exits at startup with `fatal: JWT_SIGNING_KEY missing` | `.env` not loaded | `source .env` or set env vars before running |
| `503` on all routes | Instance still UNCLAIMED | Complete bootstrap steps §3b–3f |
| `410` on `/api/setup/*` | Instance already ACTIVE | Expected — setup is one-time only |
| `401 INVALID_CREDENTIALS` on valid login | Password mismatch or wrong email | Double-check credentials; emails are case-sensitive |
| `403 ACCOUNT_LOCKED` | Brute-force triggered | Unlock via `POST /api/haven/admin/users/{id}/unlock` as owner |
| `401 TOKEN_REVOKED` on refresh | Token reuse detected or device revoked | Log in fresh |
| Integration tests fail with `dial error` | PostgreSQL not running | `docker compose -f docker-compose.dev.yml up postgres -d` |
| `migrate up: ERROR: role "haven_app" does not exist` | DB user grant fails on fresh DB | Safe to ignore — grant is conditional; see migration 0001 |
