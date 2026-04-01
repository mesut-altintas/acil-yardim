#!/bin/bash
# AcilYardım — Kurulum komutları
# Bu dosyayı kendi terminal pencerenizde SIRAYLA çalıştırın

set -e  # Hata olursa dur

echo "=== 1. ADIM: Firebase CLI kurulumu ==="
npm install -g firebase-tools

echo "=== 2. ADIM: Firebase girişi ==="
firebase login

echo "=== 3. ADIM: Firebase projesi oluştur veya mevcut projeyi seç ==="
# Yeni proje: Firebase Console → https://console.firebase.google.com → "Proje ekle"
# Sonra aşağıdaki satırdaki PROJE_ID'yi değiştirin:
firebase use --add
# YA DA doğrudan ID ile:
# firebase use YOUR_PROJECT_ID

echo "=== 4. ADIM: Twilio kimlik bilgilerini Firebase Config'e kaydet ==="
# console.twilio.com → Dashboard sayfasındaki SID ve Token'ı girin
read -p "Twilio Account SID: " TWILIO_SID
read -p "Twilio Auth Token: " TWILIO_TOKEN
read -p "Twilio Phone Number (+1xxxxxxxxxx): " TWILIO_PHONE

firebase functions:config:set \
  twilio.sid="$TWILIO_SID" \
  twilio.token="$TWILIO_TOKEN" \
  twilio.phone="$TWILIO_PHONE" \
  twilio.whatsapp="whatsapp:+14155238886"

echo "=== 5. ADIM: Firestore kurallarını ve Cloud Functions'ı deploy et ==="
firebase deploy --only firestore:rules,functions

echo ""
echo "=== FIREBASE TAMAMLANDI ==="
echo ""
echo "=== 6. ADIM: Flutter kurulumu ==="
echo "Şimdi şunları yapın:"
echo "  a) Firebase Console → Proje Ayarları → Android uygulaması ekle"
echo "     Package: com.example.acil_yardim"
echo "     google-services.json → android/app/ klasörüne koy"
echo ""
echo "  b) Firebase Console → Proje Ayarları → iOS uygulaması ekle"
echo "     Bundle ID: com.example.acilYardim"
echo "     GoogleService-Info.plist → Xcode'da Runner/ klasörüne sürükle"
echo ""
echo "  c) Flutter bağımlılıklarını yükle:"
echo "     flutter pub get"
echo ""
echo "  d) Uygulamayı çalıştır:"
echo "     flutter run"
echo ""
echo "=== 7. ADIM: Twilio WhatsApp Sandbox Aktivasyonu ==="
echo "Her acil kişi WhatsApp'tan şu mesajı göndermelidir:"
echo "  Numara: +1 415 523 8886"
echo "  Mesaj: join [sandbox-kelimesi]"
echo "  (Sandbox kelimesini Twilio Console'dan öğrenin)"
