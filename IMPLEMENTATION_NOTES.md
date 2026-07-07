# Implementation Notes

Bu fayl bugungi implementatsiyaning amaliy xotirasi: nimaga qanday qaror olingan, nimalar ataylab sodda qoldirilgan, qaysi joylar keyin almashtiriladi.

## Product Scope

Hozirgi scope ataylab kichik:

1. login
2. private chat
3. 1 ta umumiy group chat
4. minimal UI
5. keyin PQC uchun toza foundation

## Deliberate Simplifications

Ataylab sodda qilingan joylar:

1. realtime o'rniga polling
2. seeded userlar o'rniga dynamic name + device binding
3. registration/password yo'q
4. avatar, media, typing, seen yo'q
5. bitta fixed `General Group`

## Current Flutter Notes

Asosiy qatlamlar:

- `lib/app/` app bootstrap
- `lib/core/` config, API, device, storage, models
- `lib/features/auth/` login va session
- `lib/features/chat/` conversations, messages, polling
- `lib/features/crypto/` message codecs, group key store

Yangi crypto orchestration shakli:

- `RoutedChatCipherService` encryption/decryption routing uchun ishlatiladi
- `ChatCipherAlgorithm` abstraction private/group/legacy algorithm'larni ajratadi
- `PrivateConversationSecurityCoordinator` private send oldidan trust check va peer prekey sync ishlarini bajaradi
- shu refactor PQC yoki hybrid KEM algorithm qo'shishni `ChatRepository` dan mustaqil qiladi

Muhim implementatsiya eslatmalari:

1. macOS va Android prototip bosqichida secure storage muammolari sabab ayrim secretlar local fallback store bilan ishlatilmoqda
2. session token va remembered identity alohida saqlanadi
3. invalid token holatida remembered identity saqlanib qoladi
4. private chat uchun peer key fingerprint local verify qilinadi
5. verified key o'zgarsa UI warning ko'rsatiladi
6. group key participant/device signature o'zgarsa qayta yaratiladi
7. Android secretlar secure storage'ga qaytarildi, legacy local secretlar read vaqtida migratsiya qilinadi
8. device login/sync vaqtida one-time prekey batch ham yuboriladi
9. private chat payload hozir `x25519:v4` bo'lsa prekey bootstrap ishlatadi
10. prekey yo'q holatda `x25519:v3` fallback ishlaydi
11. private transport hozir reliability uchun stateless-by-default; yangi private xabarlar asosan `x25519:v4` yoki fallback `x25519:v3` bilan yuboriladi
12. self-sent encrypted payload local plaintext cache'ga yoziladi, shuning uchun history reload'da ham user o'z yuborgan xabarini ko'radi
13. peer identity key o'zgarsa stale private session avtomatik tashlab yuboriladi
14. oldin verified bo'lgan peer key o'zgarsa private send vaqtincha bloklanadi, user yangi key'ni qayta verify qilishi kerak
15. x25519:v4 bootstrap decode muvaffaqiyatli bo'lsa local one-time prekey ham delete qilinadi
16. decoder successful decryptlardan keyin plaintext payload cache'ga yozadi, shuning uchun history qayta o'qilganda bootstrap/prekey state'ga qaramlik kamayadi
17. group key create/sync vaqtida usable participant device'larning hammasi qamrab olinishi shart
18. groupda biror participant usable device key'siz bo'lsa xabar yuborish to'xtatiladi, partial envelope upload qilinmaydi
19. eski `session:v1` payloadlari uchun backward-compatible decrypt qatlami saqlangan
20. legacy yoki buzilgan local private sessionlar read vaqtida auto-invalid bo'ladi
21. outbound/inbound plaintext cache capped bo'lib yuradi va logout paytida tozalanadi

## Current Backend Notes

Asosiy endpointlar:

- `POST /api/auth/login`
- `GET /api/users`
- `GET /api/users/me`
- `POST /api/users/me/device`
- `GET /api/conversations`
- `POST /api/private-conversations`
- `GET /api/conversations/{id}/messages`
- `POST /api/conversations/{id}/messages`
- `GET /api/conversations/{id}/keys`
- `POST /api/conversations/{id}/keys`

Muhim qarorlar:

1. server faqat transport, auth va metadata roli bajaradi
2. private key serverga chiqmaydi
3. group key faqat wrapped envelope sifatida serverga boradi
4. `x25519` public key noto'g'ri bo'lsa backend reject qiladi

## Deploy Notes

Current default production-like target:

`http://91.108.121.56/api`

Server routing:

- `http://91.108.121.56/api/*` -> Django backend
- `http://91.108.121.56/` -> boshqa mavjud site

## Known Weak Spots

1. polling high traffic uchun yaxshi emas
2. crypto flow hali full double ratchet ishlatmaydi
3. group membership change bo'lsa rekey siyosati minimal
4. local plaintext cache / forensic risk alohida audit talab qiladi
5. session token secret store orqali saqlanadi, remembered identity esa UX uchun oddiy prefs'da qoladi

## Recommended Next Work

1. regression tests
2. richer key verification UX
3. local encrypted cache strategy
4. hybrid PQC design
