# E2EE Foundation Status

Bu hujjat hozirgi kriptografik foundation qayergacha kelganini va hali qayerlari kuchsiz ekanini amaliy tarzda jamlaydi.

## Hozir Nima Ishlaydi

### Private chat

1. Har device local `identity key pair` yaratadi
2. Public key login yoki device sync vaqtida backendga yuboriladi
3. Private chat xabari `X25519 shared secret` asosida encrypt qilinadi
4. Payload serverda `x25519:v4:*` yoki fallback `x25519:v3:*` ko'rinishida saqlanadi
5. Har xabar uchun ephemeral public key bor
6. Device'lar one-time prekey batch sync qiladi
7. Peer usable prekey bo'lsa private bootstrap shu prekey bilan boshlanadi
8. Payload ichida jo'natuvchining static public key'i borligi uchun yangi formatdagi xabarlar key rotate'dan keyin ham ochilishi mumkin
9. Private transport hozir reliability uchun stateless-by-default: yangi xabarlar asosan `x25519:v4` yoki fallback `x25519:v3` formatida yuboriladi
10. Self-sent encrypted payload uchun local plaintext cache bor, shu sabab yuborgan xabar history reload'da ham ko'rinadi
11. Peer identity key o'zgarsa stale private session bekor qilinadi va eski session qayta ishlatilmaydi
12. Oldin verified bo'lgan peer key o'zgarsa private send verify qilinmaguncha bloklanadi
13. Private bootstrap decode bo'lgach one-time prekey local store'dan ham consume qilinadi
14. Inbound encrypted plaintext ham payload cache'ga tushadi, shuning uchun consumed prekey history reload'ni sindirmaydi
15. Eski `session:v1` tarixiy payloadlari uchun backward-compat decrypt qatlami saqlangan
16. Legacy yoki buzilgan private session state avtomatik tashlab yuboriladi va yangi bootstrap majburlanadi
17. Plaintext payload cache bounded bo'lib saqlanadi va logout paytida tozalanadi

### Group chat

1. Group secret clientda yaratiladi
2. Har participant device uchun alohida wrapped key envelope yaratiladi
3. Server faqat envelope'larni saqlaydi
4. Payload `group:v1:*` ko'rinishida saqlanadi
5. Participant usable device ro'yxati o'zgarsa keyingi yuborishda yangi group key yaratiladi
6. Group key sync endi usable participant device'larning barchasi uchun envelope talab qiladi
7. Kimdadir usable device key bo'lmasa group send to'xtatiladi, partial distribution bo'lmaydi

## Hozir Nima Yo'q

1. safety number UI
2. full forward secrecy
3. double ratchet
4. message retry / rekey orchestration
5. PQC

## Server Nimalarni Biladi

Server biladi:

1. user identity metadata
2. device ids
3. public keys
4. conversation metadata
5. ciphertext

Server bilmaydi:

1. device private key
2. ready plaintext
3. unwrapped group secret

## Hozirgi Xavfsizlik Bahosi

Bugungi holat:

- server-side plaintext hiding: `ha`
- private key serverga chiqmasligi: `ha`
- private chat real X25519 foundation: `ha`
- private chat static + ephemeral derivation: `ha`
- private chat prekey bootstrap foundation: `ha`
- private chat stateless reinstall-safe transport default: `ha`
- stale private session automatic invalidation: `ha`
- verified key change bo'lsa private send guard: `ha`
- one-time prekey local consume semantics: `ha`
- inbound encrypted history cache after successful decrypt: `ha`
- legacy session payload backward compatibility layer: `ha`
- bounded plaintext cache cleanup on logout: `ha`
- self-sent encrypted history readability: `ha`
- private key verification va key change warning foundation: `ha`
- group chat client-side key wrapping: `ha`
- group key full-device coverage enforcement: `ha`
- production-grade messenger security: `yo'q`

## Eng Katta Hali Qolgan Kamchiliklar

1. Stateless default transport reliability'ni oshirdi, lekin hali full double ratchet va Signal darajasidagi forward secrecy yo'q
2. Verification UX hali minimal
3. Group rekey policy endi device coverage qat'iy, lekin hali membership epoch / sender key darajasiga chiqmagan
4. Local plaintext cache bounded va logout-cleaned, lekin forensic hardening hali alohida audit talab qiladi

## PQC ga O'tishdan Oldin

PQC dan oldin quyidagilar barqaror bo'lishi kerak:

1. private chat lifecycle
2. group key lifecycle
3. key update strategy
4. user-visible security UX

Keyin hybrid model:

1. `X25519`
2. `ML-KEM`
3. KDF -> final shared key

## Amaliy Xulosa

Hozirgi loyiha demo encrypt bosqichidan chiqdi va haqiqiyroq E2EE foundationga o'tdi.

Lekin bu hali:

- Signal darajasidagi himoya emas
- PQC emas
- audit-complete product emas

Shunga qaramay, endi keyingi bosqichlarni qurish uchun yetarli tayanch bor.
