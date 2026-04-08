// Tetikleme geçmişi modeli — her butona basışı kaydeder

import 'package:cloud_firestore/cloud_firestore.dart';

/// Tek bir acil yardım tetiklemesini temsil eden model
class TriggerLog {
  final String id;            // Firestore belge ID'si
  final DateTime timestamp;   // Tetiklenme zamanı
  final double? latitude;     // Enlem (opsiyonel)
  final double? longitude;    // Boylam (opsiyonel)
  final bool hasLocation;     // Konum var mı
  final int contactCount;     // Bilgilendirilen kişi sayısı
  final bool success;         // Genel başarı durumu

  TriggerLog({
    required this.id,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.hasLocation = false,
    required this.contactCount,
    this.success = true,
  });

  String? get mapsLink => hasLocation && latitude != null && longitude != null
      ? 'https://maps.google.com/?q=$latitude,$longitude'
      : null;

  /// Firestore'dan gelen Map'i modele dönüştür
  factory TriggerLog.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime ts;
    if (data['timestamp'] is Timestamp) {
      ts = (data['timestamp'] as Timestamp).toDate();
    } else {
      ts = DateTime.now();
    }

    final lat = data['latitude'] != null ? (data['latitude'] as num).toDouble() : null;
    final lng = data['longitude'] != null ? (data['longitude'] as num).toDouble() : null;
    final hasLoc = data['hasLocation'] as bool? ?? (lat != null && lng != null);

    return TriggerLog(
      id: id,
      timestamp: ts,
      latitude: lat,
      longitude: lng,
      hasLocation: hasLoc,
      contactCount: data['contactCount'] ?? 0,
      success: data['success'] ?? true,
    );
  }

  /// Okunabilir zaman metni (örn: "31 Mar 2026, 14:30")
  String get formattedTime {
    final months = [
      '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
    ];
    return '${timestamp.day} ${months[timestamp.month]} ${timestamp.year}, '
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';
  }

  @override
  String toString() =>
      'TriggerLog($formattedTime, $contactCount kişi, success: $success)';
}
