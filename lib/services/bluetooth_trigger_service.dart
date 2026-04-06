// Bluetooth HID tetikleme servisi
// AB Shutter 3, telefona Bluetooth klavye olarak görünür.
//
// iOS davranışı (AB Shutter tek event gönderir, hold tespit edilemez):
//   Ses açma (+) 2x kısa sürede bas → ACİL
//   Ses kapatma (−) 2x kısa sürede bas → GÜVENDEYİM
//   Pencere: 2 saniye
//
// Android davranışı (KeyDown/Up mevcut, hold tespit edilebilir):
//   Ses açma (+) 3 saniye basılı tut → ACİL
//   Ses kapatma (−) 2 saniye basılı tut → GÜVENDEYİM

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

  // iOS: çift basış penceresi (ms)
  static const int _doublePressWindowMs = 2000;

  // Android: hold eşikleri (ms)
  static const int _emergencyHoldMs = 3000;
  static const int _safeHoldMs = 3000;
  static const int _releaseTimeoutMs = 600;

  // iOS çift basış durumu
  DateTime? _lastUpPress;
  DateTime? _lastDownPress;

  // Android hold durumu
  DateTime? _upHoldStart;
  DateTime? _downHoldStart;
  Timer? _upReleaseTimer;
  Timer? _downReleaseTimer;

  bool _isListening = false;
  bool get isListening => _isListening;

  StreamSubscription? _volumeSubscription;

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  final StreamController<String> _triggerController =
      StreamController<String>.broadcast();
  Stream<String> get triggerStream => _triggerController.stream;

  Future<void> start() async {
    if (_isListening) return;

    if (Platform.isIOS) {
      _volumeSubscription =
          _volumeChannel.receiveBroadcastStream().listen((event) {
        if (event == 'volume_up') {
          _onIosVolumeUp();
        } else if (event == 'volume_down') {
          _onIosVolumeDown();
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
    _resetAndroidUpHold();
    _resetAndroidDownHold();
    _lastUpPress = null;
    _lastDownPress = null;
    _isListening = false;
  }

  // ── iOS: ses açma 2x → ACİL ──
  void _onIosVolumeUp() {
    _connectionController.add(true);
    final now = DateTime.now();
    if (_lastUpPress != null &&
        now.difference(_lastUpPress!).inMilliseconds <= _doublePressWindowMs) {
      _lastUpPress = null;
      _triggerController.add('emergency');
    } else {
      _lastUpPress = now;
    }
  }

  // ── iOS: ses kapatma 2x → GÜVENDEYİM ──
  void _onIosVolumeDown() {
    _connectionController.add(true);
    final now = DateTime.now();
    if (_lastDownPress != null &&
        now.difference(_lastDownPress!).inMilliseconds <= _doublePressWindowMs) {
      _lastDownPress = null;
      _triggerController.add('safe');
    } else {
      _lastDownPress = now;
    }
  }

  // ── Android: hold detection ──
  void _onAndroidVolumeUp() {
    _connectionController.add(true);
    _upReleaseTimer?.cancel();
    _upReleaseTimer = null;

    final now = DateTime.now();
    _upHoldStart ??= now;

    final held = now.difference(_upHoldStart!).inMilliseconds;
    if (held >= _emergencyHoldMs) {
      _resetAndroidUpHold();
      _triggerController.add('emergency');
      return;
    }

    _upReleaseTimer = Timer(Duration(milliseconds: _releaseTimeoutMs), () {
      _upHoldStart = null;
    });
  }

  void _onAndroidVolumeDown() {
    _connectionController.add(true);
    _downReleaseTimer?.cancel();
    _downReleaseTimer = null;

    final now = DateTime.now();
    _downHoldStart ??= now;

    final held = now.difference(_downHoldStart!).inMilliseconds;
    if (held >= _safeHoldMs) {
      _resetAndroidDownHold();
      _triggerController.add('safe');
      return;
    }

    _downReleaseTimer = Timer(Duration(milliseconds: _releaseTimeoutMs), () {
      _downHoldStart = null;
    });
  }

  void _resetAndroidUpHold() {
    _upReleaseTimer?.cancel();
    _upReleaseTimer = null;
    _upHoldStart = null;
  }

  void _resetAndroidDownHold() {
    _downReleaseTimer?.cancel();
    _downReleaseTimer = null;
    _downHoldStart = null;
  }

  bool _onKeyEvent(KeyEvent event) {
    final isVolumeUp =
        event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
        event.physicalKey == PhysicalKeyboardKey.audioVolumeUp;
    final isVolumeDown =
        event.logicalKey == LogicalKeyboardKey.audioVolumeDown ||
        event.physicalKey == PhysicalKeyboardKey.audioVolumeDown;

    if (!isVolumeUp && !isVolumeDown) return false;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (isVolumeUp) _onAndroidVolumeUp();
      if (isVolumeDown) _onAndroidVolumeDown();
    } else if (event is KeyUpEvent) {
      if (isVolumeUp) _resetAndroidUpHold();
      if (isVolumeDown) _resetAndroidDownHold();
    }

    return true;
  }

  void dispose() {
    stop();
    _connectionController.close();
    _triggerController.close();
  }
}
