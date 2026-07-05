# PQC Chat App

Minimal `Flutter + Django REST Framework` chat prototipi.

Hozirgi ishchi scope:

- ism + device identity bilan login
- 1 ta umumiy `General Group`
- istalgan 2 user orasida private chat
- polling asosidagi refresh
- private chat uchun `X25519 + AES-GCM`
- group chat uchun client-side group key + wrapped key envelopes
- manual key verification va key-change warning

Bu hali production messenger emas. Hozirgi maqsad: ishlaydigan, test qilsa bo'ladigan, keyin PQC qo'shish mumkin bo'lgan toza baza.

## Current Status

Ishlaydi:

- login
- private chat
- group chat
- server deploy
- Android release APK build
- minimal E2EE foundation
- key verification banner

Hozircha yo'q:

- WebSocket realtime
- key rotation
- forward secrecy / double ratchet
- multi-device key fanout
- PQC / hybrid KEM

## Repo Shape

```text
backend/   Django project config
chat/      DRF chat app
users/     login, device binding, user/device registry
lib/       Flutter client
test/      Flutter tests
```

## Server Default

Default API base URL:

`http://91.108.121.56/api`

Override qilish mumkin:

```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_HOST:8000/api
```

## Backend Setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt
.venv/bin/python backend/manage.py migrate
.venv/bin/python backend/manage.py runserver
```

Local API:

`http://127.0.0.1:8000/api`

## Flutter Setup

```bash
flutter pub get
flutter run
```

## Auth Model

1. User faqat ism kiritadi.
2. App local persistent `device_id` yaratadi.
3. App local device key pair yaratadi.
4. Backend user va device bindingni saqlaydi.
5. O'sha qurilma keyin shu userga bog'langan bo'lib qoladi.

Muhim:

- bu hardware IMEI emas
- bu app-side persistent identity
- test bosqichi uchun ataylab shunday qilingan

## Encryption Snapshot

Private chat:

- payload format:
  - `x25519:v4:<sender-device-id>:<sender-static-public-key>:<sender-ephemeral-public-key>:<recipient-prekey-id>:<nonce>:<ciphertext>:<mac>`
  - fallback: `x25519:v3:<sender-device-id>:<sender-static-public-key>:<sender-ephemeral-public-key>:<nonce>:<ciphertext>:<mac>`
- key: ikki device orasidagi `X25519 shared secret`dan derive qilinadi
- asosiy yo'l: recipient one-time prekey + static + per-message ephemeral secret kombinatsiyasi
- fallback: static + per-message ephemeral secret kombinatsiyasi

Group chat:

- payload format: `group:v1:<key_id>:<nonce>:<ciphertext>:<mac>`
- group secret clientda yaratiladi
- har participant device uchun wrapped key envelope serverga yuboriladi

Server nimalarni ko'radi:

- ciphertext
- conversation metadata
- user / device metadata

Server nimalarni ko'rmaydi:

- private device key
- ready plaintext message body

Secret storage:

- Android: secure storage primary, legacy SharedPreferences secretlar avtomatik migratsiya qilinadi
- macOS: hozircha prototip fallback storage ishlatiladi

Prekey note:

- har device serverga public one-time prekey batch sync qiladi
- private chat yangi xabar yuborishda usable peer prekey bo'lsa `v4` bootstrap ishlatadi

## Important Docs

- [ARCHITECTURE.md](/Users/macbookpro/Documents/PQC%20Chat%20app/ARCHITECTURE.md)
- [IMPLEMENTATION_NOTES.md](/Users/macbookpro/Documents/PQC%20Chat%20app/IMPLEMENTATION_NOTES.md)
- [E2EE_FOUNDATION_STATUS.md](/Users/macbookpro/Documents/PQC%20Chat%20app/E2EE_FOUNDATION_STATUS.md)
- [ENCRYPTION_STORAGE_MODES.md](/Users/macbookpro/Documents/PQC%20Chat%20app/ENCRYPTION_STORAGE_MODES.md)
- [PROJECT_AUDIT_2026_07_04.md](/Users/macbookpro/Documents/PQC%20Chat%20app/PROJECT_AUDIT_2026_07_04.md)

## Tests

```bash
.venv/bin/python backend/manage.py test users chat
flutter test
flutter analyze
```
