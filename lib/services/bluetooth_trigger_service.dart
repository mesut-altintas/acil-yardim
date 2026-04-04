// Bluetooth HID tetikleme servisi
// AB Shutter 3, telefona Bluetooth klavye olarak görünür.
// Android: HardwareKeyboard API
// iOS: AVAudioSession volume observer (native EventChannel)

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'emergency_service.dart';

class BluetoothTriggerService {
  static final BluetoothTriggerService _instance =
      BluetoothTriggerService._internal();
  factory BluetoothTriggerService() => _instance;
  BluetoothTriggerService._internal();

  static const EventChannel _volumeChannel =
      EventChannel('com.acilyardim/volume_button');

  static const int _debounceDurationMs = 3000;
  DateTime? _lastTriggerTime;

  bool _isListening = false;
  bool get isListening => _isListening;

  StreamSubscription? _volumeSubscription;

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  Future<void> start() async {
    if (_isListening) return;

    if (Platform.isIOS) {
      // iOS: native volume button dinle
      _volumeSubscription = _volumeChannel.receiveBroadcastStream().listen((event) {
        if (event == 'volume_up') {
          _onVolumeUp();
        }
      });
    } else {
      // Android: HardwareKeyboard
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
    }

    _isListening = true;
    print('[BluetoothTriggerService] Dinleme başladı (${Platform.isIOS ? "iOS native" : "Android HardwareKeyboard"})');
  }

  Future<void> stop() async {
    if (Platform.isIOS) {
      await _volumeSubscription?.cancel();
      _volumeSubscription = null;
    } else {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    }
    _isListening = false;
  }

  void _onVolumeUp() {
    final now = DateTime.now();
    _connectionController.add(true);

    if (_lastTriggerTime != null) {
      final elapsed = now.difference(_lastTriggerTime!).inMilliseconds;
      if (elapsed < _debounceDurationMs) return;
    }

    _lastTriggerTime = now;
    print('[BluetoothTriggerService] AB Shutter tetiklendi (iOS)');
    EmergencyService().trigger();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final isVolumeUp =
        event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
        event.physicalKey == PhysicalKeyboardKey.audioVolumeUp;

    if (!isVolumeUp) return false;

    final now = DateTime.now();
    _connectionController.add(true);

    if (_lastTriggerTime != null) {
      final elapsed = now.difference(_lastTriggerTime!).inMilliseconds;
      if (elapsed < _debounceDurationMs) return true;
    }

    _lastTriggerTime = now;
    print('[BluetoothTriggerService] AB Shutter tetiklendi (Android)');
    EmergencyService().trigger();
    return true;
  }

  void dispose() {
    stop();
    _connectionController.close();
  }
}
