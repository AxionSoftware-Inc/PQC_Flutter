# Encryption Storage Modes

Bu fayl xabarlar turli bosqichlarda serverda va clientda qanday ko'rinishda bo'lishini tushuntiradi.

## 1. Oldingi Demo Qatlam

Oldingi demo qatlam:

- payload `enc:v1:*`
- kalit `conversation-derived secret`
- maqsad: server plaintextni ko'rmasin

Bu foydali oraliq bosqich edi, lekin true E2EE emas edi.

## 2. Hozirgi Private Chat Ko'rinishi

Format:

```text
x25519:v4:<sender-device-id>:<sender-static-public-key-base64>:<sender-ephemeral-public-key-base64>:<recipient-prekey-id>:<nonce-base64>:<ciphertext-base64>:<mac-base64>
```

Fallback:

```text
x25519:v3:<sender-device-id>:<sender-static-public-key-base64>:<sender-ephemeral-public-key-base64>:<nonce-base64>:<ciphertext-base64>:<mac-base64>
```

Ma'nosi:

1. ikki device orasida `X25519 shared secret` olinadi
2. jo'natuvchining static public key'i payload ichida boradi
3. har xabar uchun ephemeral public key payload ichida boradi
4. recipient prekey id payload ichida boradi
5. static-secret + ephemeral-secret + prekey-secret kombinatsiyasidan kalit derive qilinadi
6. server ciphertextni saqlaydi

Server nuqtai nazaridan saqlanadigan narsa:

```text
conversation_id=...
sender_id=...
body='x25519:v1:...'
```

## 3. Hozirgi Group Chat Ko'rinishi

Format:

```text
group:v1:<key_id>:<nonce-base64>:<ciphertext-base64>:<mac-base64>
```

Group key envelope formati:

```text
group-wrap:v1:<nonce-base64>:<ciphertext-base64>:<mac-base64>
```

Ma'nosi:

1. group secret clientda yaratiladi
2. har target device uchun wrap qilinadi
3. server `ConversationKeyEnvelope` saqlaydi
4. xabar esa alohida `group:v1:*` bo'lib saqlanadi

## 4. Serverda Plaintext Qayerda Qolishi Mumkin

Normal oqimda plaintext quyida qolmasligi kerak:

1. message DB body ichida
2. conversation preview ichida
3. normal server log ichida

Lekin plaintext hali quyida bo'lishi mumkin:

1. client memory
2. ekran render holati
3. debug print bo'lsa local log
4. future local cache noto'g'ri yozilsa

## 5. To'liqroq E2EE Bosqichi

Keyingi kuchaytirilgan bosqichda:

1. key verification qo'shiladi
2. key rotation qo'shiladi
3. local encrypted cache policy aniq bo'ladi
4. group rekey siyosati mustahkamlanadi

## 6. PQC / Hybrid Bosqich

Oxirgi bosqichda:

1. klassik `X25519` saqlanadi
2. PQC `ML-KEM` yoki shunga yaqin KEM qo'shiladi
3. ikkalasidan hybrid shared secret olinadi
4. message payload tashqi ko'rinishda o'xshash qolishi mumkin
5. farq key schedule ichida bo'ladi

Masalan:

```json
{
  "algorithm": "aes-gcm-256",
  "key_schedule": "hybrid-x25519-mlkem768",
  "ciphertext": "...",
  "nonce": "...",
  "mac": "..."
}
```

## 7. Eng Muhim Xulosa

Bugungi real holat:

1. server plaintext storage'dan chiqdi
2. private chat real X25519 foundationga o'tdi
3. group chat wrapped key modeliga o'tdi
4. manual verification bor, lekin hali full safety-number UX emas
5. hali ratchet yo'q
6. Android secret storage endi secure storage primary
7. device prekey batch clientda saqlanadi va serverga sync qilinadi
8. PQC hali keyingi bosqich
