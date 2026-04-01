// Bluetooth HID tetikleme servisi
// AB Shutter 3, telefona Bluetooth klavye olarak görünür.
// Flutter'ın yerleşik HardwareKeyboard API'si ile Volume Up tuşu yakalanır —
// harici paket gerektirmez.

import 'dart:async';
import 'package:flutter/services.dart';
import 'emergency_service.dart';

class BluetoothTriggerService {
  // Singleton pattern — tek örnek kullan
  static final BluetoothTriggerService _instance =
      BluetoothTriggerService._internal();
  factory BluetoothTriggerService() => _instance;
  BluetoothTriggerService._internal();

  // Yanlışlıkla tetiklenmeyi önlemek için debounce süresi (ms)
  static const int _debounceDurationMs = 3000;

  // Son tetikleme zamanı (debounce için)
  DateTime? _lastTriggerTime;

  // Servisi dinliyor mu?
  bool _isListening = false;
  bool get isListening => _isListening;

  // Son klavye eventi zamanı — bağlantı tespiti için
  DateTime? _lastEventTime;

  // Bağlantı durumu: son 30 saniyede event geldiyse bağlı say
  bool get isConnected {
    if (_lastEventTime == null) return false;
    return DateTime.now().difference(_lastEventTime!).inSeconds < 30;
  }

  // Bağlantı durumu akışı
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  // ─────────────────────────────────────────────
  // Servisi başlat — klavye eventlerini dinle
  // ─────────────────────────────────────────────
  Future<void> start() async {
    if (_isListening) return;

    // Flutter'ın HardwareKeyboard handler'ını kaydet
    // AB Shutter 3'ün gönderdiği Volume Up = LogicalKeyboardKey.audioVolumeUp
    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    _isListening = true;
    print('[BluetoothTriggerService] Dinleme başladı (HardwareKeyboard)');
  }

  // ─────────────────────────────────────────────
  // Servisi durdur
  // ─────────────────────────────────────────────
  Future<void> stop() async {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _isListening = false;
    print('[BluetoothTriggerService] Dinleme durduruldu');
  }

  // ─────────────────────────────────────────────
  // Klavye eventi geldiğinde çağrılır
  // ─────────────────────────────────────────────
  bool _onKeyEvent(KeyEvent event) {
    // Sadece tuşa basılma anını yakala (basılı tutma veya bırakma değil)
    if (event is! KeyDownEvent) return false;

    // AB Shutter 3 → Volume Up tuşu
    // Fiziksel anahtar: PhysicalKeyboardKey.audioVolumeUp
    // Mantıksal anahtar: LogicalKeyboardKey.audioVolumeUp
    final isVolumeUp =
        event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
        event.physicalKey == PhysicalKeyboardKey.audioVolumeUp;

    if (!isVolumeUp) return false;

    final now = DateTime.now();
    _lastEventTime = now;
    _connectionController.add(true); // Bağlı sinyali yayınla

    print('[BluetoothTriggerService] Volume Up eventi alındı: $now');

    // ── Debounce kontrolü ──
    if (_lastTriggerTime != null) {
      final elapsed = now.difference(_lastTriggerTime!).inMilliseconds;
      if (elapsed < _debounceDurationMs) {
        print('[BluetoothTriggerService] Debounce: $elapsed ms, yoksayıldı');
        return true; // Olayı tüket (ses seviyesi değişmesin)
      }
    }

    _lastTriggerTime = now;
    print('[BluetoothTriggerService] Acil yardım tetikleniyor...');

    // Acil yardım servisini çağır
    EmergencyService().trigger();

    return true; // true dönerek olayın daha fazla işlenmesini engelle
  }

  // ─────────────────────────────────────────────
  // Kaynakları serbest bırak
  // ─────────────────────────────────────────────
  void dispose() {
    stop();
    _connectionController.close();
  }
}
