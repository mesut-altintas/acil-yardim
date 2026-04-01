// Tetikleme geçmişi modeli — her butona basışı kaydeder

import 'package:cloud_firestore/cloud_firestore.dart';

/// Tek bir acil yardım tetiklemesini temsil eden model
class TriggerLog {
  final String id;            // Firestore belge ID'si
  final DateTime timestamp;   // Tetiklenme zamanı
  final double latitude;      // Enlem
  final double longitude;     // Boylam
  final String mapsLink;      // Google Maps linki
  final int contactCount;     // Bilgilendirilen kişi sayısı
  final bool success;         // Genel başarı durumu

  TriggerLog({
    required this.id,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.mapsLink,
    required this.contactCount,
    this.success = true,
  });

  /// Firestore'dan gelen Map'i modele dönüştür
  factory TriggerLog.fromFirestore(String id, Map<String, dynamic> data) {
    // Firestore Timestamp'ini DateTime'a çevir
    DateTime ts;
    if (data['timestamp'] is Timestamp) {
      ts = (data['timestamp'] as Timestamp).toDate();
    } else {
      ts = DateTime.now();
    }

    return TriggerLog(
      id: id,
      timestamp: ts,
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      mapsLink: data['mapsLink'] ?? '',
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
