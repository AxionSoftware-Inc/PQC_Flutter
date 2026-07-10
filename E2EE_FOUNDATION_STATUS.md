# E2EE Foundation Status

Bu hujjat hozirgi kriptografik foundation qayergacha kelganini va hali qayerlari kuchsiz ekanini amaliy tarzda jamlaydi.

## Hozir Nima Ishlaydi

### Private chat

1. Har device local `identity key pair` yaratadi
2. `ML-KEM-768` public key login yoki device sync vaqtida backendga yuboriladi
3. `ML-DSA-65` signing public key ham backendga yuboriladi
4. Yangi private chat xabari `pqc:v1` formatida encrypt qilinadi
5. Payload serverda PQC-wrapped ciphertext ko'rinishida saqlanadi
6. Self-sent encrypted payload uchun local plaintext cache bor, shu sabab yuborgan xabar history reload'da ham ko'rinadi
7. Oldin verified bo'lgan peer key o'zgarsa private send verify qilinmaguncha bloklanadi
8. Plaintext payload cache bounded bo'lib saqlanadi va logout paytida tozalanadi
9. Payload signature verify bo'lmasa decrypt reject qilinadi

### Group chat

1. Group secret clientda yaratiladi
2. Har participant device uchun alohida PQC wrapped key envelope yaratiladi
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
- private chat aktiv PQC payload formati: `ha`
- verified key change bo'lsa private send guard: `ha`
- bounded plaintext cache cleanup on logout: `ha`
- self-sent encrypted history readability: `ha`
- private key verification va key change warning foundation: `ha`
- private payload signature verify: `ha`
- group chat client-side PQC key wrapping: `ha`
- group key full-device coverage enforcement: `ha`
- production-grade messenger security: `yo'q`

## Eng Katta Hali Qolgan Kamchiliklar

1. Private chat hozir stabil ishlash uchun soddalashtirilgan, lekin hali true modern E2EE transport emas
2. Verification UX hali minimal
3. Group rekey policy endi device coverage qat'iy, lekin hali membership epoch / sender key darajasiga chiqmagan
4. Local plaintext cache bounded va logout-cleaned, lekin forensic hardening hali alohida audit talab qiladi

## Amaliy Xulosa

Hozirgi loyiha private va group oqimlarida aktiv PQC foundation bilan ishlayapti.

Lekin bu hali:

- Signal darajasidagi himoya emas
- audit-complete product emas

Shunga qaramay, endi keyingi bosqichlarni qurish uchun yetarli tayanch bor.
