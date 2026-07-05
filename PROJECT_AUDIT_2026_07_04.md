# Project Audit 2026-07-04

Bu fayl hozirgi ishchi holatni, topilgan xatolarni, yechilgan muammolarni va keyingi qadamlarni bir joyga jamlaydi.

## Hozirgi Ishchi Holat

Prototipda quyidagilar real tekshiruvdan o'tdi:

1. Mac va Android / planshet login qila oladi
2. Bir xil serverga ulanadi
3. Private chat ikki tomondan ishlaydi
4. `General Group` group chat ishlaydi
5. Server plaintext emas, ciphertext saqlaydi

## Ish paytida topilgan muhim muammolar

### 1. Android release APK network permission

Muammo:

- release buildda `INTERNET` permission yo'q edi
- debug ishlashi mumkin, release esa `SocketException` berardi

Yechim:

- [AndroidManifest.xml](/Users/macbookpro/Documents/PQC%20Chat%20app/android/app/src/main/AndroidManifest.xml) ga `uses-permission android:name="android.permission.INTERNET"` qo'shildi

### 2. Server non-standard port

Muammo:

- app `:8020` ga to'g'ridan urardi
- ayrim qurilmalar / tarmoqlarda bu noqulaylik berdi

Yechim:

- serverda `nginx` orqali `/api` reverse proxy qo'yildi
- app default URL `http://91.108.121.56/api` ga o'tkazildi

### 3. Server DB wrong target

Muammo:

- ishlayotgan service `shared/db.sqlite3` dan o'qirdi
- migratsiya noto'g'ri boshqa faylga tushib qolgan payt bo'ldi
- natijada Django HTML xato sahifasi qaytib, client `FormatException` berdi

Yechim:

- haqiqiy DB yo'liga migratsiya qayta bosildi
- client non-JSON response'ni ham foydali xatoga aylantiradigan himoya oldi

### 4. Group chat send failure

Muammo:

- avvalgi smoke-testdan qolgan fake userlar group ichida qolgan
- ularning `x25519` public key'i yaroqsiz edi
- group key tarqatish paytida shu device'lar sabab yiqilish yuz berdi

Yechim:

- serverdan fake userlar tozalandi
- backend `x25519` public key uchun validatsiya oldi
- client ham yaroqsiz public key'larni usable device deb hisoblamaydi

## Hozirgi Arxitektura Xulosasi

To'g'ri ishlayotgan qatlamlar:

1. `device identity`
2. `device-bound login`
3. `private X25519 encryption`
4. `group envelope distribution`
5. `minimal polling chat`
6. `manual key verification`
7. `key change warning`
8. `basic group rekey trigger`
9. `private static + ephemeral message key derivation`
10. `private one-time prekey bootstrap foundation`

Hali sodda yoki vaqtinchalik qolgan qatlamlar:

1. polling o'rniga realtime yo'q
2. secure storage barcha platformada bir xil kuchli emas
3. group rekey strategiyasi basic, lekin endi participant/device key signature o'zgarsa trigger bo'ladi
4. multi-device user modeli hali to'liq emas

## Hozirgi Kamchiliklar

### Security

1. To'liq ratcheted forward secrecy yo'q
2. Ratchet yo'q
3. Group verification UX hali sodda
4. Local plaintext exposure bo'yicha forensic audit hali to'liq emas
5. macOS secret storage hali production-grade emas

### Product

1. UI juda minimal
2. message status yo'q
3. attachments yo'q
4. offline queue yo'q
5. chat pagination yo'q

### Engineering

1. Flutter test coverage hali past
2. Crypto unit testlar keng emas
3. deploy automation yo'q
4. environment config hali sodda

## Hozirgi Tavsiya Etiladigan Yo'nalish

Eng to'g'ri tartib:

1. regression testlarni kengaytirish
2. current E2EE modelni mustahkamlash
3. forward secrecy / session lifecycle ni yaxshilash
4. group verification UX ni kuchaytirish
5. keyin hybrid PQC qatlamiga o'tish

## PQC ga o'tishdan oldin minimum tayyorgarlik

PQC dan oldin quyidagilar bo'lishi kerak:

1. private chat E2EE to'liq ishonchli bo'lishi
2. group key lifecycle tushunarli bo'lishi
3. device key change flow yozilgan bo'lishi
4. audit va debug mexanizmlari tayyor bo'lishi

Shundan keyin:

1. klassik `X25519`
2. PQC `ML-KEM`
3. hybrid KDF

qatlamiga o'tish osonlashadi.
