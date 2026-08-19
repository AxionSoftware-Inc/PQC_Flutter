# PQC Chat App

Minimal `Flutter + Django REST Framework` chat prototipi.

Hozirgi ishchi scope:

- ism + device identity bilan login
- 1 ta umumiy `General Group`
- istalgan 2 user orasida private chat
- polling asosidagi refresh
- private chat uchun versioned PQC transport
- group chat uchun client-side group key + wrapped key envelopes
- manual key verification va key-change warning

Bu hali production messenger emas. Hozirgi maqsad: versioned PQC, recovery va
capability negotiation bilan ishlaydigan, test qilsa bo'ladigan toza baza;
production hardening alohida release gate'lar bilan bajariladi.

## Current Status

Ishlaydi:

- login
- private chat
- group chat
- server deploy
- Android debug/release APK build
- PQC private payloads
- PQC group key wrapping
- key verification banner

Hozircha yo'q:

- WebSocket realtime
- full automatic key rotation / rekey UX
- forward secrecy / double ratchet
- production-grade trust center UX
- full PQC trust-center UX

## Current Crypto Shape

Crypto qatlam hozir ikki aniq yo'lga ajratilgan:

- `ChatRepository` endi to'g'ridan-to'g'ri `X25519` yoki `group` codec'larni bilmaydi
- `RoutedChatCipherService` conversation/payload bo'yicha mos algorithm'ni tanlaydi
- `PrivateConversationSecurityCoordinator` private send oldidan trust holatini boshqaradi
- private/group uchun aktiv yozish formati release profile'ga bog'liq: V2/V2.5 uchun `pqc:v2:` / `group:v2:`, V3 uchun `pqc:v3:` / `group:v3:`
- group key envelope V2 yoki V2.5 sifatida alohida negotiate qilinadi
- har bir device o'zining `supported_protocols` capability'sini serverga bildiradi; recipient mos bo'lmasa V2.5/V3 yozish fail-closed bo'ladi
- eski klassik formatlar endi aktiv write path emas

Hozir amalda ishlayotgan algorithm'lar:

- private chat: `ML-KEM-768` + `AES-GCM` + `ML-DSA-65`
- group chat: PQC wrapped group key + `AES-GCM`
- legacy decrypt compatibility: faqat tarixiy oqimlar uchun

Release profile va protocol negotiation xaritasi: [docs/release-profiles.md](docs/release-profiles.md).

## Repo Shape

```text
services/backend/   Django service root
services/backend/chat/      DRF chat app
services/backend/users/     login, device binding, user/device registry
packages/pqc_engine_sdk/    pure Dart versioned PQC engine contract
packages/crypto_core/       crypto policy, routing and key durability
packages/chat_core/         chat orchestration and transport boundary
lib/       Flutter client and composition root
test/      Flutter tests
```

Yangi dasturchi uchun qisqa yo‘l xaritasi: [docs/CODEBASE_MAP.md](docs/CODEBASE_MAP.md).

## Server URL

Debug builds use the current HTTP server as a development fallback:

`http://169.58.123.200/api`

Override qilish mumkin:

```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_HOST:8000/api
```

Release builds fail closed unless an HTTPS API URL is supplied:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://chat.example.com/api \
  --dart-define=SDK_RELEASE=v2
```

The current server is still HTTP-only, so it is suitable for development and
network smoke tests, not a secure public release. Domain, TLS certificate and
reverse-proxy termination must be configured before production rollout.

## Backend Setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r services/backend/requirements.txt
.venv/bin/python services/backend/manage.py migrate
.venv/bin/python services/backend/manage.py runserver
```

Local API:

`http://127.0.0.1:8000/api`

PostgreSQL bilan ishlatish: [POSTGRES_SETUP.md](POSTGRES_SETUP.md)

Production backend qo‘shimcha ravishda shared `REDIS_URL` va
`DJANGO_MEDIA_STORAGE=s3`/`AWS_STORAGE_BUCKET_NAME` talab qiladi. Shu sababli
websocket eventlari workerlar orasida yo‘qolmaydi va attachment chunklari
serverning lokal diskiga bog‘lanib qolmaydi. Deploy script attachment temporary
object cleanup timerini ham o‘rnatadi.

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

## Persistence Rules

App hozir quyidagilarni eslab qoladi:

- `device_id`
- local device keylar
- session
- remembered display name
- chat conversations
- message history
- outbox queue
- verified key fingerprints

Muhim qoidalar:

- `outbox clear` endi chat history'ni o'chirmaydi
- local DB bo'sh, lekin sync marker qolib ketgan bo'lsa app full-fetch fallback qiladi
- agar ayni `device_id` ostida keylar yo'qolib qayta yaralsa, app bu holatni yangi installation deb aylantiradi
- bu `key changed` spamini kamaytirish uchun qilingan

Qisqa amaliy xulosa:

- app restartdan keyin chatlar qolishi kerak
- qurilma qayta ochilganda shu device sifatida davom etishi kerak
- secure storage buzilsa, jim noto'g'ri state bilan yurish o'rniga yangi installation identity olinadi

## Encryption Snapshot

Private chat:

- default payload format: `pqc:v2:*`; V3 release profile writes `pqc:v3:*`
- content plaintext `AES-GCM` bilan shifrlanadi
- content key `ML-KEM-768` bilan self va peer device uchun wrap qilinadi
- payload `ML-DSA-65` bilan imzolanadi
- plaintext payload ichida ko'rinmaydi

Group chat:

- default payload format: `group:v2:<key_id>:<nonce>:<ciphertext>:<mac>`;
  V3 release profile writes `group:v3:*`
- group secret clientda yaratiladi
- har participant device uchun PQC wrapped key envelope serverga yuboriladi
- group envelope writer `group-wrap:pqc:v2:` yoki negotiated V2.5
  (`group-wrap:pqc:v2.5:`) bo‘ladi; V3 profile V2 envelope reader’ini saqlaydi

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

## Important Docs

- [Codebase map](docs/CODEBASE_MAP.md)
- [SDK release profiles](docs/release-profiles.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [TECHNICAL_STATUS.md](TECHNICAL_STATUS.md)
- [CRYPTO_DURABILITY_CORE.md](CRYPTO_DURABILITY_CORE.md)
- [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md)
- [E2EE_FOUNDATION_STATUS.md](E2EE_FOUNDATION_STATUS.md)
- [ENCRYPTION_STORAGE_MODES.md](ENCRYPTION_STORAGE_MODES.md)
- [PROJECT_AUDIT_2026_07_04.md](PROJECT_AUDIT_2026_07_04.md)

## Tests

```bash
.venv/bin/python services/backend/manage.py test --noinput
ANTIQ_BACKEND_PLUGINS=rbac,task_kpi .venv/bin/python services/backend/manage.py test --noinput
flutter test
flutter analyze
```

Korporativ yo‘l bo‘yicha keyingi katta qatlam: mixed-device migration, recovery va
trust-center UX’ni real qurilmalarda yakunlash. Flutter crypto va chat kodlari
mos ravishda `packages/crypto_core/` va `packages/chat_core/` ichida, backend
esa `services/backend/` ichida saqlanadi.
