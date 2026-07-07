# E2EE Foundation Status

Bu hujjat hozirgi kriptografik foundation qayergacha kelganini va hali qayerlari kuchsiz ekanini amaliy tarzda jamlaydi.

## Hozir Nima Ishlaydi

### Private chat

1. Har device local `identity key pair` yaratadi
2. Public key login yoki device sync vaqtida backendga yuboriladi
3. Yangi private chat xabari bitta stabil `enc:v1` formatida encrypt qilinadi
4. Payload serverda `enc:v1:*` ko'rinishida saqlanadi
5. Self-sent encrypted payload uchun local plaintext cache bor, shu sabab yuborgan xabar history reload'da ham ko'rinadi
6. Oldin verified bo'lgan peer key o'zgarsa private send verify qilinmaguncha bloklanadi
7. Plaintext payload cache bounded bo'lib saqlanadi va logout paytida tozalanadi
8. Eski `x25519:*`, `hybrid:*`, `session:v1` tarixiy payloadlari uchun backward-compat decrypt qatlami saqlangan

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
5. full PQC trust-center UX

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
- private chat stabil yagona payload formati: `ha`
- private chat legacy payload backward compatibility: `ha`
- verified key change bo'lsa private send guard: `ha`
- bounded plaintext cache cleanup on logout: `ha`
- self-sent encrypted history readability: `ha`
- private key verification va key change warning foundation: `ha`
- group chat client-side key wrapping: `ha`
- group key full-device coverage enforcement: `ha`
- production-grade messenger security: `yo'q`

## Eng Katta Hali Qolgan Kamchiliklar

1. Private chat hozir stabil ishlash uchun soddalashtirilgan, lekin hali true modern E2EE transport emas
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

Hozirgi loyiha avval stabil, platformalararo bir xil ishlaydigan ciphertext transportni saqlab turadi.

Lekin bu hali:

- Signal darajasidagi himoya emas
- PQC emas
- audit-complete product emas

Shunga qaramay, endi keyingi bosqichlarni qurish uchun yetarli tayanch bor.
