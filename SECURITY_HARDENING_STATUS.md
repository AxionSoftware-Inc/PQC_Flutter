# Security Hardening Status

## Implemented in this pass
- Device-bound login now reuses the same account only for the same `device_id`
- Same display name on different devices creates distinct accounts
- `account_id` and `device_id` are returned from login
- Device metadata now includes `created_at` and `updated_at`
- Structured JSON API errors are enabled
- Backend defaults to `DEBUG=False`
- Health endpoint added at `/health/`
- Message send idempotency added through `client_message_id`
- Incremental sync added for conversations and messages
- Persistent outbox queue added on Flutter side
- Retryable vs permanent send failures added to UI
- macOS secret store no longer uses SharedPreferences as the primary secret store

## Still not fully closed
- Full HTTPS/TLS termination is not complete until the live server is served over HTTPS with a valid certificate/domain
- Key verification is still primarily peer/device-selection based, not a full multi-device trust center UX
- Group trust summary UI is still minimal
- Full ratcheted private transport migration is not complete
- Detailed threat transparency and ops alerting are still minimal

## Current Product State
- Stronger than the earlier prototype
- Suitable as a much safer internal baseline for continuing toward production
- Not yet final “production secure messenger” level before the remaining TLS + trust-center + full rotation work is finished
