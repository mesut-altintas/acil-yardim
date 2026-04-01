# AcilYardım — Kurulum Kılavuzu

## Ön Gereksinimler
- Flutter SDK (3.0+)
- Node.js 18+
- Firebase CLI (`npm install -g firebase-tools`)
- Twilio hesabı (trial veya paid)
- Google hesabı (Firebase için)

---

## 1. Firebase Projesi Oluştur

```bash
# Firebase CLI ile giriş yap
firebase login

# Proje kök dizinine git
cd acil_yardim

# Firebase'i başlat (Functions + Firestore + Auth seç)
firebase init
```

Seçenekler:
- ✅ Firestore
- ✅ Functions (Node.js, JavaScript)
- ✅ Emulators (Functions, Firestore, Auth)

---

## 2. Twilio Yapılandırması

```bash
# Twilio kimlik bilgilerini Firebase Config'e kaydet
firebase functions:config:set \
  twilio.sid="ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
  twilio.token="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
  twilio.phone="+1xxxxxxxxxx" \
  twilio.whatsapp="whatsapp:+14155238886"
```

> **Not:** `twilio.whatsapp` değeri Twilio Sandbox için `whatsapp:+14155238886` şeklindedir.
> Production'da kendi onaylı WhatsApp numaranızı kullanın.

---

## 3. Firebase Functions Deploy

```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

---

## 4. Flutter Yapılandırması

### google-services.json (Android)
Firebase Console → Proje Ayarları → Android uygulaması ekle
- Package name: `com.example.acil_yardim` (veya kendi paket adınız)
- `google-services.json` dosyasını `android/app/` klasörüne koy

### GoogleService-Info.plist (iOS)
Firebase Console → Proje Ayarları → iOS uygulaması ekle
- Bundle ID: `com.example.acilYardim`
- `GoogleService-Info.plist` dosyasını Xcode'da `Runner/` klasörüne sürükle

### Flutter bağımlılıklarını yükle
```bash
flutter pub get
```

---

## 5. Twilio WhatsApp Sandbox Aktivasyonu

Her acil kişi şu adımı tamamlamalı:
1. WhatsApp'ı aç
2. `+1 415 523 8886` numarasına mesaj at
3. Mesaj içeriği: `join [sandbox-kelimesi]`
   (Twilio Console → Messaging → Try it out → Send a WhatsApp message sayfasında sandbox kelimesini bul)

---

## 6. AB Shutter 3 Eşleştirme

1. Telefonun Bluetooth ayarlarını aç
2. AB Shutter 3'ün yanındaki butona 3 saniye basılı tut (LED yanıp sönmeye başlar)
3. Bluetooth listesinde `AB Shutter3` cihazını seç ve eşleştir
4. Artık switch telefona Bluetooth klavye olarak görünür

---

## 7. Test

1. Uygulamayı başlat ve Google ile giriş yap
2. Ayarlar ekranından acil kişi ekle
3. Ana ekranda "Test Et" butonuna bas
4. AB Shutter 3 switch'ine bas — 3 saniye debounce sonrası tetiklenir

---

## Önemli Notlar

- **Twilio Trial:** Sadece doğrulanmış numaralara arama yapılabilir
- **Cloud Function Timeout:** Çok kişi varsa `timeoutSeconds: 120` ayarı gerekli (functions/index.js'de mevcut)
- **iOS Arka Plan:** Arka plan konum izni için "Always" seçilmeli
- **Android Batarya Optimizasyonu:** Arka planda çalışması için batarya optimizasyonundan muaf tutulmalı
  - Ayarlar → Uygulamalar → AcilYardım → Batarya → Kısıtlama Yok

---

## Firestore Güvenlik Kuralları

`firestore.rules` dosyası zaten yapılandırıldı. Deploy için:

```bash
firebase deploy --only firestore:rules
```
