// Kişi yönetim servisi
// Telefon rehberinden kişi seçme ve Firestore'a kaydetme işlemleri

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/emergency_contact.dart';
import 'firestore_service.dart';

class ContactService {
  // Singleton pattern
  static final ContactService _instance = ContactService._internal();
  factory ContactService() => _instance;
  ContactService._internal();

  final FirestoreService _firestoreService = FirestoreService();

  // ─────────────────────────────────────────────
  // Telefon rehberinden kişi seç
  // ─────────────────────────────────────────────

  /// Sistem rehber seçicisini aç ve tam kişi bilgisini döndür.
  /// openExternalPick() bazen boş phones listesiyle döner;
  /// bu durumda getContact ile tam veri yüklenir.
  Future<Contact?> pickContact() async {
    final contact = await FlutterContacts.openExternalPick();
    if (contact == null) return null;
    if (contact.phones.isNotEmpty) return contact;

    // Phones boş — izin isteyip tam veriyi yükle
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (granted) {
        final full = await FlutterContacts.getContact(
          contact.id,
          withProperties: true,
          withThumbnail: false,
        );
        if (full != null) return full;
      }
    } catch (_) {}
    return contact;
  }

  /// Seçilen rehber kişisini acil kişi olarak kaydet
  /// [selectedPhone]: birden fazla numara varsa seçilen numara, null ise ilk numara kullanılır
  Future<EmergencyContact> saveContactFromPhone(
    Contact phoneContact, {
    List<ContactChannel> channels = const [ContactChannel.notification],
    String? selectedPhone,
  }) async {
    // Telefon numarası kontrolü
    if (phoneContact.phones.isEmpty) {
      throw Exception('Bu kişinin telefon numarası yok');
    }

    // Numarayı E.164 formatına getir (başına + ekle, boşlukları temizle)
    String phone = (selectedPhone ?? phoneContact.phones.first.number)
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('(', '')
        .replaceAll(')', '');

    if (!phone.startsWith('+')) {
      // Türkiye kodu ekle (0 ile başlıyorsa 0'ı kaldır)
      if (phone.startsWith('0')) {
        phone = '+9${phone}'; // 0532... → +90532...
      } else {
        phone = '+90$phone';
      }
    }

    // Acil kişi oluştur
    final emergencyContact = EmergencyContact(
      id: '', // Firestore otomatik ID atayacak
      name: phoneContact.displayName,
      phone: phone,
      channels: channels,
    );

    // Firestore'a kaydet
    await _firestoreService.addContact(emergencyContact);

    print('[ContactService] Kişi kaydedildi: ${emergencyContact.name} ($phone)');
    return emergencyContact;
  }

  // ─────────────────────────────────────────────
  // FCM Token yönetimi
  // ─────────────────────────────────────────────

  /// Cihazın FCM token'ını al
  Future<String?> getDeviceFcmToken() async {
    try {
      // iOS için izin iste
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        print('[ContactService] FCM bildirimi izni reddedildi');
        return null;
      }

      final token = await FirebaseMessaging.instance.getToken();
      print('[ContactService] FCM token alındı: ${token?.substring(0, 10)}...');
      return token;
    } catch (e) {
      print('[ContactService] FCM token hatası: $e');
      return null;
    }
  }

  /// Kişinin FCM token'ını güncelle
  Future<void> updateContactFcmToken(String contactId, String token) async {
    await _firestoreService.updateFcmToken(contactId, token);
  }

  // ─────────────────────────────────────────────
  // Kişi yönetimi
  // ─────────────────────────────────────────────

  /// Kişinin kanallarını güncelle
  Future<void> updateContactChannels(
    String contactId,
    List<ContactChannel> channels,
  ) async {
    final contacts = await _firestoreService.getContacts();
    final contact = contacts.firstWhere(
      (c) => c.id == contactId,
      orElse: () => throw Exception('Kişi bulunamadı: $contactId'),
    );

    await _firestoreService.updateContactFull(
      contact.copyWith(channels: channels),
    );
  }

  /// Kişi alanlarını kısmi güncelle
  Future<void> updateContact(String contactId, Map<String, dynamic> fields) async {
    await _firestoreService.updateContact(contactId, fields);
  }

  /// Kişiyi sil
  Future<void> deleteContact(String contactId) async {
    await _firestoreService.deleteContact(contactId);
    print('[ContactService] Kişi silindi: $contactId');
  }

  /// Kişi sırasını güncelle (drag & drop sonrası)
  Future<void> reorderContacts(List<EmergencyContact> contacts) async {
    await _firestoreService.reorderContacts(contacts);
  }

  /// Tüm aktif kişileri getir
  Future<List<EmergencyContact>> getActiveContacts() async {
    return await _firestoreService.getContacts();
  }
}
