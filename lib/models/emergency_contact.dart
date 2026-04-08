// Acil kişi modeli — Firestore belgesiyle birebir eşleşir

/// Bildirim kanallarını tanımlayan enum
enum ContactChannel {
  notification, // FCM push bildirimi
  whatsapp,     // Twilio WhatsApp mesajı
  call,         // Twilio sesli arama
  sms,          // Cihazdan SMS (yalnızca Android)
}

/// Tek bir acil kişiyi temsil eden model
class EmergencyContact {
  final String id;        // Firestore belge ID'si
  final String name;      // Kişinin adı soyadı
  final String phone;     // E.164 formatında (+905xxxxxxxxx)
  String? fcmToken;       // Kişinin FCM token'ı (bildirim için)
  List<ContactChannel> channels; // Aktif bildirim kanalları
  int order;             // Sıralama indeksi (küçük = önce)

  EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.fcmToken,
    List<ContactChannel>? channels,
    this.order = 0,
  }) : channels = channels ?? [ContactChannel.notification];

  /// Firestore'dan gelen Map'i modele dönüştür
  factory EmergencyContact.fromFirestore(String id, Map<String, dynamic> data) {
    // Kanal listesini string'den enum'a çevir
    final channelStrings = List<String>.from(data['channels'] ?? ['notification']);
    final channels = channelStrings
        .map((s) => ContactChannel.values.firstWhere(
              (e) => e.name == s,
              orElse: () => ContactChannel.notification,
            ))
        .toList();

    return EmergencyContact(
      id: id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      fcmToken: data['fcmToken'],
      channels: channels,
      order: data['order'] ?? 0,
    );
  }

  /// Modeli Firestore'a kaydetmek için Map'e dönüştür
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'fcmToken': fcmToken,
      'channels': channels.map((c) => c.name).toList(),
      'order': order,
    };
  }

  /// Belirli bir kanalın aktif olup olmadığını kontrol et
  bool hasChannel(ContactChannel channel) => channels.contains(channel);

  /// Kopyasını belirli alanlar değiştirilerek oluştur
  EmergencyContact copyWith({
    String? name,
    String? phone,
    String? fcmToken,
    List<ContactChannel>? channels,
    int? order,
  }) {
    return EmergencyContact(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      fcmToken: fcmToken ?? this.fcmToken,
      channels: channels ?? List.from(this.channels),
      order: order ?? this.order,
    );
  }

  @override
  String toString() => 'EmergencyContact($name, $phone, channels: $channels)';
}
