// Acil yardım tetikleme servisi
// GPS konumu alır, Cloud Function'ı çağırır, hata durumunda yedek arama yapar

import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firestore_service.dart';

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

  // ─────────────────────────────────────────────
  // Ana tetikleme metodu
  // ─────────────────────────────────────────────
  Future<void> trigger({bool isTest = false}) async {
    // Zaten tetikleniyorsa yoksay
    if (_isTriggering) {
      print('[EmergencyService] Zaten tetiklenme sürecinde, yoksayıldı');
      return;
    }

    _isTriggering = true;
    _setStatus(TriggerStatus.gettingGps);

    try {
      // ── 1. GPS konumunu al ──
      final position = await _getLocation();
      print('[EmergencyService] GPS alındı: ${position.latitude}, ${position.longitude}');

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

        final result = await callable.call({
          'userId': userId,
          'latitude': position.latitude,
          'longitude': position.longitude,
        });

        print('[EmergencyService] Cloud Function yanıtı: ${result.data}');
        _setStatus(TriggerStatus.success);

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

    // Konumu al — yüksek doğruluk, max 10sn timeout
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );
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
        await FlutterPhoneDirectCaller.callNumber(contact.phone);
        // Bir sonraki kişiyi aramadan önce kısa bekle
        if (callContacts.indexOf(contact) < callContacts.length - 1) {
          await Future.delayed(const Duration(seconds: 15));
        }
      }
    } catch (e) {
      print('[EmergencyService] Cihaz araması hatası: $e');
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

  void dispose() {
    _statusController.close();
  }
}

/// Geolocator hata sınıfı
class GeolocatorError implements Exception {
  final String message;
  GeolocatorError(this.message);
  @override
  String toString() => 'GeolocatorError: $message';
}
