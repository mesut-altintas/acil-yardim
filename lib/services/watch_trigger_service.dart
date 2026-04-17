// Apple Watch tetikleme servisi
// Watch'tan gelen 'emergency' ve 'safe' metodlarını MethodChannel üzerinden alır.
// Yalnızca iOS'ta aktiftir.

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class WatchTriggerService {
  static final WatchTriggerService _instance = WatchTriggerService._internal();
  factory WatchTriggerService() => _instance;
  WatchTriggerService._internal();

  static const _channel = MethodChannel('com.acilyardim/watch_trigger');

  final StreamController<String> _triggerController =
      StreamController<String>.broadcast();

  /// 'emergency' veya 'safe' olaylarını yayar
  Stream<String> get triggerStream => _triggerController.stream;

  bool _initialized = false;

  /// iOS'ta channel handler'ı kaydet
  void init() {
    if (!Platform.isIOS || _initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      final type = call.method; // 'emergency' veya 'safe'
      if (type == 'emergency' || type == 'safe') {
        print('[WatchTrigger] Tetikleme alındı: $type');
        _triggerController.add(type);
      }
      return null;
    });

    print('[WatchTrigger] Başlatıldı');
  }

  void dispose() {
    _triggerController.close();
  }
}
