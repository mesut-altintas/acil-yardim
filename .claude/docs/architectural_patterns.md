# Architectural Patterns — AcilYardım

## 1. Singleton Services with Broadcast Streams

All services are singletons exposing `Stream`s for state propagation. No external state management library.

**Pattern:**
```
static final _instance = ServiceName._internal();
factory ServiceName() => _instance;
ServiceName._internal();

final StreamController<T> _controller = StreamController<T>.broadcast();
Stream<T> get stream => _controller.stream;
```

**Files:**
- [lib/services/emergency_service.dart](../../lib/services/emergency_service.dart) — `TriggerStatus` stream
- [lib/services/bluetooth_trigger_service.dart](../../lib/services/bluetooth_trigger_service.dart) — `triggerStream`, `connectionStream`
- [lib/services/firestore_service.dart](../../lib/services/firestore_service.dart) — `watchSettings()`, `watchContacts()`
- [lib/services/contact_service.dart](../../lib/services/contact_service.dart)

Screens subscribe in `initState`, cancel in `dispose`.

---

## 2. Platform Channel Pair: EventChannel (native → Dart) + MethodChannel (Dart → native)

Volume button events flow up via `EventChannel`; accessibility checks flow down via `MethodChannel`.

| Channel | Direction | Usage |
|---|---|---|
| `com.acilyardim/volume_button` | Native → Dart | `volume_up` / `volume_down` string events |
| `com.acilyardim/accessibility` | Dart → Native | `isEnabled()`, `openSettings()` |

**Dart side:** [lib/services/bluetooth_trigger_service.dart:24](../../lib/services/bluetooth_trigger_service.dart#L24), [lib/screens/home_screen.dart](../../lib/screens/home_screen.dart)  
**Android:** [android/.../MainActivity.kt:30-93](../../android/app/src/main/kotlin/com/example/acil_yardim/MainActivity.kt#L30)  
**iOS:** [ios/Runner/AppDelegate.swift](../../ios/Runner/AppDelegate.swift)

---

## 3. Silent Audio Trick (Both Platforms) — Locked Screen Volume Detection

AB Shutter 3 volume events are swallowed by the OS when the screen is locked *unless* the music stream is active. Both platforms solve this by playing a silent looping audio buffer.

| Platform | Implementation | File |
|---|---|---|
| Android | `AudioTrack` with `USAGE_MEDIA`, `CONTENT_TYPE_MUSIC`, PCM silence loop in background thread | [android/.../VolumeService.kt:53-88](../../android/app/src/main/kotlin/com/example/acil_yardim/VolumeService.kt#L53) |
| iOS | `AVAudioEngine` + `AVAudioPlayerNode` scheduling zero-amplitude PCM buffer in loop | [ios/Runner/AppDelegate.swift](../../ios/Runner/AppDelegate.swift) |

Do not remove this audio — it is load-bearing for locked screen functionality.

---

## 4. Platform-Divergent Hold/Press Detection

The same physical button triggers different detection logic per platform because iOS sends one event per press (double-press window) while Android's `ContentObserver` fires repeatedly while held (accumulated hold timing).

| Platform | Trigger gesture | Window/threshold | File |
|---|---|---|---|
| iOS | 2 presses within 2000 ms | `_doublePressWindowMs = 2000` | [bluetooth_trigger_service.dart:28](../../lib/services/bluetooth_trigger_service.dart#L28) |
| Android | Hold ≥ 3000 ms accumulated | `_holdMs = 3000`, `_releaseTimeoutMs = 2500` | [bluetooth_trigger_service.dart:31-32](../../lib/services/bluetooth_trigger_service.dart#L31) |

`_releaseTimeoutMs = 2500` bridges the ~2.2 s natural gap between AB Shutter event bursts — do not reduce below 2500.

---

## 5. Graceful Degradation Chain (Emergency Trigger)

Every failure mode has a fallback, and the user is always notified of the outcome.

```
EmergencyService.trigger()
  └─ GPS.getCurrentPosition()
       └─ fallback: getLastKnownPosition()   [if GPS fails / screen locked]
            └─ continue without location     [if no last known]
  └─ CloudFunctions('triggerEmergency').call()
       └─ fallback: url_launcher tel: dialer [if Cloud Function throws]
  └─ statusStream emits TriggerStatus.*      [UI always gets feedback]
```

**File:** [lib/services/emergency_service.dart](../../lib/services/emergency_service.dart)

---

## 6. Firestore as Single Source of Truth + Local Stream Cache

No local database. Firebase SDK offline cache is the persistence layer. All UI data comes from `Stream<QuerySnapshot>` / `Stream<DocumentSnapshot>` exposed by `FirestoreService`.

- Settings → `watchSettings()` → `StreamBuilder` in HomeScreen
- Contacts → `watchContacts()` → `ListView` in SettingsScreen
- Trigger logs → `watchTriggerLogs()` (last 20)

Adding a field: add to Firestore document, update `fromFirestore()` / `toFirestore()` in the model, update Cloud Function if server-side logic touches it.

---

## 7. E.164 Phone Normalization

All phone numbers stored in E.164 format (`+90XXXXXXXXXX` for Turkey). Normalization applied at contact-save time in `ContactService` and again in Cloud Functions before Twilio calls. `phoneRegistry` collection keys are also E.164.

**Files:** [lib/services/contact_service.dart](../../lib/services/contact_service.dart), [functions/index.js](../../functions/index.js)

---

## 8. Cloud Function Promise Isolation (`Promise.allSettled`)

`triggerEmergency` and `sendSafeMessage` use `Promise.allSettled()` (not `Promise.all()`) so a single contact's FCM or WhatsApp failure never prevents other contacts from being notified. Results are logged to Firestore regardless of partial failure.

**File:** [functions/index.js:132](../../functions/index.js#L132)

---

## 9. LocalBroadcastManager for Android Service→Activity IPC

`VolumeService` (foreground service) communicates with `MainActivity` via `LocalBroadcastManager`, not system `sendBroadcast`. Required for Android 14+ (`RECEIVER_NOT_EXPORTED` restriction).

**Files:** [android/.../VolumeService.kt:36](../../android/app/src/main/kotlin/com/example/acil_yardim/VolumeService.kt#L36), [android/.../MainActivity.kt:71](../../android/app/src/main/kotlin/com/example/acil_yardim/MainActivity.kt#L71)
