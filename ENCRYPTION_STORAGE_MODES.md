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
enc:v1:<nonce-base64>:<ciphertext-base64>:<mac-base64>
```

Ma'nosi:

1. private chat uchun bitta stabil payload formati ishlatiladi
2. kalit conversation-derived shared secret'dan olinadi
3. server ciphertextni saqlaydi
4. macOS va Android bir xil yozish oqimini ishlatadi

Server nuqtai nazaridan saqlanadigan narsa:

```text
conversation_id=...
sender_id=...
body='enc:v1:...'
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

## 6. Legacy Private Transport Compatibility

Eski private payloadlar hali o'qilishi mumkin:

1. `x25519:v4`
2. `x25519:v3`
3. `hybrid:v1`
4. `hybrid:v0`
5. `session:v1`

Lekin ular endi yangi yozish formati emas. Faqat backward-compatible decrypt qatlami sifatida saqlanadi.

## 7. PQC / Hybrid Bosqich

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

## 8. Eng Muhim Xulosa

Bugungi real holat:

1. server plaintext storage'dan chiqdi
2. private chat bitta stabil `enc:v1` formatga qaytdi
3. group chat wrapped key modeliga o'tdi
4. manual verification bor, lekin hali full safety-number UX emas
5. hali ratchet yo'q
6. Android secret storage endi secure storage primary
7. eski private transport formatlari faqat compatibility uchun qoldi
8. PQC hali keyingi bosqich
