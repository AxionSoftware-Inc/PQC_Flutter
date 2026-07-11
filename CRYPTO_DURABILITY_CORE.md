# Crypto Durability Core

Bu hujjat chat ilovasidagi yangi `crypto durability core` nimani hal qilishi, nimani hali hal qilmasligi, va kelajakda bu yadroga qanday munosabatda bo'lish kerakligini tushuntiradi.

Maqsad bitta:

- UI / UX / branding o'zgarsa ham shifrlash kontrakti buzilmasin
- backend yoki app update bo'lsa ham eski xabarlar o'qilmay qolib ketmasin
- key lifecycle, reinstall, logout, restore, historical decrypt kabi holatlar bitta markaziy yadroda boshqarilsin

## 1. Qisqa Javob

Bugungi holatda:

1. `UI ni alohida o'zgartirish` oldingidan ancha xavfsiz
2. `Eski payload formatlarni o'qish kontrakti` ancha mustahkamlandi
3. `Historical decrypt` uchun keyset registry va encrypted backup foundation qo'shildi
4. lekin bu hali `100% product complete forever` degani emas

Eng muhim halol gap:

- faqat UI bilan ishlasangiz, crypto buzilish ehtimoli ancha past
- lekin `crypto wire format`, `key storage`, `backup/recovery`, `group key lifecycle` qismlariga noto'g'ri tegilsa baribir tarixiy decrypt buzilishi mumkin

## 2. Yangi Core Nimalardan Tashkil Topgan

Asosiy yangi qatlamlar:

1. `PayloadFormatRegistry`
2. `KeyMaterialRegistry`
3. `CryptoBackupService`
4. `CryptoCoreFacade`

Ularning vazifasi:

### `PayloadFormatRegistry`

- qaysi payload qaysi formatga tegishli ekanini biladi
- `pqc:v1`
- `group:v1`
- `group-wrap:pqc:v1`

Muhim qoida:

- eski decrypt support olib tashlanmaydi
- yangi format qo'shilsa eski format o'qilishi davom etishi kerak

### `KeyMaterialRegistry`

- current device keyset'ini versionlangan snapshot sifatida saqlaydi
- historical decrypt uchun eski keyset reference'larini saqlaydi
- reinstall yoki restore'dan keyin eski key materialni qayta bog'lashga yordam beradi

Muhim farq:

- oldin app asosan `current device key` bilan yashardi
- endi `current + historical keyset` tushunchasi paydo bo'ldi

### `CryptoBackupService`

- key material va kerakli crypto metadata'ni encrypted blob ko'rinishida export qiladi
- blob `recovery passphrase` bilan shifrlanadi
- boshqa device yoki reinstall'dan keyin import qilinishi mumkin

Muhim:

- server plaintext keyni ko'rmasligi mumkin
- restore uchun foydalanuvchining recovery passphrase'i kerak bo'ladi

### `CryptoCoreFacade`

- durability bilan bog'liq yuqori darajadagi entrypoint
- supported formatlar
- backup export/import
- historical decrypt capability tekshiruvi

## 3. Amalda Qanday Ishlaydi

### Oddiy UI update bo'lsa

1. ekranlar o'zgaradi
2. bubble, list, workspace UI, company branding o'zgaradi
3. crypto payload format o'zgarmasa eski xabarlar ochilishi davom etadi

Shuning uchun:

- faqat UI / UX / theme / navigation refactorlari endi ancha xavfsiz

### App update bo'lsa

1. eski decryptorlar kodda qolishi kerak
2. yangi writer format qo'shilishi mumkin
3. lekin eski payload support saqlanadi

Natija:

- to'g'ri yo'l bilan update qilinsa eski chat history `decrypt-error` bo'lib qolmasligi kerak

### Logout bo'lsa

1. session chiqadi
2. auth state tozalanadi
3. historical decrypt uchun zarur key registry saqlanib qolishi kerak

Natija:

- o'sha device ichida logout/login odatda history'ni o'qishga xalaqit bermasligi kerak

### App o'chirib qayta o'rnatilsa

Bu yerda 2 holat bor:

1. `backup bor`
   - encrypted backup import qilinadi
   - historical keyset tiklanadi
   - eski xabarlar yana o'qiladi

2. `backup yo'q`
   - secure storage ham yo'qolgan bo'lsa eski private/group decrypt kafolati yo'q
   - bu kriptografik cheklov, oddiy kod bilan sehrlab hal qilib bo'lmaydi

Shuning uchun eng muhim product qatlami:

- backup/recovery foydalanuvchi oqimi

### Boshqa yangi device'dan kirilsa

1. yangi device odatda yangi active keyset oladi
2. eski history'ni o'qish uchun:
   - old device kerak
   - yoki encrypted backup import kerak

Natija:

- yangi device `future write` uchun tayyor bo'lishi mumkin
- `past history` uchun esa recovery zarur bo'ladi

## 4. Hozir Qanday Mustahkamlandi

Bu pass'da aniq kuchaygan joylar:

1. private decrypt current device bilan cheklanib qolmay, historical keyset orqali ham tiklanishi mumkin
2. group history decrypt local historical group key bo'lsa yangi install'da ham ishlashi mumkin
3. key material registry current va tarixiy keylarni ajratadi
4. encrypted backup roundtrip testlandi
5. noto'g'ri recovery passphrase reject qilinishi testlandi

## 5. Hali Qolgan Cheklovlar

Bu yadro kuchaydi, lekin hali quyidagilar product darajasida tugamagan:

1. backup/recovery uchun user-facing UI yo'q
2. server-side encrypted backup storage flow hali yo'q
3. attachment encryption hali alohida durability contractga kirmagan
4. full ratchet / forward secrecy hali yo'q
5. historical decrypt statusni userga chiroyli ko'rsatish UX'i hali yo'q
6. device transfer / QR migration flow hali yo'q
7. backend-level retention / archival contract hali alohida rasmiylashtirilmagan

Demak:

- `core stronger`
- `product flow still incomplete`

## 6. Endi Nimalarga Bemalol Tegish Mumkin

Nisbatan xavfsiz joylar:

1. chat screen dizayni
2. company branding
3. workspace UX
4. theme, typography, layout
5. navigation
6. non-crypto presentation state

Bu o'zgarishlar odatda eski xabar decrypt'iga tegmasligi kerak.

## 7. Nimalarga Juda Ehtiyotkor Tegish Kerak

Eng xavfli joylar:

1. `message payload format`
2. `group envelope format`
3. `LocalSecretStore`
4. `KeyMaterialRegistry`
5. `DeviceStateManager` va key rotation logic
6. `GroupKeyStore` historical key behavior
7. private decrypt path

Qoidalar:

1. eski decryptorlarni o'chirmang
2. format prefixlarini bir kunda almashtirmang
3. storage key nomlarini sababsiz almashtirmang
4. backup blob formatini versionlamasdan o'zgartirmang
5. group key'ni faqat latest state sifatida saqlab qo'ymang

## 8. Hozirgi Eng To'g'ri Xulosa

Eng to'g'ri gap:

1. `yadro oldingidan ancha pishdi`
2. `faqat UI bilan ishlash oldingidan ancha xavfsiz`
3. `eski xabarlar update sabab yo'qolib qolish xavfi ancha kamaydi`
4. `backup/recovery product flow to'liq yakunlanmaguncha mutlaq kafolat tugamagan`

Yana ham aniqroq:

- siz hozirdan boshlab kompaniyalarga turli UI / UX bilan sotadigan oqimga yaqinlashdingiz
- lekin uzun yillik tarixiy decrypt kafolatini product darajasida yakunlash uchun backup/recovery UX va server-side encrypted backup oqimi ham qurilishi kerak

## 9. Developer Qoidalari

Kelajakda bu loyihada ishlaydiganlar uchun qat'iy qoidalar:

1. UI refactor crypto refactor emas
2. eski decrypt support hech qachon olib tashlanmaydi
3. yangi format qo'shilsa registry orqali qo'shiladi
4. key migration har doim backward-compatible bo'ladi
5. logout history decrypt metadata'ni tasodifan o'chirmaydi
6. reinstall recovery backup orqali tiklanadi
7. `decrypt-error` sababi typed tarzda farqlanadi: key missing, corrupted payload, unsupported format
8. historical group keylar `latest only` rejimiga qaytarilmaydi
9. recovery passphrase productning first-class qismi bo'lishi kerak
10. crypto qatlamiga har tegilganda regression tests majburiy ishlatiladi
