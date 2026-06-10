# AcilYardım — CLAUDE.md

## Project Overview
Emergency alert app for Turkey. A user presses a button (physical AB Shutter 3 or on-screen hold) and GPS-tagged WhatsApp messages + FCM push notifications are sent to configured emergency contacts. Firebase backend, Twilio WhatsApp, Flutter frontend.

**important**: When you work on a new feature or bug, create a git branch first. Then work on the change in that branch for the remainder of the session.

---

## Tech Stack
| Layer | Technology |
|---|---|
| UI / App | Flutter 3.32+ (Dart, Material 3, dark theme seed `0xFFE63946`) |
| Auth | Firebase Auth (Google, Apple, email/password) |
| Database | Cloud Firestore |
| Push | Firebase Cloud Messaging (FCM) |
| Backend | Firebase Cloud Functions v2, Node.js 22 |
| WhatsApp | Twilio (Sandbox — 50 msg/day limit) |
| Location | `geolocator` package |
| Android native | Kotlin (`ContentObserver`, `AccessibilityService`, foreground `Service`) |
| iOS native | Swift (`AVAudioEngine`, `AVAudioSession` KVO) |

---

## Key Directories
```
lib/
  main.dart          — Firebase init, auth gate, FCM background handler
  models/            — EmergencyContact, TriggerLog (Firestore ↔ Dart)
  services/          — All business logic (singletons + streams)
  screens/           — HomeScreen, SettingsScreen

android/app/src/main/kotlin/com/example/acil_yardim/
  MainActivity.kt            — Flutter channels + battery exemption
  VolumeContentObserver.kt   — Nested in MainActivity; Settings URI observer
  VolumeAccessibilityService.kt — HW key intercept when screen locked
  VolumeService.kt           — Foreground service + silent AudioTrack

ios/Runner/
  AppDelegate.swift          — EventChannel + VolumeButtonHandler
  VolumeButtonHandler.swift  — AVAudioSession KVO + silent AVAudioEngine

functions/
  index.js           — triggerEmergency, sendSafeMessage, callStatusCallback
```

---

## Essential Commands

### Flutter
```bash
# Build & install debug APK (from project root)
flutter build apk --debug && flutter install

# Build iOS (requires Mac)
flutter build ios --debug

# Run on connected device
flutter run

# Run tests
flutter test
```

### Cloud Functions
```bash
cd functions
npm install

# Deploy all functions
firebase deploy --only functions

# Local emulator
firebase emulators:start --only functions,firestore
```

### Android Logs
```bash
adb logcat -s AcilYardim
```

---

## Firestore Schema (brief)
```
users/{uid}/settings/main       — message, safeMessage, callerName, isActive
users/{uid}/contacts/{id}       — name, phone (E.164), channels[], order, isEnabled
users/{uid}/triggerLogs/{id}    — timestamp, lat, lng, contactCount, type ('emergency'|'safe'), direction ('sent'|'received'), message
users/{uid}/receivedAlerts/{id} — incoming FCM alerts logged from HomeScreen
phoneRegistry/{phone}           — fcmToken (global, for cross-user FCM lookup)
```

---

## Environment / Secrets
Cloud Functions read from `.env` (never commit):
- `TWILIO_SID`, `TWILIO_TOKEN`, `TWILIO_WHATSAPP` (`whatsapp:+14155238886`)

---

## Additional Documentation
Check these files when working on the relevant area:

| Topic | File |
|---|---|
| Architecture, patterns, design decisions | [.claude/docs/architectural_patterns.md](.claude/docs/architectural_patterns.md) |

---

## Known Constraints
- Twilio Sandbox: **50 WhatsApp messages/day** — resets at UTC 00:00 (03:00 Turkey)
- Android Accessibility Service must be **re-enabled after every APK reinstall** (Android security)
- iOS locked-screen detection requires AVAudioEngine to be running (started on `onListen`) — **do not remove the silent audio trick**
- Background location on Android requires `Always Allow` permission (prompted on first launch)
- `BluetoothTriggerService._releaseTimeoutMs = 2500` bridges AB Shutter's ~2.2 s natural burst gap — **do not lower this value**
- Android 14+: use `LocalBroadcastManager` for VolumeService→MainActivity IPC (`RECEIVER_NOT_EXPORTED` restriction)
- Calls on Android use `ACTION_CALL` via `com.acilyardim/call` MethodChannel; iOS falls back to `tel:` URI (no auto-dial on iOS)

---

## Trigger Flow (summary)
```
BluetoothTriggerService (volume EventChannel)
  iOS:     2× press within 2000 ms  → 'emergency' or 'safe'
  Android: hold ≥ 3000 ms           → 'emergency' or 'safe'
        ↓
EmergencyService.trigger()
  1. GPS getCurrentPosition()  → fallback: getLastKnownPosition() → fallback: no location
  2. Cloud Function 'triggerEmergency'  → WhatsApp (Twilio) + FCM per contact
  3. SMS from device (Android only, com.acilyardim/sms)
  4. Calls from device (com.acilyardim/call, sequential, 15 s apart)
  5. On any Cloud Function error → tel: URI fallback (first contact with 'call' channel)
        ↓
statusStream → UI always gets TriggerStatus feedback
```
