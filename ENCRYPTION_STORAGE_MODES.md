# Encryption Storage Modes

Bu hujjat `PQC Chat` ilovasida xabarlar turli bosqichlarda qanday ko'rinishda saqlanishini tushuntiradi:

1. Hozirgi `demo encrypt` holati
2. Keyingi `to'liqroq E2EE` holati
3. Oxirgi `PQC / hybrid E2EE` holati

Hujjatga real serverdan olingan namunaviy log va storage ko'rinishlari ham kiritilgan.

## 1. Hozirgi Holat: Demo Encrypt

### 1.1 Maqsad

Hozirgi qatlamning maqsadi:

1. Server database ichida plaintext qolmasin
2. Backend preview ham plaintext bo'lmasin
3. Client message yuborish va o'qish oqimi saqlanib qolsin

Bu qatlam `production-grade E2EE` emas.

### 1.2 Qanday ishlaydi

Hozirgi implementatsiya:

1. Flutter client xabar yuborishdan oldin matnni encrypt qiladi
2. Kalit `app secret + conversation metadata` dan derive qilinadi
3. AES-GCM ishlatiladi
4. Server faqat ciphertext qabul qiladi
5. Qabul qiluvchi client shu conversation metadata bilan decrypt qiladi

Asosiy kod:

- [message_codec.dart](/Users/macbookpro/Documents/PQC%20Chat%20app/lib/features/crypto/message_codec.dart:1)

### 1.3 Serverda qanday saqlanadi

Serverdagi real database'dan olingan namunalar:

```text
(2, 2, 'mac', 'enc:v1:1LH8ezNP8BbxcpZ1:xVNPy62Otz8MmwU+0L7sD6V5EKiW:tDJzAW5Zf523HUcCHZoxwQ==', '2026-07-03 15:03:31.773120')
(1, 1, 'mac', 'enc:v1:7rEk/5odDbd9DLpm:GqqSvI5DcW6JDFrUXw==:qhLxTofwQFrA1coDyZzhHA==', '2026-07-03 15:03:11.714140')
```

Keyingi auditda ham shu ko'rinish tasdiqlandi:

```text
(5, 2, 6, 'enc:v1:Uc81sCuaprmdNla/:3t/IPcdXlL65uHHeKAmQgEqOA5jHdJVD5auR:ZoLmWXGfoHQzmcEWOzFVgw==', '2026-07-03 15:47:39.923855')
(4, 2, 6, 'enc:v1:WRyLH7IRkJADEqwt:Xn47tNLAXPtsKZbaTZ6B3KQdt64=:QeIqEgViqkOJWcX2hJOVhg==', '2026-07-03 15:47:29.624033')
(3, 1, 6, 'enc:v1:C4252Swj8NzQ17Yl:GNF7ICuN7qgrCg==:FudYqiNkw7no55e87uKSOg==', '2026-07-03 15:47:16.856102')
```

Shu audit vaqtida ochilgan plaintextlar:

```text
group#1   -> yana salom
private#2 -> Qalaysan yaxshimisan
private#2 -> axvollaring yaxshimi asalim
```

Izoh:

1. Bu ochilish real device private key bilan emas.
2. Bu ochilish `DemoCipherMessageCodec` ichidagi conversation-derived kalit bilan bo'ldi.
3. Demak hozirgi qatlam ciphertext beradi, lekin hali `true E2EE` darajasiga chiqmagan.

Conversation preview ham ciphertext bo'lib qoladi:

```text
(1, 'group', 'General Group', 'enc:v1:7rEk/5odDbd9DLpm:GqqSvI5DcW6JDFrUXw==:qhLxTofwQFrA1coDyZzhHA==')
(2, 'private', '', 'enc:v1:1LH8ezNP8BbxcpZ1:xVNPy62Otz8MmwU+0L7sD6V5EKiW:tDJzAW5Zf523HUcCHZoxwQ==')
```

### 1.4 Server loglarda nima ko'rinadi

Server loglarda plaintext xabar matni ko'rinmadi.

Ko'ringan servis loglari:

```text
Unauthorized: /api/users
Started pqc-chat.service - PQC Chat Django Backend.
Listening at: http://0.0.0.0:8020
```

Demak hozir:

1. Request yo'li ko'rinadi
2. Auth xatolari ko'rinadi
3. Plaintext message body loglarda ko'rinmadi

### 1.5 Device ichida nimalar bor

Hozirgi client tarafda:

1. Foydalanuvchi session token localda saqlanadi
2. Device identity localda saqlanadi
3. Plaintext ekranda render bo'ladi
4. Polling bilan backenddan ciphertext olinadi va clientda decrypt qilinadi

Muhim:

1. Agar app logga plaintext chiqarsa, bu xavf bo'ladi
2. Agar local cache keyin qo'shilsa, plaintext emas ciphertext cache qilish afzal
3. Hozir bu qism hali chuqur local forensic audit qilingan emas

### 1.6 Xavfsizlik darajasi

Afzalliklari:

1. Server DB plaintextni to'g'ridan-to'g'ri ko'rmaydi
2. Server preview ham plaintext emas
3. Oddiy test uchun privacy darajasi oldingidan ancha yaxshi

Cheklovlari:

1. Kalit client ichidagi umumiy secret bilan derive qilinadi
2. Reverse engineering bo'lsa ochilishi mumkin
3. Multi-device key management yo'q
4. Contact verification yo'q
5. True end-to-end trust model hali yo'q

Qisqa baho:

- `server-side plaintext hiding`: ha
- `strong E2EE`: yo'q
- `PQC`: yo'q

## 2. Keyingi Bosqich: To'liqroq E2EE

### 2.1 Maqsad

Bu bosqichda maqsad:

1. Har user yoki har device o'z private key'iga ega bo'lsin
2. Server kalitni bilmasin
3. Har private chat uchun shared secret clientlarda hosil bo'lsin
4. Group chat uchun alohida group key ishlasin

### 2.2 Qanday ishlashi kerak

Tavsiya etilgan oqim:

1. Har device identity key pair yaratadi
2. Public key serverda saqlanadi
3. Private key faqat device ichida qoladi
4. Private chat boshlanganda ikki device shared secret hosil qiladi
5. Xabar message key bilan encrypt qilinadi
6. Group chatda group session key clientlar o'rtasida tarqatiladi

### 2.3 Serverda qanday saqlanadi

Bu bosqichda serverda taxminan shunday data bo'ladi:

```json
{
  "conversation_id": 2,
  "sender_device_id": "device-a",
  "ciphertext": "base64(...)",
  "nonce": "base64(...)",
  "mac": "base64(...)",
  "algorithm": "aes-gcm-256",
  "key_id": "session-key-42"
}
```

Muhim farq:

1. Kalit derive qilish app secret'dan emas
2. Session key real client key exchange'dan hosil bo'ladi
3. Server ciphertextni saqlaydi, lekin uni ocholmaydi

### 2.4 Device ichida qanday saqlanadi

Device secure storage ichida:

1. Identity private key
2. Session state
3. Group key yoki wrapped group key
4. Optional encrypted local cache

Shunday bo'lishi kerak:

1. Plaintext history doimiy local DB'da turmasin yoki encrypt bo'lib tursin
2. Private key `SharedPreferences` ichida emas, secure storage ichida tursin
3. Session recovery ehtiyotkorlik bilan qilinsin

### 2.5 Loglarda nima ko'rinishi kerak

Ideal holat:

1. Request path ko'rinadi
2. Sender id yoki device id ko'rinishi mumkin
3. Ciphertext ko'rinishi mumkin
4. Plaintext logga chiqmasligi kerak

Masalan:

```text
POST /api/conversations/2/messages
sender_device=device-a
ciphertext_length=184
algorithm=aes-gcm-256
```

### 2.6 Xavfsizlik darajasi

Bu bosqichda:

1. Server plaintextni bilmaydi
2. Reverse engineering qilish qiyinlashadi
3. Kalitlar real client secretlarga bog'lanadi
4. Device compromise bo'lmasa xavfsizlik ancha yaxshilanadi

Lekin hali:

1. PQC emas
2. To'liq ratchet bo'lmasligi mumkin
3. Metadata hali ko'rinib turadi

## 3. Oxirgi Bosqich: PQC / Hybrid E2EE

### 3.1 Maqsad

Bu bosqichda maqsad:

1. Klassik E2EE'ni PQC bilan mustahkamlash
2. Future quantum attack'lar uchun tayyor bo'lish
3. Hybrid key exchange orqali transitionni xavfsiz qilish

### 3.2 Qanday ishlashi kerak

Tavsiya etilgan model:

1. Device klassik identity key va PQC public key yaratadi
2. Server ikkala public key'ni ham saqlaydi
3. Session boshlanganda klassik shared secret + PQC shared secret olinadi
4. Ikkalasi birga KDF orqali bitta session key'ga aylantiriladi
5. Message encryption shu derived session key bilan ishlaydi

### 3.3 Serverda qanday saqlanadi

Serverda ma'lumot taxminan shunday bo'ladi:

```json
{
  "conversation_id": 2,
  "sender_device_id": "device-a",
  "ciphertext": "base64(...)",
  "nonce": "base64(...)",
  "mac": "base64(...)",
  "algorithm": "aes-gcm-256",
  "key_schedule": "hybrid-x25519-mlkem768",
  "session_epoch": 7,
  "header": {
    "sender_key_id": "device-a-key-3",
    "receiver_key_id": "device-b-key-4"
  }
}
```

## 4. 2026-07-04 Dagı Real Implementatsiya

Hozirgi kod bazada amalda quyidagi saqlash ko'rinishlari ishlatiladi:

### 4.1 Private chat

Yangi private xabarlar:

```text
x25519:v1:<nonce-base64>:<ciphertext-base64>:<mac-base64>
```

Ma'nosi:

1. Message key ikki device orasidagi `X25519 shared secret`dan derive qilinadi
2. Server faqat ciphertext ko'radi
3. Server private keyni bilmaydi

### 4.2 Group chat

Yangi group xabarlar:

```text
group:v1:<key_id>:<nonce-base64>:<ciphertext-base64>:<mac-base64>
```

Serverda group key o'zi saqlanmaydi. Serverda faqat wrapped envelope saqlanadi:

```json
{
  "key_id": "uuid-like-key-id",
  "algorithm": "group-x25519-aesgcm-v1",
  "target_device_id": "device-b",
  "sender_device_id": "device-a",
  "wrapped_key": "group-wrap:v1:<nonce>:<ciphertext>:<mac>"
}
```

Ma'nosi:

1. Group secret clientda yaratiladi
2. Har device uchun alohida wrapped variant serverga yuboriladi
3. Device private key yordamida key unwrap qilinadi
4. Server plaintext group keyni ham bilmaydi

### 4.3 Legacy xabarlar

Eski test xabarlari hali quyidagi formatda ko'rinishi mumkin:

```text
enc:v1:<nonce-base64>:<ciphertext-base64>:<mac-base64>
```

Bu faqat eski yozishmalarni o'qish uchun decoderda qoldirilgan backward compatibility qatlamidir. Yangi xabarlar shu formatda yuborilmasligi kerak.

Server yana ham quyidagilarni ko'radi:

1. Public keys
2. Key identifiers
3. Conversation metadata
4. Ciphertext

Server ko'rmaydigan narsalar:

1. Plaintext
2. Private key
3. Final derived session key

### 3.4 Device ichida qanday saqlanadi

Device secure storage ichida:

1. Klassik private key
2. PQC private key
3. Ratchet state
4. Session epochs
5. Group sender key state

### 3.5 Loglarda nima ko'rinishi kerak

Ideal PQC/hybrid log:

```text
POST /api/conversations/2/messages
sender_device=device-a
key_schedule=hybrid-x25519-mlkem768
session_epoch=7
ciphertext_length=192
```

Ko'rinmasligi kerak:

1. Plaintext
2. Shared secret
3. Private key material
4. Session key bytes

### 3.6 Xavfsizlik darajasi

Bu bosqichda tizim:

1. Server-side plaintext exposure'ni kamaytiradi
2. Classical compromise ssenariylariga nisbatan kuchliroq bo'ladi
3. Quantum davrga tayyorroq bo'ladi

Lekin hatto bu bosqichda ham:

1. Device compromise bo'lsa plaintext olinishi mumkin
2. Screenshot, keyboard logger, malware kabi endpoint hujumlari qoladi
3. Metadata hanuz muhim xavf bo'lib qoladi

## 4. Uchtala Bosqichni Solishtirish

### 4.1 Server DB ko'rinishi

`Plaintext prototype`

```text
salom hammaga
salom
Salom asalom
```

`Current demo encrypt`

```text
enc:v1:7rEk/5odDbd9DLpm:GqqSvI5DcW6JDFrUXw==:qhLxTofwQFrA1coDyZzhHA==
enc:v1:1LH8ezNP8BbxcpZ1:xVNPy62Otz8MmwU+0L7sD6V5EKiW:tDJzAW5Zf523HUcCHZoxwQ==
```

`Future stronger E2EE`

```text
{
  "ciphertext": "...",
  "nonce": "...",
  "mac": "...",
  "key_id": "..."
}
```

`Future PQC / hybrid`

```text
{
  "ciphertext": "...",
  "nonce": "...",
  "mac": "...",
  "key_schedule": "hybrid-x25519-mlkem768",
  "session_epoch": 7
}
```

### 4.2 Server nimani bila oladi

`Plaintext prototype`

1. Hamma narsani

`Current demo encrypt`

1. Conversation metadata
2. Sender
3. Ciphertext
4. App logic reverse engineering qilinsa ochish ehtimoli bor

`Stronger E2EE`

1. Metadata
2. Ciphertext
3. Public keys
4. Plaintextni ocholmaydi

`PQC / hybrid`

1. Metadata
2. Ciphertext
3. Public keys
4. Key schedule turi
5. Plaintextni ocholmaydi

## 5. Hozirgi Xulosa

Hozir tizim oldingi plaintext variantdan yaxshiroq:

1. Serverda xabarlar oddiy matn emas
2. Preview ham oddiy matn emas
3. Loglarda plaintext ko'rinmadi

Lekin bu hali yakuniy xavfsizlik modeli emas.

Eng to'g'ri keyingi bosqich:

1. Real device-level key generation
2. Secure storage
3. Private chat uchun real shared secret
4. Group key management
5. Undan keyin hybrid PQC key exchange
