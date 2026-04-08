// Bluetooth HID tetikleme servisi
// AB Shutter 3, telefona Bluetooth klavye olarak görünür.
//
// iOS davranışı (AB Shutter tek event gönderir, hold tespit edilemez):
//   Ses açma (+) 2x kısa sürede bas → ACİL
//   Ses kapatma (−) 2x kısa sürede bas → GÜVENDEYİM
//   Pencere: 2 saniye
//
// Android davranışı (ContentObserver sürekli event üretir, hold tespit edilebilir):
//   Ses açma (+) 3 saniye basılı tut → ACİL
//   Ses kapatma (−) 3 saniye basılı tut → GÜVENDEYİM
//   Tetiklemeden sonra 30 sn cooldown (yanlışlık önleme)

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

  // ── iOS: çift basış ──
  static const int _doublePressWindowMs = 2000;

  // ── Android: basılı tut ──
  static const int _holdMs = 3000;       // tetikleme eşiği
  static const int _releaseTimeoutMs = 2500; // bu kadar sessizlik = bırakıldı

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
      // Android: ContentObserver hold tespiti
      _volumeSubscription =
          _volumeChannel.receiveBroadcastStream().listen((event) {
        if (event == 'volume_up') {
          _onAndroidVolumeUp();
        } else if (event == 'volume_down') {
          _onAndroidVolumeDown();
        }
      });
    }

    _isListening = true;
  }

  Future<void> stop() async {
    await _volumeSubscription?.cancel();
    _volumeSubscription = null;
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

  // ── Android: ses açma basılı tut → ACİL ──
  void _onAndroidVolumeUp() {
    _connectionController.add(true);
    _upReleaseTimer?.cancel();
    _upReleaseTimer = null;

    final now = DateTime.now();
    _upHoldStart ??= now;

    final held = now.difference(_upHoldStart!).inMilliseconds;
    if (held >= _holdMs) {
      _resetAndroidUpHold();
      _triggerController.add('emergency');
      return;
    }

    // Bırakıldı mı kontrol et
    _upReleaseTimer = Timer(Duration(milliseconds: _releaseTimeoutMs), () {
      _upHoldStart = null;
    });
  }

  // ── Android: ses kapatma basılı tut → GÜVENDEYİM ──
  void _onAndroidVolumeDown() {
    _connectionController.add(true);
    _downReleaseTimer?.cancel();
    _downReleaseTimer = null;

    final now = DateTime.now();
    _downHoldStart ??= now;

    final held = now.difference(_downHoldStart!).inMilliseconds;
    if (held >= _holdMs) {
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

  void dispose() {
    stop();
    _connectionController.close();
    _triggerController.close();
  }
}
