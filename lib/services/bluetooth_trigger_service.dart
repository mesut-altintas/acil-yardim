// Bluetooth HID tetikleme servisi
// AB Shutter 3, telefona Bluetooth klavye olarak görünür.
// Android: HardwareKeyboard API
// iOS: AVAudioSession volume observer (native EventChannel)
//
// Buton davranışı:
//   Ses açma (volume up):   3 saniye basılı tut → ACİL tetikle
//   Ses kapatma (volume down): 2 saniye basılı tut → GÜVENDEYİM tetikle

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class BluetoothTriggerService {
  static final BluetoothTriggerService _instance =
      BluetoothTriggerService._internal();
  factory BluetoothTriggerService() => _instance;
  BluetoothTriggerService._internal();

  static const EventChannel _volumeChannel =
      EventChannel('com.acilyardim/volume_button');

  // Hold eşikleri (ms)
  static const int _emergencyHoldMs = 3000; // ses açma → ACİL
  static const int _safeHoldMs = 2000;      // ses kapatma → GÜVENDEYİM
  // Bu süre boyunca yeni event gelmezse bırakıldı sayılır
  static const int _releaseTimeoutMs = 600;

  // Hold durumu
  DateTime? _upHoldStart;
  DateTime? _downHoldStart;
  Timer? _upReleaseTimer;
  Timer? _downReleaseTimer;

  bool _isListening = false;
  bool get isListening => _isListening;

  StreamSubscription? _volumeSubscription;

  // AB Shutter bağlantı durumu
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  // Tetikleme olayları: 'emergency' veya 'safe'
  final StreamController<String> _triggerController =
      StreamController<String>.broadcast();
  Stream<String> get triggerStream => _triggerController.stream;

  Future<void> start() async {
    if (_isListening) return;

    if (Platform.isIOS) {
      _volumeSubscription =
          _volumeChannel.receiveBroadcastStream().listen((event) {
        if (event == 'volume_up') {
          _onVolumeUp();
        } else if (event == 'volume_down') {
          _onVolumeDown();
        }
      });
    } else {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
    }

    _isListening = true;
  }

  Future<void> stop() async {
    if (Platform.isIOS) {
      await _volumeSubscription?.cancel();
      _volumeSubscription = null;
    } else {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    }
    _resetUpHold();
    _resetDownHold();
    _isListening = false;
  }

  // ── Ses açma: 3 saniye basılı tut → ACİL ──
  void _onVolumeUp() {
    _connectionController.add(true);
    _upReleaseTimer?.cancel();
    _upReleaseTimer = null;

    final now = DateTime.now();
    _upHoldStart ??= now;

    final held = now.difference(_upHoldStart!).inMilliseconds;
    if (held >= _emergencyHoldMs) {
      _resetUpHold();
      _triggerController.add('emergency');
      return;
    }

    // Sonraki event gelmezse bırakıldı say
    _upReleaseTimer = Timer(Duration(milliseconds: _releaseTimeoutMs), () {
      _upHoldStart = null;
    });
  }

  // ── Ses kapatma: 2 saniye basılı tut → GÜVENDEYİM ──
  void _onVolumeDown() {
    _connectionController.add(true);
    _downReleaseTimer?.cancel();
    _downReleaseTimer = null;

    final now = DateTime.now();
    _downHoldStart ??= now;

    final held = now.difference(_downHoldStart!).inMilliseconds;
    if (held >= _safeHoldMs) {
      _resetDownHold();
      _triggerController.add('safe');
      return;
    }

    _downReleaseTimer = Timer(Duration(milliseconds: _releaseTimeoutMs), () {
      _downHoldStart = null;
    });
  }

  void _resetUpHold() {
    _upReleaseTimer?.cancel();
    _upReleaseTimer = null;
    _upHoldStart = null;
  }

  void _resetDownHold() {
    _downReleaseTimer?.cancel();
    _downReleaseTimer = null;
    _downHoldStart = null;
  }

  // Android: HardwareKeyboard handler
  bool _onKeyEvent(KeyEvent event) {
    final isVolumeUp =
        event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
        event.physicalKey == PhysicalKeyboardKey.audioVolumeUp;
    final isVolumeDown =
        event.logicalKey == LogicalKeyboardKey.audioVolumeDown ||
        event.physicalKey == PhysicalKeyboardKey.audioVolumeDown;

    if (!isVolumeUp && !isVolumeDown) return false;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (isVolumeUp) _onVolumeUp();
      if (isVolumeDown) _onVolumeDown();
    } else if (event is KeyUpEvent) {
      // Android: gerçek bırakma eventi var, direkt sıfırla
      if (isVolumeUp) _resetUpHold();
      if (isVolumeDown) _resetDownHold();
    }

    return true;
  }

  void dispose() {
    stop();
    _connectionController.close();
    _triggerController.close();
  }
}
