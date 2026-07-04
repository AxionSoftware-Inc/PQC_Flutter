# E2EE Foundation Status

Bu hujjat realroq E2EE sari bugungi holatni, kamchiliklarni va keyingi qadamlarni qisqa emas, amaliy nuqtai nazardan yig'adi.

## Hozir nimalar qo'shildi

1. Har device uchun alohida `identity key pair` generatsiya qilish foundation'i qo'shildi.
2. Device private key client ichida saqlanadi.
3. Device public key backendga login vaqtida yuboriladi.
4. Backend har user uchun device registryni public key bilan saqlay oladi.

Asosiy fayllar:

- [device_key_service.dart](/Users/macbookpro/Documents/PQC%20Chat%20app/lib/core/device/device_key_service.dart:1)
- [auth_repository.dart](/Users/macbookpro/Documents/PQC%20Chat%20app/lib/features/auth/data/auth_repository.dart:1)
- [users/models.py](/Users/macbookpro/Documents/PQC%20Chat%20app/users/models.py:1)
- [users/views.py](/Users/macbookpro/Documents/PQC%20Chat%20app/users/views.py:1)

## Bu nima beradi

Bu bosqich hali to'liq E2EE emas, lekin juda muhim poydevor:

1. Har qurilma endi alohida kriptografik identifikatsiyaga ega bo'lishi mumkin.
2. Kelajakda private chat uchun real shared secret shu device key'lar asosida hosil qilinadi.
3. Group chat uchun group key distribution ham shu foundation ustiga quriladi.

## Hozirgi eng katta kamchiliklar

1. Xabarlar hali `real device-to-device session key exchange` bilan encrypt qilinmayapti.
2. Hozirgi message encryption hali demo darajada va app ichidagi static secretga suyanadi.
3. Private key secure storage'da saqlanmoqda, lekin undan foydalanib real E2EE session hali qurilmagan.
4. Group chat uchun shared group key management yo'q.
5. Device verification va fingerprint UI yo'q.
6. Forward secrecy yo'q.
7. Key rotation yo'q.

## Keyingi aniq qadamlar

### Qadam 1

Private chat uchun real session setup:

1. User list endpoint device public key'larini clientga beradi.
2. Private chat ochilganda sender receiver device public key'ini oladi.
3. Client tomonida `X25519` shared secret hosil qilinadi.
4. Message key shu shared secret'dan derive qilinadi.
5. Demo static secret message codec olib tashlanadi.

### Qadam 2

Private chat message envelope:

1. `ciphertext`
2. `nonce`
3. `mac`
4. `sender_device_id`
5. `key_algorithm`
6. `session_id` yoki `key_id`

### Qadam 3

Group chat uchun key distribution:

1. Group creator group key yaratadi.
2. Group key har participant device public key'i bilan wrapped bo'ladi.
3. Server wrapped group key'larni saqlaydi.
4. Har user o'z device private key'i bilan unwrap qiladi.

### Qadam 4

Key verification:

1. Har device public key fingerprint'i ko'rsatiladi.
2. User contact key'ni tasdiqlay oladi.
3. Key o'zgarsa ogohlantirish chiqadi.

### Qadam 5

Shundan keyin PQC / hybrid:

1. Klassik `X25519` bilan birga PQC KEM qo'shiladi.
2. Hybrid shared secret hosil qilinadi.
3. KDF orqali final session key olinadi.

## Hozirgi tavsiya

Eng to'g'ri navbat:

1. avval private chat uchun real X25519-based E2EE
2. keyin group key management
3. keyin verification
4. keyin hybrid PQC

Shu tartib bilan yursak, biz demo encryption'dan haqiqiyroq E2EE'ga kontrolli o'tamiz.

## 2026-07-03 Audit Natijasi

Server va client holatini amaliy tekshiruvda quyidagilar aniqlandi:

1. Serverdagi oxirgi xabarlar `x25519:v1` emas, `enc:v1` formatida saqlangan.
2. `mac` user'ga bog'langan `users_userdevice` yozuvida `identity_public_key` bo'sh edi.
3. Shu sabab private chat ham real `X25519` yo'liga o'tmagan, fallback demo encryption ishlagan.

Server DB'dan ko'rilgan real namunalar:

```text
(5, 2, 6, 'enc:v1:Uc81sCuaprmdNla/:3t/IPcdXlL65uHHeKAmQgEqOA5jHdJVD5auR:ZoLmWXGfoHQzmcEWOzFVgw==', '2026-07-03 15:47:39.923855')
(4, 2, 6, 'enc:v1:WRyLH7IRkJADEqwt:Xn47tNLAXPtsKZbaTZ6B3KQdt64=:QeIqEgViqkOJWcX2hJOVhg==', '2026-07-03 15:47:29.624033')
(3, 1, 6, 'enc:v1:C4252Swj8NzQ17Yl:GNF7ICuN7qgrCg==:FudYqiNkw7no55e87uKSOg==', '2026-07-03 15:47:16.856102')
```

Decrypt audit natijasi:

```text
group#1   -> yana salom
private#2 -> Qalaysan yaxshimisan
private#2 -> axvollaring yaxshimi asalim
```

Muhim xulosa:

1. Server plaintext saqlamayapti, ciphertext saqlayapti.
2. Lekin bu ciphertext hozircha demo conversation-derived kalit bilan ochildi.
3. Demak amalda `server-side plaintext hiding` bor, lekin hali `true device-to-device E2EE` yo'q.

## 2026-07-04 Hozirgi Amaliy Holat

Bugungi buildda oldingi eng katta kamchiliklar yopildi:

1. Private chat uchun yangi xabarlar endi `x25519:v1` formatida yuboriladi.
2. Private chat demo fallback bilan yuborilmaydi.
3. Session restore vaqtida ham device public key serverga qayta sync qilinadi.
4. Group chat uchun serverda `ConversationKeyEnvelope` saqlanadi.
5. Group key clientda yaratiladi, participant device public key'lari bilan wrapped qilinadi va serverga faqat wrapped ko'rinishda yuboriladi.

Asosiy yangi fayllar:

- [group_key_store.dart](/Users/macbookpro/Documents/PQC Chat app/lib/features/crypto/group_key_store.dart:1)
- [message_codec.dart](/Users/macbookpro/Documents/PQC Chat app/lib/features/crypto/message_codec.dart:1)
- [chat/models.py](/Users/macbookpro/Documents/PQC Chat app/chat/models.py:1)
- [chat/views.py](/Users/macbookpro/Documents/PQC Chat app/chat/views.py:1)

Server smoke test natijasi:

1. `POST /api/auth/login` ishladi
2. `POST /api/users/me/device` ishladi
3. `POST /api/conversations/{id}/keys` ishladi
4. `GET /api/conversations/{id}/keys` ishladi

Hali qolayotgan real cheklovlar:

1. Contact key verification UI yo'q
2. Key rotation yo'q
3. Forward secrecy yo'q
4. Group membership o'zgarsa rekey siyosati hali sodda
5. PQC hali qo'shilmagan
