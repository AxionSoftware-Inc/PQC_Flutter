# PQC Chat App Architecture

Bu hujjat `PQC Chat` ilovasi uchun tavsiya etilgan yuqori darajadagi arxitekturani tasvirlaydi. Maqsad: oddiy chat funksiyalarini keyinchalik post-quantum cryptography (`PQC`) bilan kengaytirish mumkin bo'lgan, bosqichma-bosqich rivojlanuvchi tizim qurish.

## 1. Maqsad

Ilova quyidagilarni ta'minlashi kerak:

1. Foydalanuvchi ro'yxatdan o'tishi va kirishi.
2. 1:1 chat va keyinchalik guruh chat.
3. Xabarlarni serverda oddiy matn holatida saqlamaslik.
4. Xabarlar uchun end-to-end encryption (`E2EE`) qo'llash.
5. Kalit almashinuvida post-quantum algoritmlardan foydalanish.
6. Key rotation, device management va key verification kabi xavfsizlik funksiyalarini qo'llab-quvvatlash.

## 2. Arxitektura Tamoyillari

1. `Security first` - kriptografiya ilovaning markazida bo'ladi.
2. `Layered design` - UI, domain, data va crypto qatlamlari ajratiladi.
3. `Replaceable crypto` - algoritmlar keyinchalik almashtirilishi mumkin bo'lgan modul sifatida yoziladi.
4. `Minimize trust` - server faqat transport va sinxronizatsiya uchun ishlatiladi.
5. `Incremental delivery` - avval oddiy chat, so'ng E2EE, so'ng PQC.

## 3. Yuqori Darajadagi Komponentlar

### 3.1 Flutter Client

Client ilovaning barcha UI va biznes oqimini boshqaradi.

Mas'uliyatlar:

1. Login va signup ekranlari.
2. Chat ro'yxati va chat oynasi.
3. Local state boshqaruvi.
4. Xabarlarni encrypt/decrypt qilish uchun crypto layer bilan ishlash.
5. Local cache va offline support.

### 3.2 Application Backend

Backend kriptografiyani bajarmaydi, asosan transport va autentifikatsiya uchun xizmat qiladi.

Mas'uliyatlar:

1. User authentication.
2. Device registration.
3. Message delivery.
4. Push notification metadata.
5. Public key / device key distribution.
6. Read receipts, typing indicators, presence.

### 3.3 Crypto Layer

Bu qatlam eng muhim qism.

Mas'uliyatlar:

1. Stable message encryption/decryption.
2. Identity key storage.
3. Future key agreement modules.
4. Key rotation.
5. Ratchet yoki forward secrecy mexanizmlari.

Bu qatlam ilovaning qolgan qismidan mustaqil bo'lishi kerak.

### 3.4 Local Secure Storage

Telefon ichidagi maxfiy ma'lumotlar xavfsiz saqlanadi.

Saqlanadigan narsalar:

1. Identity private key.
2. Session state.
3. Cached chat metadata.
4. Draft messages.

Saqlanmaydigan narsalar:

1. Plaintext message history.
2. Private keys ochiq ko'rinishda.

## 4. Tavsiya Etilgan Layer Strukturasi

### 4.1 Presentation Layer

UI, ekranlar, widgetlar va user interaction.

Misollar:

1. `LoginPage`
2. `ChatListPage`
3. `ChatPage`
4. `SettingsPage`
5. `SecurityVerificationPage`

### 4.2 Application Layer

Use case'lar va state management.

Misollar:

1. `SendMessageUseCase`
2. `LoadChatsUseCase`
3. `RegisterDeviceUseCase`
4. `VerifyContactKeyUseCase`
5. `RotateKeysUseCase`

Amaliy prototipda bunga yaqin bo'lgan orchestration komponentlari:

1. `ChatRepository`
2. `RoutedChatCipherService`
3. `PrivateConversationSecurityCoordinator`

### 4.3 Domain Layer

Business model va interfeyslar.

Asosiy entity'lar:

1. `User`
2. `Device`
3. `Conversation`
4. `Message`
5. `CryptoSession`
6. `IdentityKey`

Asosiy abstraksiyalar:

1. `AuthRepository`
2. `ChatRepository`
3. `CryptoRepository`
4. `KeyStoreRepository`

### 4.4 Data Layer

API, local database va repository implementation.

Mas'uliyatlar:

1. Remote API bilan ishlash.
2. Local cache.
3. DTO va model mapping.
4. Repository implementations.

## 5. Crypto Arxitekturasi

### 5.1 Asosiy G'oya

PQC chat uchun ikki bosqichli model tavsiya etiladi:

1. `Identity layer` - foydalanuvchi va device identifikatsiyasi.
2. `Session layer` - har bir suhbat uchun ephemeral session key.

### 5.2 Hozirgi Amaliy Yondashuv

Hozirgi ishlab turgan yondashuv:

1. Private chat uchun aktiv yozish formati ishlatiladi: `pqc:v1`
2. Private payload `ML-KEM-768` + `AES-GCM` + `ML-DSA-65` modelida ishlaydi
3. Group chat uchun `group:v1` payload va `group-wrap:pqc:v1` envelope ishlatiladi
4. Eski klassik payloadlar endi aktiv write path emas

Bu yondashuv platformalararo barqarorlikni tiklaydi va Flutter kod bazasini bir xil saqlab turadi.

Shu sabab crypto qatlam algoritmga qattiq bog'lanmasligi kerak. Hozirgi tavsiya:

1. conversation oqimi `ChatCipherAlgorithm` kabi pluggable interfeys orqali ishlaydi
2. private trust policy alohida coordinator'da turadi
3. aktiv private transport va legacy decrypt transport alohida implementation bo'ladi
4. keyin kerak bo'lsa yangi PQC/private transport shu interfeys ostida qayta kiritiladi

### 5.3 Tavsiya Etiladigan Crypto Flow

1. User device o'z identity key'ini yaratadi.
2. Public key serverga yuboriladi.
3. Private chat uchun PQC KEM orqali content key wrapping ishlatiladi.
4. Group chat uchun alohida PQC wrapped-key oqimi ishlatiladi.
5. Payload integrity uchun device-level PQC signature ishlatiladi.

### 5.4 Xavfsizlik Talablari

1. Private key hech qachon serverga yuborilmaydi.
2. Plaintext xabar serverda saqlanmaydi.
3. Transport doim TLS orqali ishlaydi.
4. Local storage encrypt bo'ladi.
5. Key verification uchun user-friendly fingerprint UI bo'ladi.

## 6. Network Flow

### 6.1 Auth Flow

1. User ro'yxatdan o'tadi.
2. Backend session token beradi.
3. Client device registration qiladi.
4. Device public key va metadata sync qilinadi.

### 6.2 Message Flow

1. Sender xabar yozadi.
2. Client session key bilan encrypt qiladi.
3. Backend faqat ciphertext yetkazadi.
4. Receiver ciphertext ni oladi.
5. Client local session key bilan decrypt qiladi.

### 6.3 Key Sync Flow

1. Yangi device qo'shiladi.
2. Device public key ro'yxatdan o'tadi.
3. Existing device'lar alert oladi.
4. User verification tasdiqlaydi.

## 7. Database / Storage Model

### 7.1 Remote Data

Backendda quyidagi data bo'lishi mumkin:

1. User profile.
2. Device registry.
3. Conversation metadata.
4. Encrypted messages.
5. Delivery receipts.

### 7.2 Local Data

Client ichida:

1. Session state.
2. Encrypted message cache.
3. Contact fingerprints.
4. User preferences.

## 8. Tavsiya Etiladigan Folder Structure

`lib/` ichida quyidagi struktura mos keladi:

```text
lib/
  app/
  core/
    crypto/
    network/
    storage/
    utils/
  features/
    auth/
    chat/
    contacts/
    settings/
    security/
  shared/
    widgets/
    theme/
    models/
```

Izoh:

1. `core/crypto` - barcha kripto helper va interfeyslar.
2. `features/` - feature-based modular design.
3. `shared/` - qayta ishlatiladigan widget va util'lar.

## 9. Tavsiya Etiladigan Tech Stack

Bu faqat arxitektura uchun tavsiya, hali implementatsiya emas.

1. Flutter
2. State management uchun `Riverpod` yoki `Bloc`
3. Local storage uchun `Isar`, `Drift` yoki `Hive`
4. Secure storage uchun platform secure enclave / keystore
5. Transport uchun REST + WebSocket yoki SSE
6. Backend uchun Node.js, Go yoki Rust

## 10. Bosqichma-Bosqich Reja

### Bosqich 1 - MVP Chat

1. Auth.
2. Contact list.
3. 1:1 chat.
4. Plain message transport.
5. Local cache.

### Bosqich 2 - E2EE

1. Client-side encryption.
2. Key storage.
3. Message integrity.
4. Device verification.

### Bosqich 3 - PQC Integration

1. PQC key exchange.
2. Hybrid session setup.
3. Key rotation.
4. Multi-device support.

### Bosqich 4 - Hardening

1. Audit logs.
2. Abuse prevention.
3. Rate limiting.
4. Secure backup strategy.

## 11. Risklar

1. Kriptografiyani noto'g'ri implementatsiya qilish.
2. Device sync murakkabligi.
3. Multi-device session management.
4. UX va security balansini topish.
5. PQC kutubxonalarining maturity darajasi.

## 12. Xulosa

Eng to'g'ri yo'l - avval minimal chat platforma, keyin E2EE, undan keyin PQC qo'shish. Shunda loyiha nazoratli, test qilinadigan va kengaytiriladigan bo'lib qoladi.
