# Deploy Smoke Check

## Backend
- `GET /api/health` returns `{"status":"ok"}`
- `POST /api/auth/login` returns `token`, `account_id`, `device_id`, `user`
- `GET /api/users/me` works with returned token
- `GET /api/conversations` works with token
- `POST /api/conversations/{id}/messages` with `client_message_id` is idempotent
- `GET /api/conversations/{id}/messages?after_id=N` returns only newer messages
- `POST /api/users/{user_id}/devices/{device_id}/claim-prekey` returns JSON, not HTML

## Client
- Login from Android works
- Login from macOS works
- Same display name on different devices creates separate accounts
- Same device re-login restores same account
- Failed send shows retry state
- Retry button clears failed-retryable message after sync succeeds

## Security Notes
- Device-bound account bootstrap is implemented
- Ciphertext storage is implemented
- Structured JSON API errors are implemented
- HTTPS/TLS still depends on server/domain termination configuration
