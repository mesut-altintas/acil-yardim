// Firestore veritabanı işlemlerini yöneten servis

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/emergency_contact.dart';
import '../models/trigger_log.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Giriş yapmış kullanıcının ID'si
  String get _userId => FirebaseAuth.instance.currentUser!.uid;

  // ── Kullanıcı ayarları referansı ──
  DocumentReference get _settingsRef =>
      _db.collection('users').doc(_userId).collection('settings').doc('main');

  // ── Acil kişiler koleksiyon referansı ──
  CollectionReference get _contactsRef =>
      _db.collection('users').doc(_userId).collection('contacts');

  // ── Tetikleme geçmişi koleksiyon referansı ──
  CollectionReference get _logsRef =>
      _db.collection('users').doc(_userId).collection('triggerLogs');

  // ─────────────────────────────────────────────
  // KULLANICI AYARLARI
  // ─────────────────────────────────────────────

  /// Kullanıcı ayarlarını akış olarak izle
  Stream<Map<String, dynamic>> watchSettings() {
    return _settingsRef.snapshots().map((snap) {
      if (!snap.exists) return _defaultSettings();
      return snap.data() as Map<String, dynamic>;
    });
  }

  /// Kullanıcı ayarlarını bir kez oku
  Future<Map<String, dynamic>> getSettings() async {
    final snap = await _settingsRef.get();
    if (!snap.exists) {
      // İlk kez açılıyorsa varsayılan ayarları oluştur
      await _settingsRef.set(_defaultSettings());
      return _defaultSettings();
    }
    return snap.data() as Map<String, dynamic>;
  }

  /// Ayarları güncelle (kısmi güncelleme)
  Future<void> updateSettings(Map<String, dynamic> updates) async {
    await _settingsRef.set(updates, SetOptions(merge: true));
  }

  /// Uygulamayı aktif/pasif yap
  Future<void> setActive(bool isActive) async {
    await _settingsRef.set({'isActive': isActive}, SetOptions(merge: true));
  }

  // ─────────────────────────────────────────────
  // ACİL KİŞİLER
  // ─────────────────────────────────────────────

  /// Acil kişileri sıralı olarak akış ile izle
  Stream<List<EmergencyContact>> watchContacts() {
    return _contactsRef
        .orderBy('order')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => EmergencyContact.fromFirestore(
                  doc.id,
                  doc.data() as Map<String, dynamic>,
                ))
            .toList());
  }

  /// Acil kişileri bir kez oku
  Future<List<EmergencyContact>> getContacts() async {
    final snap = await _contactsRef.orderBy('order').get();
    return snap.docs
        .map((doc) => EmergencyContact.fromFirestore(
              doc.id,
              doc.data() as Map<String, dynamic>,
            ))
        .toList();
  }

  /// Yeni acil kişi ekle
  Future<void> addContact(EmergencyContact contact) async {
    // Mevcut kişi sayısını al ve sıra numarası belirle
    final snap = await _contactsRef.count().get();
    final count = snap.count ?? 0;

    await _contactsRef.doc(contact.id.isEmpty ? null : contact.id).set({
      ...contact.toFirestore(),
      'order': count, // Listenin sonuna ekle
    });
  }

  /// Acil kişiyi güncelle
  Future<void> updateContact(EmergencyContact contact) async {
    await _contactsRef.doc(contact.id).update(contact.toFirestore());
  }

  /// Acil kişiyi sil
  Future<void> deleteContact(String contactId) async {
    await _contactsRef.doc(contactId).delete();
  }

  /// Kişilerin sırasını güncelle (drag & drop sonrası)
  Future<void> reorderContacts(List<EmergencyContact> contacts) async {
    final batch = _db.batch();
    for (int i = 0; i < contacts.length; i++) {
      batch.update(_contactsRef.doc(contacts[i].id), {'order': i});
    }
    await batch.commit();
  }

  /// Kişinin FCM token'ını güncelle
  Future<void> updateFcmToken(String contactId, String token) async {
    await _contactsRef.doc(contactId).update({'fcmToken': token});
  }

  // ─────────────────────────────────────────────
  // TETİKLEME GEÇMİŞİ
  // ─────────────────────────────────────────────

  /// Son tetiklenmeleri akış olarak izle (en fazla 20)
  Stream<List<TriggerLog>> watchTriggerLogs() {
    return _logsRef
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => TriggerLog.fromFirestore(
                  doc.id,
                  doc.data() as Map<String, dynamic>,
                ))
            .toList());
  }

  /// Güvendeyim mesajını geçmişe kaydet
  Future<void> logSafeMessage(int contactCount, String message) async {
    await _logsRef.add({
      'type': 'safe',
      'timestamp': FieldValue.serverTimestamp(),
      'contactCount': contactCount,
      'hasLocation': false,
      'message': message,
    });
  }

  /// Son tetiklenme zamanını al
  Future<DateTime?> getLastTriggerTime() async {
    final snap = await _logsRef
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final data = snap.docs.first.data() as Map<String, dynamic>;
    final ts = data['timestamp'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  // ─────────────────────────────────────────────
  // PHONE REGISTRY — numara → FCM token eşleme
  // ─────────────────────────────────────────────

  /// Kendi telefon numaramı ve FCM token'ımı global registry'ye yaz
  Future<void> registerPhoneWithFcmToken(String phone, String fcmToken) async {
    final normalized = _normalizePhone(phone);
    if (normalized.isEmpty) return;
    await _db.collection('phoneRegistry').doc(normalized).set({
      'fcmToken': fcmToken,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Telefon numarası kayıtlı mı kontrol et (kayıt sil)
  Future<void> unregisterPhone(String phone) async {
    final normalized = _normalizePhone(phone);
    if (normalized.isEmpty) return;
    await _db.collection('phoneRegistry').doc(normalized).delete();
  }

  String _normalizePhone(String phone) {
    String p = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (p.isEmpty) return '';
    if (!p.startsWith('+')) {
      p = p.startsWith('0') ? '+9$p' : '+90$p';
    }
    return p;
  }

  // ─────────────────────────────────────────────
  // YARDIMCI METODLAR
  // ─────────────────────────────────────────────

  /// Varsayılan kullanıcı ayarları
  Map<String, dynamic> _defaultSettings() => {
        'message': 'ACİL YARDIM! Yardıma ihtiyacım var.',
        'callerName': 'Kullanıcı',
        'isActive': true,
      };
}
