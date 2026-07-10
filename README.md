# PQC Chat App

Minimal `Flutter + Django REST Framework` chat prototipi.

Hozirgi ishchi scope:

- ism + device identity bilan login
- 1 ta umumiy `General Group`
- istalgan 2 user orasida private chat
- polling asosidagi refresh
- private chat uchun bitta barqaror shared-secret transport
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
- minimal ciphertext-at-rest foundation
- key verification banner

Hozircha yo'q:

- WebSocket realtime
- key rotation
- forward secrecy / double ratchet
- production-grade multi-device private E2EE
- full PQC trust-center UX

## Current Crypto Shape

Crypto qatlam hozir ikki aniq yo'lga ajratilgan:

- `ChatRepository` endi to'g'ridan-to'g'ri `X25519` yoki `group` codec'larni bilmaydi
- `RoutedChatCipherService` conversation/payload bo'yicha mos algorithm'ni tanlaydi
- `PrivateConversationSecurityCoordinator` private send oldidan trust holatini boshqaradi
- private chat uchun aktiv yozish formati hozir faqat `enc:v1`
- eski `x25519:*`, `hybrid:*`, `session:*` payloadlar faqat backward-compatible decrypt uchun saqlangan

Hozir amalda ishlayotgan algorithm'lar:

- private chat: `enc:v1`
- group chat: wrapped group key + `AES-GCM`
- legacy decrypt compatibility: `x25519:*`, `hybrid:*`, `session:*`

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

PostgreSQL bilan ishlatish:

- [POSTGRES_SETUP.md](/Users/macbookpro/Documents/PQC%20Chat%20app/POSTGRES_SETUP.md)

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

- payload format: `enc:v1:<nonce>:<ciphertext>:<mac>`
- key: conversation-derived shared secret
- maqsad: macOS va Android o'rtasida yagona, stabil, bir xil private transport ishlatish
- eski `x25519:*`, `hybrid:*`, `session:*` formatlar faqat oldingi tarixiy xabarlarni o'qish uchun qoldirilgan

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

Korporativ yo‘l bo‘yicha keyingi katta qatlamni qo‘shdim: private chat endi nafaqat ML-KEM-768 bilan hybrid secret oladi, balki peer device signing key e’lon qilgan bo‘lsa payload ML-DSA-65 bilan ham imzolanadi. Shuning uchun arxitektura endi “server ciphertextni tashiydi” darajasidan “device-level signed private transport foundation” darajasiga ko‘tarildi.
Asosiy o‘zgarishlar [lib/core/device/device_pqc_signing_key_service.dart](/Users/macbookpro/Documents/PQC Chat app/lib/core/device/device_pqc_signing_key_service.dart), [lib/features/crypto/message_codec.dart](/Users/macbookpro/Documents/PQC Chat app/lib/features/crypto/message_codec.dart), [lib/features/auth/data/auth_repository.dart](/Users/macbookpro/Documents/PQC Chat app/lib/features/auth/data/auth_repository.dart), [lib/core/models/app_user.dart](/Users/macbookpro/Documents/PQC Chat app/lib/core/models/app_user.dart), [users/models.py](/Users/macbookpro/Documents/PQC Chat app/users/models.py), [users/serializers.py](/Users/macbookpro/Documents/PQC Chat app/users/serializers.py), [users/views.py](/Users/macbookpro/Documents/PQC Chat app/users/views.py), [users/migrations/0005_userdevice_pqc_signing_public_key_and_more.py](/Users/macbookpro/Documents/PQC Chat app/users/migrations/0005_userdevice_pqc_signing_public_key_and_more.py) da. Device sync endi PQC signing public key’ni ham olib yuradi, private payload signed variantlarni tushunadi, verify qilolmasa reject qiladi, lekin eski/signed bo‘lmagan oqimlar bilan backward compatibility saqlangan.
