# Technical Status

Bu hujjat loyiha bugungi holatda texnik jihatdan qayerga kelganini jamlaydi. Maqsad: "nima ishlaydi", "nima hali zaif", va "production uchun yana nima kerak" degan savollarga bitta joydan javob berish.

## 1. Qisqa Xulosa

Hozirgi holatda loyiha:

1. private chat uchun ishlaydigan PQC-based secure messaging core'ga ega
2. group chat uchun PQC wrapped group key foundation'ga ega
3. backend deploy va Android build bilan amalda ishlatilgan
4. test bilan tasdiqlangan

Lekin hali:

1. final production secure messenger darajasiga chiqmagan
2. full forward secrecy / ratchet yo'q
3. realtime hali polling bilan almashtirilmagan
4. trust-center UX va audit/ops qatlami minimal

## 2. Hozir Ishlaydigan Yadro

### 2.1 Auth va device binding

1. foydalanuvchi ism bilan login qiladi
2. har qurilma local persistent `device_id` oladi
3. backend device'ni user bilan bog'laydi
4. device public key directory serverda saqlanadi

### 2.2 Private chat

1. private payload formati `pqc:v1`
2. content plaintext `AES-GCM` bilan shifrlanadi
3. content key peer qurilmalar uchun `ML-KEM-768` bilan wrap qilinadi
4. payload `ML-DSA-65` bilan imzolanadi
5. sender ham, receiver ham o'ziga tegishli wrapped key orqali decrypt qila oladi
6. imzo verify bo'lmasa payload reject qilinadi
7. private send endi enterprise-ready va verified peer bo'lmaguncha o'tmaydi

### 2.3 Group chat

1. group secret client tomonda yaratiladi
2. har participant device uchun alohida PQC wrapped envelope yaratiladi
3. envelope formati `group-wrap:pqc:v1:*`
4. group key wrap ham `ML-KEM-768` + `ML-DSA-65` bilan ishlaydi
5. usable device coverage to'liq bo'lmasa send bloklanadi

### 2.4 Backend

1. Django backend ciphertext va metadata tashiydi
2. `91.108.121.56` serverda live deploy qilingan
3. health endpoint ishlaydi
4. login/device sync endpointlari PQC kalitlarni qabul qiladi va qaytaradi

### 2.5 Build va deploy

1. Flutter Android release APK build ishlaydi
2. production API default URL ishlaydi
3. serverga deploy qilingan build production backend bilan mos

## 3. PQC Haqiqatan Ishlayaptimi

Ha.

Koddagi aktiv PQC algoritmlar:

1. `ML-KEM-768`
2. `ML-DSA-65`

Amaliy dalillar:

1. `DevicePqcKeyService.algorithmName = ml-kem-768`
2. `DevicePqcSigningKeyService.algorithmName = ml-dsa-65`
3. private payload testida:
   - signing public key `1952` bayt
   - KEM ciphertext `1088` bayt
   - signature taxminan `3309` bayt
4. plaintext payload ichida ko'rinmaydi

Muhim aniqlik:

1. xabar matnining o'zi to'g'ridan-to'g'ri PQC blok-shifr bilan shifrlanmaydi
2. PQC bu yerda key encapsulation va signature qatlamida ishlatiladi
3. message body esa `AES-GCM` bilan shifrlanadi

Bu normal va to'g'ri arxitektura.

## 4. Arxitektura Bahosi

Hozirgi arxitektura endi oldingi "prototip chat" holatidan chiqqan.

Kuchli tomonlari:

1. private va group crypto oqimlari ajratilgan
2. PQC key service va signing service alohida
3. server ciphertext carrier rolida qolgan
4. backend va Flutter o'rtasida payload contract barqarorlashgan
5. production serverga real deploy qilingan

Zaif tomonlari:

1. polling hali realtime o'rnida turibdi
2. macOS secure storage hali Android darajasida emas
3. drift-based full local DB source-of-truth hali yakunlanmagan
4. ops monitoring, alerting, audit trail minimal

## 4.1 Oxirgi Hardening Qatlami

Bu pass davomida quyidagilar qattiqlashtirildi:

1. secure storage ishlamasa fallback secretlar plain text emas, wrapped formatda saqlanadi
2. legacy plain fallback qiymatlar o'qilish paytida avtomatik protected formatga migratsiya qilinadi
3. backend private chat uchun plain text body qabul qilmaydi, faqat `pqc:v1`
4. backend group chat uchun plain text body qabul qilmaydi, faqat `group:v1`
5. backend group key envelope sync uchun faqat PQC algorithm va PQC envelope format qabul qiladi
6. group envelope target coverage server tomonda ham PQC device registry bilan tekshiriladi
7. local message/outbox plaintext endi protected at-rest ko'rinishda saqlanadi
8. private send endi verified enterprise trust talab qiladi
9. secure storage/key state yo'qolib qayta yaralsa app endi o'sha qurilmani avtomatik yangi installation sifatida aylantiradi
10. outbox clear endi butun chat tarixini o'chirmaydi, faqat queued message'larni tozalaydi
11. conversation va message sync bo'sh local state holatida full-fetch fallback bilan tiklanadi

## 5. Asosiy Kamchiliklar

Yadro ishlaydi, lekin quyidagilar hali qolgan:

1. full forward secrecy yo'q
2. double ratchet yo'q
3. message rekey/rotation policy hali chuqur emas
4. multi-device trust UX minimal
5. attachment encryption hali keyingi faza
6. websocket realtime hali yo'q
7. tenant hardening va role policy hali boshlang'ich bosqichda
8. HTTPS/domain/cert ops hardening alohida yakunlanishi kerak

## 5.1 Persistence Kontrakti

Bu bo'lim eng amaliy savolga javob beradi: "nima eslab qolinadi, nima o'chib ketishi mumkin, nima ataylab tozalanadi".

### Qurilma identity

1. app har installation uchun local persistent `device_id` saqlaydi
2. `device_id` odatda o'zgarmaydi
3. agar secure storage/key state yo'qolib, ayni `device_id` ostida yangi keylar paydo bo'lsa:
   - app bunu "shu device buzilib qayta yaralgan" deb qabul qiladi
   - eski `device_id`ni ushlab turmaydi
   - yangi installation identity yaratadi
4. bu qaror key-change shovqinini kamaytirish uchun kiritilgan

### Device keylar

1. `X25519`, `ML-KEM-768`, `ML-DSA-65` keylar local secret store'da saqlanadi
2. secure storage ishlamasa wrapped fallback storage ishlatiladi
3. app jim holda eski keyni yangisiga almashtirib yubormasligi kerak
4. key material haqiqatan almashsa, bu endi yangi installation sifatida ko'riladi

### Session

1. session token localda saqlanadi
2. app qayta ochilganda session restore qilinadi
3. remembered display name saqlanadi
4. server o'zgarsa session va outbox reset bo'ladi

### Chatlar va xabarlar

1. `conversations` va `messages` Drift database'da saqlanadi
2. `Chats` tab local DB + server sync orqali tiklanadi
3. local preview/message plaintext protected at-rest ko'rinishda saqlanadi
4. app qayta ishga tushganda chat list va history qayta tiklanishi kerak
5. agar local DB bo'sh, lekin sync marker qolib ketgan bo'lsa:
   - app full-fetch fallback qiladi
   - chat list yoki message history yo'qolib qolmasligi kerak

### Outbox

1. pending private/group sendlar local queue'da saqlanadi
2. queue retry state bilan birga saqlanadi
3. outbox clear faqat queued itemlarni tozalaydi
4. outbox clear endi chat history'ni o'chirmaydi

### Trust state

1. verified fingerprint holati local DB'da saqlanadi
2. peer key haqiqatan o'zgarsa `key changed` chiqadi
3. ayni device ostida storage buzilib key qayta yaralgan holat esa endi imkon qadar yangi installationga aylantiriladi

## 5.2 Hozirgi Stability Qoidalari

Kelajakdagi o'zgarishlar shu qoidalarga bo'ysunishi kerak:

1. private payload formatini o'zgartirish production oqimida bir fazada qilinmaydi
2. avvalgi write formatni almashtirishdan oldin live mixed-device sinov bo'lishi kerak
3. `OutboxStore.clear()` hech qachon chat history'ni o'chirmasligi kerak
4. `fetchConversations` va `fetchMessages` bo'sh local state uchun full-fetch fallback'ga ega bo'lishi kerak
5. device key lifecycle markaziy service orqali boshqarilishi kerak, tarqoq joylarda emas
6. trust state va chat persistence bir-biridan tasodifan tozalanmasligi kerak

## 6. Production Readiness Bahosi

### 6.1 Nima uchun "yadro tayyor" deyish mumkin

1. private chat ishlaydi
2. group chat ishlaydi
3. private payload PQC bilan ishlaydi
4. group key wrap PQC bilan ishlaydi
5. live backend deploy ishlaydi
6. Android build ishlaydi
7. smoke-level test va regression testlar bor

### 6.2 Nima uchun hali "to'liq production tayyor" emas

1. secure messenger sifatida full ratchet yo'q
2. forensic/storage hardening hali to'liq emas
3. trust UX hali korporativ darajaga yetmagan
4. load/ops/observability hali minimal
5. realtime va offline source-of-truth arxitekturasi hali yakunlanmagan

## 7. Hozirgi To'g'ri Xulosa

Eng to'g'ri gap:

1. `messaging core ishlaydi`
2. `PQC private va group foundation ishlaydi`
3. `MVP/B2B pilot uchun asos tayyor`
4. `final production secure messenger holatiga hali chiqmagan`

Yana ham aniqroq gap:

1. private va group chat yadro oqimi ishlayapti
2. persistence va key lifecycle oldingidan ancha barqaror
3. eng ko'p regressiya bergan joylar endi markazlashtirildi
4. lekin private multi-device transportni yana alohida ehtiyotkor fazada qilish kerak

## 8. Keyingi Texnik Bosqichlar

Productionga yaqinlashish uchun tavsiya etilgan tartib:

1. local DB va outbox/source-of-truth qatlamini yakunlash
2. websocket realtime qo'shish
3. trust-center va verification UX'ni kuchaytirish
4. key rotation / membership epoch / rekey siyosatini kuchaytirish
5. attachment metadata + upload foundation
6. attachment binary encryption
7. observability, audit, backup, restore, ops checklist
