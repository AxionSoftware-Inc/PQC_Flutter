# Encryption Storage Modes

Bu fayl xabarlar turli bosqichlarda serverda va clientda qanday ko'rinishda bo'lishini tushuntiradi.

> Eslatma: `v1` formatlari tarixiy demo qatlamiga tegishli. Hozirgi production
> contract `docs/release-profiles.md` bilan belgilanadi: V2 default, V2.5
> group-envelope migration profili, V3 esa capability-gated writer/reader.

## 1. Oldingi Demo Qatlam

Oldingi demo qatlam:

- payload `enc:v1:*`
- kalit `conversation-derived secret`
- maqsad: server plaintextni ko'rmasin

Bu foydali oraliq bosqich edi. Hozir aktiv write path endi bu emas.

## 2. Hozirgi Private Chat Ko'rinishi

Format:

```text
pqc:v2:<sender-device-id>:<signing-public-key>:<target-device-id>:...
```

Ma'nosi:

1. private chat uchun default payload formati `pqc:v2:`; V3 profile `pqc:v3:`
2. message body `AES-GCM` bilan shifrlanadi
3. content key self va peer device uchun `ML-KEM-768` bilan wrap qilinadi
4. payload `ML-DSA-65` bilan imzolanadi
5. server ciphertextni saqlaydi
6. macOS va Android bir xil yozish oqimini ishlatadi

Server nuqtai nazaridan saqlanadigan narsa:

```text
conversation_id=...
sender_id=...
body='pqc:v2:...'  # V3 profile: pqc:v3:...
```

## 3. Hozirgi Group Chat Ko'rinishi

Format:

```text
group:v2:<key_id>:<nonce-base64>:<ciphertext-base64>:<mac-base64>
```

Group key envelope formati:

```text
group-wrap:pqc:v2:<sender-device-id>:<signing-public-key>:<kem-ciphertext>:...
```

Ma'nosi:

1. group secret clientda yaratiladi
2. har target device uchun PQC wrap qilinadi
3. server `ConversationKeyEnvelope` saqlaydi
4. xabar esa alohida `group:v2:*` bo'lib saqlanadi; V3 profile `group:v3:*`

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

## 6. PQC Dalil O'lchamlari

Hozirgi payloadda ko'rinadigan asosiy o'lchamlar:

1. `ML-KEM-768` public key: `1184` bayt
2. `ML-KEM-768` ciphertext: `1088` bayt
3. `ML-DSA-65` public key: `1952` bayt
4. `ML-DSA-65` signature: bir necha kilobayt

Shu sabab payload oddiy kichik klassik format emas.

## 7. Eng Muhim Xulosa

Bugungi real holat:

1. server plaintext storage'dan chiqdi
2. private chat default `pqc:v2:` formatda ishlaydi, V3 esa capability orqali yoqiladi
3. group chat PQC wrapped key modelida ishlaydi; V2.5 envelope reader/writer alohida negotiate qilinadi
4. manual verification bor, lekin hali full safety-number UX emas
5. hali ratchet yo'q
6. Android secret storage endi secure storage primary
7. PQC endi keyingi bosqich emas, aktiv ishlayotgan qatlam
8. final production hardening esa hali keyingi bosqich
