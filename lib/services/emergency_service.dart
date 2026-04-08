// Acil yardım tetikleme servisi
// GPS konumu alır, Cloud Function'ı çağırır, hata durumunda yedek arama yapar

import 'dart:async';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/emergency_contact.dart';
import 'firestore_service.dart';

// SMS kanalı için Android MethodChannel
const _smsChannel = MethodChannel('com.acilyardim/sms');

// Otomatik arama için Android MethodChannel
const _callChannel = MethodChannel('com.acilyardim/call');

/// Tetikleme durumunu UI'a bildirmek için enum
enum TriggerStatus {
  idle,          // Bekleme
  gettingGps,    // GPS alınıyor
  calling,       // Cloud Function çağrılıyor
  success,       // Başarıyla tamamlandı
  fallback,      // Yedek arama açıldı
  error,         // Hata oluştu
}

class EmergencyService {
  // Singleton pattern
  static final EmergencyService _instance = EmergencyService._internal();
  factory EmergencyService() => _instance;
  EmergencyService._internal();

  final FirestoreService _firestoreService = FirestoreService();

  // Tetikleme çalışıyor mu? (çift tetiklemeyi önle)
  bool _isTriggering = false;

  // Durum akışı — UI bu akışı dinleyerek güncellenir
  final StreamController<TriggerStatus> _statusController =
      StreamController<TriggerStatus>.broadcast();
  Stream<TriggerStatus> get statusStream => _statusController.stream;

  TriggerStatus _currentStatus = TriggerStatus.idle;
  TriggerStatus get currentStatus => _currentStatus;

  TriggerResult? _lastResult;
  TriggerResult? get lastResult => _lastResult;

  // ─────────────────────────────────────────────
  // Ana tetikleme metodu
  // ─────────────────────────────────────────────
  Future<void> trigger({bool isTest = false}) async {
    // Zaten tetikleniyorsa yoksay
    if (_isTriggering) {
      print('[EmergencyService] Zaten tetiklenme sürecinde, yoksayıldı');
      return;
    }

    // Kişi listesi kontrolü
    final contacts = await _firestoreService.getContacts();
    if (contacts.isEmpty) {
      _setStatus(TriggerStatus.error);
      print('[EmergencyService] Acil kişi eklenmemiş, tetikleme iptal edildi');
      return;
    }

    _isTriggering = true;
    _setStatus(TriggerStatus.gettingGps);

    try {
      // ── 1. GPS konumunu al (başarısız olsa devam et) ──
      double? latitude;
      double? longitude;
      try {
        final position = await _getLocation();
        latitude = position.latitude;
        longitude = position.longitude;
        print('[EmergencyService] GPS alındı: $latitude, $longitude');
      } catch (e) {
        print('[EmergencyService] GPS alınamadı, konumsuz devam: $e');
      }

      _setStatus(TriggerStatus.calling);

      // ── 2. Cloud Function'ı çağır ──
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      if (!isTest) {
        // Gerçek tetikleme — Cloud Function çağır (WhatsApp + FCM)
        final callable = FirebaseFunctions.instance
            .httpsCallable('triggerEmergency');

        final payload = <String, dynamic>{'userId': userId};
        if (latitude != null && longitude != null) {
          payload['latitude'] = latitude;
          payload['longitude'] = longitude;
        }

        final result = await callable.call(payload);

        final data = Map<String, dynamic>.from(result.data as Map);
        final notifResults = data['notificationResults'] as List? ?? [];

        // Kaç kişiye başarıyla gönderildi?
        int successCount = 0;
        final List<String> failedNames = [];

        for (final r in notifResults) {
          final item = r is Map ? r : {};
          final errors = item['errors'] as List? ?? [];
          if (errors.isEmpty) {
            successCount++;
          } else {
            final contact = contacts.firstWhere(
              (c) => c.id == item['contactId'],
              orElse: () => contacts.first,
            );
            failedNames.add(contact.name);
          }
        }

        _lastResult = TriggerResult(
          successCount: successCount,
          failedNames: failedNames,
          contactCount: contacts.length,
        );

        print('[EmergencyService] Gönderim: $successCount/${contacts.length} başarılı');
        _setStatus(TriggerStatus.success);

        // SMS kanalı: cihazdan gönder (Android only)
        final settings = await _firestoreService.getSettings();
        final callerName = settings['callerName'] ?? 'Kullanıcı';
        final msgText = settings['message'] ?? '🚨 ACİL YARDIM';
        final locationText = latitude != null && longitude != null
            ? '\n📍 Konum: https://maps.google.com/?q=$latitude,$longitude'
            : '';
        final smsMessage = '$msgText$locationText\n— $callerName';
        await _sendSmsFromDevice(contacts, smsMessage);

        // Arama kanalı seçili kişileri cihazdan ara
        await _callContactsFromDevice(userId);
      } else {
        // Test modu — gerçek bildirim gönderme, sadece simüle et
        await Future.delayed(const Duration(seconds: 2));
        print('[EmergencyService] TEST MODU: Gerçek bildirim gönderilmedi');
        _setStatus(TriggerStatus.success);
      }
    } on GeolocatorError catch (e) {
      // GPS hatası — yedek arama aç
      print('[EmergencyService] GPS hatası: $e');
      await _fallbackCall();
    } catch (e) {
      // Cloud Function veya diğer hata — yedek arama aç
      print('[EmergencyService] Hata: $e');
      if (!isTest) {
        await _fallbackCall();
      } else {
        _setStatus(TriggerStatus.error);
      }
    } finally {
      _isTriggering = false;

      // 5 saniye sonra idle durumuna dön
      Future.delayed(const Duration(seconds: 5), () {
        _setStatus(TriggerStatus.idle);
      });
    }
  }

  // ─────────────────────────────────────────────
  // GPS konumunu al — izinleri kontrol ederek
  // ─────────────────────────────────────────────
  Future<Position> _getLocation() async {
    // Konum servisi açık mı?
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw GeolocatorError('Konum servisi kapalı');
    }

    // Konum izni var mı?
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw GeolocatorError('Konum izni reddedildi');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw GeolocatorError('Konum izni kalıcı olarak reddedildi');
    }

    // Kilitli ekranda arka plan konumu gerekir
    // "Her zaman izin ver" yoksa son bilinen konumu dene
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      );
    } catch (_) {
      // Son bilinen konuma düş (cache, kilitli ekranda çalışır)
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        print('[EmergencyService] getCurrentPosition başarısız, son bilinen konum kullanılıyor');
        return last;
      }
      rethrow;
    }
  }

  // ─────────────────────────────────────────────
  // Kişileri cihazdan ara (kendi telefonunla)
  // ─────────────────────────────────────────────
  Future<void> _callContactsFromDevice(String userId) async {
    try {
      final contacts = await _firestoreService.getContacts();
      final callContacts = contacts.where(
        (c) => c.channels.any((ch) => ch.name == 'call'),
      ).toList();

      for (final contact in callContacts) {
        print('[EmergencyService] Arama başlatılıyor: ${contact.name} (${contact.phone})');
        if (Platform.isAndroid) {
          // Android: ACTION_CALL ile direkt arama (onay gerektirmez)
          try {
            await _callChannel.invokeMethod('dial', {'phone': contact.phone});
          } catch (e) {
            // Yetki yoksa dialer'a düş
            final telUri = Uri.parse('tel:${contact.phone}');
            if (await canLaunchUrl(telUri)) await launchUrl(telUri);
          }
        } else {
          // iOS: dialer aç (otomatik arama iOS'ta mümkün değil)
          final telUri = Uri.parse('tel:${contact.phone}');
          if (await canLaunchUrl(telUri)) await launchUrl(telUri);
        }
        if (callContacts.indexOf(contact) < callContacts.length - 1) {
          await Future.delayed(const Duration(seconds: 15));
        }
      }
    } catch (e) {
      print('[EmergencyService] Cihaz araması hatası: $e');
    }
  }

  // ─────────────────────────────────────────────
  // SMS gönder — cihazdan, yalnızca Android
  // ─────────────────────────────────────────────
  Future<void> _sendSmsFromDevice(List<EmergencyContact> contacts, String message) async {
    if (!Platform.isAndroid) return;
    final smsContacts = contacts.where((c) => c.hasChannel(ContactChannel.sms)).toList();
    for (final contact in smsContacts) {
      try {
        await _smsChannel.invokeMethod('send', {
          'phone': contact.phone,
          'message': message,
        });
        print('[EmergencyService] SMS gönderildi: ${contact.name}');
      } catch (e) {
        print('[EmergencyService] SMS hatası (${contact.name}): $e');
      }
    }
  }

  // ─────────────────────────────────────────────
  // Yedek arama — Cloud Function çalışmazsa
  // url_launcher ile doğrudan telefon aç
  // ─────────────────────────────────────────────
  Future<void> _fallbackCall() async {
    _setStatus(TriggerStatus.fallback);

    try {
      // Firestore'dan ilk kişinin numarasını al
      final contacts = await _firestoreService.getContacts();

      // Arama kanalı olan ilk kişiyi bul
      final callContact = contacts.firstWhere(
        (c) => c.channels.any((ch) => ch.name == 'call'),
        orElse: () => contacts.isNotEmpty ? contacts.first : throw Exception('Kişi bulunamadı'),
      );

      // tel: URL şeması ile araç telefonu aç
      final telUri = Uri.parse('tel:${callContact.phone}');
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri);
        print('[EmergencyService] Yedek arama açıldı: ${callContact.phone}');
      }
    } catch (e) {
      print('[EmergencyService] Yedek arama hatası: $e');
      _setStatus(TriggerStatus.error);
    }
  }

  // ─────────────────────────────────────────────
  // Durum güncelleyici
  // ─────────────────────────────────────────────
  void _setStatus(TriggerStatus status) {
    _currentStatus = status;
    _statusController.add(status);
    print('[EmergencyService] Durum: $status');
  }

  // ─────────────────────────────────────────────
  // Güvendeyim bildirimi
  // ─────────────────────────────────────────────
  Future<bool> sendSafe() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return false;

      final callable = FirebaseFunctions.instance.httpsCallable('sendSafeMessage');
      await callable.call({'userId': userId});
      print('[EmergencyService] Güvendeyim mesajı gönderildi');

      // SMS kanalı: cihazdan gönder (Android only)
      final contacts = await _firestoreService.getContacts();
      final settings = await _firestoreService.getSettings();
      final callerName = settings['callerName'] ?? 'Kullanıcı';
      final safeMsg = settings['safeMessage'] ?? '✅ $callerName güvende. Endişelenmeyin.';
      final fullSafeMsg = '$safeMsg\n— $callerName';
      await _sendSmsFromDevice(contacts, fullSafeMsg);

      // Firestore'a log kaydet
      await _firestoreService.logSafeMessage(contacts.length, fullSafeMsg);

      return true;
    } catch (e) {
      print('[EmergencyService] Güvendeyim hatası: $e');
      return false;
    }
  }

  void dispose() {
    _statusController.close();
  }
}

/// Tetikleme sonuç özeti
class TriggerResult {
  final int successCount;
  final List<String> failedNames;
  final int contactCount;

  TriggerResult({
    required this.successCount,
    required this.failedNames,
    required this.contactCount,
  });

  bool get allSuccess => failedNames.isEmpty;
  String get summary {
    if (allSuccess) return '$successCount kişiye bildirim gönderildi ✓';
    if (successCount == 0) return 'Hiçbir kişiye gönderilemedi ✗';
    return '$successCount/$contactCount gönderildi. Başarısız: ${failedNames.join(", ")}';
  }
}

/// Geolocator hata sınıfı
class GeolocatorError implements Exception {
  final String message;
  GeolocatorError(this.message);
  @override
  String toString() => 'GeolocatorError: $message';
}
