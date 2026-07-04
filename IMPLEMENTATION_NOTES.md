# PQC Chat Prototype Status

## Current state

This repository now contains a working chat prototype with:

- Flutter client
- Django REST Framework backend
- automatic login with `username + device identity`
- one shared `General Group`
- private chats between any two users
- polling refresh every 3 seconds

## Authentication model

Current login is intentionally minimal for test distribution.

Flow:

1. User enters only a name.
2. Flutter creates or reuses a persistent app installation identifier.
3. Backend receives:
   - `username`
   - `device_id`
   - `device_name`
   - `platform`
4. If the username does not exist, backend creates it.
5. If the device is already linked to another username, login is rejected.
6. On successful login, the user is automatically added to `General Group`.

Important note:

- this is not a true hardware phone identifier
- it is a persistent app-side device identity stored locally on the device
- this is deliberate for testability, cross-platform support, and privacy safety

## Architecture notes

### Flutter

- `lib/app/` contains app bootstrap and screen switching
- `lib/core/` contains config, API, local storage, models, and device identity
- `lib/features/auth/` contains login and session state
- `lib/features/chat/` contains conversations, messages, and polling
- `lib/features/crypto/` contains placeholder message codec services for future PQC work

### Backend

- `users/` handles login, current user, user list, and device binding
- `chat/` handles conversations and messages
- `backend/config/` contains Django project settings and routing

## PQC status

PQC encryption is not implemented yet.

What is already prepared:

- Flutter message composition and decoding are separated behind interfaces
- backend remains transport-oriented
- future encryption can be inserted before send and after receive without changing chat UI flow

## Deployment target

The mobile app default API base URL is currently set to:

`http://91.108.121.56/api`

Current server routing:

- `http://91.108.121.56/api/*` -> Django chat backend through nginx reverse proxy
- `http://91.108.121.56/` -> existing non-chat site

Current server state for testing:

- database was reset to a clean state
- there are no pre-created test users
- only one default conversation exists: `General Group`
- users are created only when a new device logs in with a chosen name

This can still be overridden with:

```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_HOST:8000/api
```

## What to test now

1. Multiple testers can enter different names and join the shared group.
2. Two testers can open a private chat and exchange messages.
3. Reopening the app on the same device restores the same identity.
4. The same device cannot impersonate a different username later.
