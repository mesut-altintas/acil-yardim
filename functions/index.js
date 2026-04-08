// AcilYardım — Firebase Cloud Functions
// Node.js 22, firebase-functions v7 (v2 API), Blaze planı gereklidir

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const twilio = require("twilio");

admin.initializeApp();

// Tüm fonksiyonlar için varsayılan bölge ve timeout ayarla
setGlobalOptions({ region: "us-central1", timeoutSeconds: 120, memory: "256MiB" });

// ─────────────────────────────────────────────────────────────
// Ana acil yardım tetikleme fonksiyonu
// Flutter uygulaması bu callable function'ı çağırır
// ─────────────────────────────────────────────────────────────
exports.triggerEmergency = onCall(async (request) => {
  // Kimlik doğrulama zorunlu
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Bu işlem için giriş yapılmış olması gerekiyor.");
  }

  const { userId, latitude, longitude } = request.data;

  // Gelen veriler geçerli mi kontrol et
  if (!userId) {
    throw new HttpsError("invalid-argument", "userId zorunludur.");
  }

  // Firestore referansları
  const userRef = admin.firestore().collection("users").doc(userId);

  // Kullanıcı ayarlarını ve acil kişilerini paralel olarak çek
  const [settingsDoc, contactsSnap] = await Promise.all([
    userRef.collection("settings").doc("main").get(),
    userRef.collection("contacts").orderBy("order").get(),
  ]);

  // Ayarlar belgesi yoksa hata fırlat
  if (!settingsDoc.exists) {
    throw new HttpsError("not-found", "Kullanıcı ayarları bulunamadı.");
  }

  const settings = settingsDoc.data();

  // Uygulama pasif durumdaysa tetikleme yapma
  if (!settings.isActive) {
    return { success: false, reason: "Uygulama pasif durumda." };
  }

  // Google Maps linki oluştur (konum varsa)
  const callerName = settings.callerName || "Kullanıcı";
  const hasLocation = latitude !== undefined && longitude !== undefined;
  const locationText = hasLocation
    ? `\n📍 Konum: https://maps.google.com/?q=${latitude},${longitude}`
    : "";
  const fullMessage = `🚨 ${settings.message}${locationText}\n— ${callerName}`;

  // Twilio istemcisi — .env dosyasından process.env ile oku
  const twilioClient = twilio(process.env.TWILIO_SID, process.env.TWILIO_TOKEN);

  const contacts = contactsSnap.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));

  // ── 1. ADIM: FCM Push Notification + WhatsApp mesajları ──
  const notificationPromises = contacts.map(async (contact) => {
    const errors = [];

    // Firebase Cloud Messaging bildirimi gönder
    if (contact.channels && contact.channels.includes("notification")) {
      try {
        // phoneRegistry'den FCM token ara
        let fcmToken = contact.fcmToken || null;
        if (!fcmToken && contact.phone) {
          const registryDoc = await admin.firestore()
            .collection("phoneRegistry").doc(contact.phone).get();
          if (registryDoc.exists) {
            fcmToken = registryDoc.data().fcmToken;
          }
        }

        if (fcmToken) {
          await admin.messaging().send({
            token: fcmToken,
            notification: { title: "🚨 ACİL YARDIM", body: fullMessage },
            data: {
              type: "emergency",
              latitude: String(latitude),
              longitude: String(longitude),
              userId: userId,
            },
            android: {
              priority: "high",
              notification: { channelId: "emergency_channel", sound: "default" },
            },
            apns: {
              payload: { aps: { sound: "default", badge: 1 } },
              headers: { "apns-priority": "10" },
            },
          });
          console.log(`FCM bildirimi gönderildi: ${contact.name}`);
        } else {
          console.log(`FCM token bulunamadı: ${contact.name} (${contact.phone})`);
        }
      } catch (err) {
        console.error(`FCM hatası (${contact.name}):`, err.message);
        errors.push({ type: "fcm", error: err.message });
      }
    }

    // Twilio WhatsApp mesajı gönder
    if (contact.channels && contact.channels.includes("whatsapp")) {
      try {
        await twilioClient.messages.create({
          body: fullMessage,
          from: process.env.TWILIO_WHATSAPP,
          to: `whatsapp:${contact.phone}`,
        });
        console.log(`WhatsApp mesajı gönderildi: ${contact.name}`);
      } catch (err) {
        console.error(`WhatsApp hatası (${contact.name}):`, err.message);
        errors.push({ type: "whatsapp", error: err.message });
      }
    }

    return { contactId: contact.id, errors };
  });

  // allSettled: bir kişide hata olsa diğerleri etkilenmez
  const notificationResults = await Promise.allSettled(notificationPromises);

  // ── 2. ADIM: Tetikleme geçmişini Firestore'a kaydet ──
  // (Aramalar artık Flutter tarafında cihazdan yapılıyor)
  const callResults = [];
  await userRef.collection("triggerLogs").add({
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    latitude: latitude ?? null,
    longitude: longitude ?? null,
    hasLocation,
    notificationResults,
    callResults,
    contactCount: contacts.length,
  });

  console.log(`triggerEmergency tamamlandı. ${contacts.length} kişi bilgilendirildi.`);

  return {
    success: true,
    timestamp: Date.now(),
    contactCount: contacts.length,
    notificationResults,
    callResults,
  };
});

// ─────────────────────────────────────────────────────────────
// Güvendeyim bildirimi — tüm acil kişilere WhatsApp mesajı gönder
// ─────────────────────────────────────────────────────────────
exports.sendSafeMessage = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Bu işlem için giriş yapılmış olması gerekiyor.");
  }

  const { userId } = request.data;
  if (!userId) {
    throw new HttpsError("invalid-argument", "userId zorunludur.");
  }

  const userRef = admin.firestore().collection("users").doc(userId);
  const [settingsDoc, contactsSnap] = await Promise.all([
    userRef.collection("settings").doc("main").get(),
    userRef.collection("contacts").orderBy("order").get(),
  ]);

  const settings = settingsDoc.exists ? settingsDoc.data() : {};
  const callerName = settings.callerName || "Kullanıcı";
  const safeMessage = (settings.safeMessage || `✅ ${callerName} güvende. Endişelenmeyin.`) + `\n— ${callerName}`;

  const twilioClient = twilio(process.env.TWILIO_SID, process.env.TWILIO_TOKEN);
  const contacts = contactsSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));

  const results = await Promise.allSettled(
    contacts.map(async (contact) => {
      const errors = [];

      // FCM bildirimi
      if (contact.channels && contact.channels.includes("notification")) {
        try {
          let fcmToken = contact.fcmToken || null;
          if (!fcmToken && contact.phone) {
            const registryDoc = await admin.firestore()
              .collection("phoneRegistry").doc(contact.phone).get();
            if (registryDoc.exists) fcmToken = registryDoc.data().fcmToken;
          }
          if (fcmToken) {
            await admin.messaging().send({
              token: fcmToken,
              notification: { title: "✅ GÜVENDEYİM", body: safeMessage },
              data: { type: "safe", userId },
              android: {
                priority: "high",
                notification: { channelId: "emergency_channel", sound: "default" },
              },
              apns: {
                payload: { aps: { sound: "default", badge: 0 } },
                headers: { "apns-priority": "10" },
              },
            });
            console.log(`Güvendeyim FCM gönderildi: ${contact.name}`);
          }
        } catch (err) {
          console.error(`Güvendeyim FCM hatası (${contact.name}):`, err.message);
          errors.push({ type: "fcm", error: err.message });
        }
      }

      // WhatsApp
      if (contact.channels && contact.channels.includes("whatsapp")) {
        try {
          await twilioClient.messages.create({
            body: safeMessage,
            from: process.env.TWILIO_WHATSAPP,
            to: `whatsapp:${contact.phone}`,
          });
          console.log(`Güvendeyim WhatsApp gönderildi: ${contact.name}`);
        } catch (err) {
          console.error(`Güvendeyim WhatsApp hatası (${contact.name}):`, err.message);
          errors.push({ type: "whatsapp", error: err.message });
        }
      }

      return { contactId: contact.id, errors };
    })
  );

  return { success: true, results };
});

// ─────────────────────────────────────────────────────────────
// Twilio arama durumu webhook'u (opsiyonel — loglama için)
// ─────────────────────────────────────────────────────────────
exports.callStatusCallback = onRequest((req, res) => {
  const { CallSid, CallStatus, To } = req.body;
  console.log(`Arama durumu — SID: ${CallSid}, Durum: ${CallStatus}, Hedef: ${To}`);
  res.status(200).send("OK");
});
