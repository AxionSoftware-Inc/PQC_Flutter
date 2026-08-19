# Implementation Notes

Bu fayl bugungi implementatsiyaning amaliy xotirasi: nimaga qanday qaror olingan, nimalar ataylab sodda qoldirilgan, qaysi joylar keyin almashtiriladi.

## Product Scope

Hozirgi scope ataylab kichik:

1. login
2. private chat
3. 1 ta umumiy group chat
4. minimal UI
5. versioned PQC writer/reader foundation

## Deliberate Simplifications

Ataylab sodda qilingan joylar:

1. realtime o'rniga polling
2. seeded userlar o'rniga dynamic name + device binding
3. registration/password yo'q
4. typing indicator va rich-media presentation UX hali yo'q; avatar API va
   encrypted resumable chat-attachment transport mavjud
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
8. device login/sync vaqtida `ml-kem-768` va `ml-dsa-65` public key'lar backendga yuboriladi
9. private chat default writer `pqc:v2:`; V3 release profile `pqc:v3:` yozadi
10. private payload ichida content key `ML-KEM-768` bilan self va peer device uchun wrap qilinadi
11. content plaintext `AES-GCM` bilan shifrlanadi
12. payload `ML-DSA-65` bilan imzolanadi
13. self-sent encrypted payload local plaintext cache'ga yoziladi, shuning uchun history reload'da ham user o'z yuborgan xabarini ko'radi
14. oldin verified bo'lgan peer key o'zgarsa private send vaqtincha bloklanadi, user yangi key'ni qayta verify qilishi kerak
15. decoder successful decryptlardan keyin plaintext payload cache'ga yozadi
16. group key create/sync vaqtida usable participant device'larning hammasi qamrab olinishi shart
17. groupda biror participant usable PQC device key'siz bo'lsa xabar yuborish to'xtatiladi, partial envelope upload qilinmaydi
18. group key envelope default `group-wrap:pqc:v2:`; V2.5 profile
    `group-wrap:pqc:v2.5:` ni faqat server capability e'lon qilganda yozadi
19. group wrap `ML-KEM-768` bilan encapsulate qilinadi va `ML-DSA-65` bilan imzolanadi
20. outbound/inbound plaintext cache capped bo'lib yuradi va logout paytida tozalanadi

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
- `GET/PATCH /api/users/me/avatar`
- `POST /api/conversations/{id}/attachment-sessions`
- `PUT /api/attachment-sessions/{id}/chunks/{index}`
- `POST /api/attachment-sessions/{id}/complete`
- `GET /api/attachments/{id}/file`
- `POST /api/messages/{id}/reaction` va `POST /api/messages/{id}/read`

Muhim qarorlar:

1. server faqat transport, auth va metadata roli bajaradi
2. private key serverga chiqmaydi
3. group key faqat wrapped envelope sifatida serverga boradi
4. `ml-kem-768` yoki `ml-dsa-65` public key noto'g'ri bo'lsa backend reject qiladi

## Deploy Notes

Current development/smoke-test target:

`http://169.58.123.200/api`

Server routing:

- `http://169.58.123.200/api/*` -> Django backend
- `http://169.58.123.200/` -> boshqa mavjud site
- release Flutter builds must use an HTTPS URL supplied with `API_BASE_URL`

## Known Weak Spots

1. polling high traffic uchun yaxshi emas
2. crypto flow hali full double ratchet ishlatmaydi
3. group membership change bo'lsa rekey siyosati minimal
4. local plaintext cache / forensic risk alohida audit talab qiladi
5. attachment blobs default local storage'da; horizontal scaling uchun shared
   object storage va orphan-cleanup worker kerak
6. session token secret store orqali saqlanadi, remembered identity esa UX
   uchun oddiy prefs'da qoladi
7. live serverda domain/TLS hali o'rnatilmagan

## Recommended Next Work

1. regression tests
2. richer key verification UX
3. local encrypted cache strategy
4. signed device directory trust UX
