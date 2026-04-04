// Ana ekran — büyük toggle, bağlantı durumu, kişi listesi, test butonu

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/bluetooth_trigger_service.dart';
import '../services/emergency_service.dart';
import '../services/firestore_service.dart';
import '../models/emergency_contact.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  final BluetoothTriggerService _btService = BluetoothTriggerService();
  final EmergencyService _emergencyService = EmergencyService();
  final FirestoreService _firestoreService = FirestoreService();

  // Uygulama aktif mi?
  bool _isActive = true;

  // Bluetooth bağlı mı?
  bool _isBluetoothConnected = false;

  // Acil kişiler
  List<EmergencyContact> _contacts = [];

  // Son tetiklenme zamanı
  DateTime? _lastTriggerTime;

  // Tetikleme durumu
  TriggerStatus _triggerStatus = TriggerStatus.idle;

  // Akış abonelikleri
  StreamSubscription? _settingsSubscription;
  StreamSubscription? _contactsSubscription;
  StreamSubscription? _btConnectionSubscription;
  StreamSubscription? _triggerStatusSubscription;

  // Animasyon kontrolcüsü (alarm titreşimi için)
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Basılı tut animasyonu
  late AnimationController _holdController;
  bool _isHolding = false;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initSubscriptions();
    _btService.start();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseController.stop();

    // Basılı tut — 3 saniyede dolacak
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onHoldCompleted();
      }
    });
  }

  void _startHold() {
    if (!_isActive || _triggerStatus != TriggerStatus.idle) return;
    setState(() => _isHolding = true);
    HapticFeedback.mediumImpact();
    _holdController.forward(from: 0);
  }

  void _cancelHold() {
    if (!_isHolding) return;
    setState(() => _isHolding = false);
    _holdController.reverse();
  }

  void _onHoldCompleted() {
    setState(() => _isHolding = false);
    HapticFeedback.heavyImpact();
    _emergencyService.trigger();
  }

  void _initSubscriptions() {
    // Kullanıcı ayarlarını izle
    _settingsSubscription =
        _firestoreService.watchSettings().listen((settings) {
      if (mounted) {
        setState(() {
          _isActive = settings['isActive'] ?? true;
        });
      }
    });

    // Acil kişileri izle
    _contactsSubscription =
        _firestoreService.watchContacts().listen((contacts) {
      if (mounted) {
        setState(() => _contacts = contacts);
      }
    });

    // Bluetooth bağlantı durumunu izle
    _btConnectionSubscription =
        _btService.connectionStream.listen((isConnected) {
      if (mounted) {
        setState(() => _isBluetoothConnected = isConnected);
      }
    });

    // Tetikleme durumunu izle
    _triggerStatusSubscription =
        _emergencyService.statusStream.listen((status) {
      if (mounted) {
        setState(() => _triggerStatus = status);

        // Tetiklenince pulse animasyonunu başlat
        if (status == TriggerStatus.gettingGps ||
            status == TriggerStatus.calling) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.reset();
        }

        // Son tetiklenme zamanını güncelle
        if (status == TriggerStatus.success) {
          setState(() => _lastTriggerTime = DateTime.now());
        }
      }
    });
  }

  // ─────────────────────────────────────────────
  // Aktif/Pasif Toggle
  // ─────────────────────────────────────────────
  Future<void> _toggleActive() async {
    final newValue = !_isActive;
    setState(() => _isActive = newValue);
    await _firestoreService.setActive(newValue);

    if (newValue) {
      _btService.start();
    } else {
      _btService.stop();
    }
  }

  // ─────────────────────────────────────────────
  // Yardım menüsü
  // ─────────────────────────────────────────────
  void _showHelp() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nasıl Kullanılır?',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _helpItem(Icons.radio_button_checked, 'AB Shutter 3',
                'Bluetooth düğmeye basınca acil bildirim tetiklenir. Uygulamanın açık ve AKTİF olması gerekir.'),
            _helpItem(Icons.shield, 'AKTİF/PASİF',
                'Ana ekrandaki kırmızı butona basarak sistemi açıp kapatabilirsiniz.'),
            _helpItem(Icons.contacts, 'Acil Kişi Ekle',
                'Ayarlar → Acil Kişiler → + Ekle. Rehberden seç veya manuel gir.'),
            _helpItem(Icons.message, 'WhatsApp Aktivasyonu',
                'Ayarlar sayfasındaki talimatı takip edin. Twilio sandbox numarasına "join [kelime]" gönderin.'),
            _helpItem(Icons.location_on, 'Konum Bildirimi',
                'Tetiklenince GPS konumunuz Google Maps linki olarak tüm kişilere gönderilir.'),
            _helpItem(Icons.call, 'Sesli Arama',
                'Bildirimden 5 saniye sonra acil kişiler otomatik olarak sırayla aranır.'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _helpItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFE63946), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(desc, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Test modu — gerçek bildirim göndermez
  // ─────────────────────────────────────────────
  Future<void> _runTest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test Modu'),
        content: const Text(
          'Bu test sadece uygulama akışını simüle eder. '
          'Gerçek bildirim, WhatsApp mesajı veya arama yapılmaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Testi Başlat'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _emergencyService.trigger(isTest: true);
    }
  }

  // ─────────────────────────────────────────────
  // Tetikleme durumu metni
  // ─────────────────────────────────────────────
  String get _statusText {
    switch (_triggerStatus) {
      case TriggerStatus.gettingGps:
        return 'GPS konumu alınıyor...';
      case TriggerStatus.calling:
        return 'Acil kişiler bilgilendiriliyor...';
      case TriggerStatus.success:
        return '✓ Bildirimler gönderildi!';
      case TriggerStatus.fallback:
        return 'Yedek arama açılıyor...';
      case TriggerStatus.error:
        return '⚠ Hata oluştu';
      default:
        return '';
    }
  }

  Color get _statusColor {
    switch (_triggerStatus) {
      case TriggerStatus.success:
        return Colors.green;
      case TriggerStatus.error:
        return Colors.red;
      case TriggerStatus.fallback:
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  // ─────────────────────────────────────────────
  // Son tetiklenme zamanı metni
  // ─────────────────────────────────────────────
  String get _lastTriggerText {
    if (_lastTriggerTime == null) return 'Henüz tetiklenmedi';
    final diff = DateTime.now().difference(_lastTriggerTime!);
    if (diff.inMinutes < 1) return 'Az önce tetiklendi';
    if (diff.inHours < 1) return '${diff.inMinutes} dakika önce';
    if (diff.inDays < 1) return '${diff.inHours} saat önce';
    return '${diff.inDays} gün önce';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: _isActive ? const Color(0xFF1A1A2E) : Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'AcilYardım',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          // AKTİF/PASİF toggle
          GestureDetector(
            onTap: _toggleActive,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(
                children: [
                  Icon(
                    _isActive ? Icons.power_settings_new : Icons.power_off,
                    color: _isActive ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isActive ? 'Açık' : 'Kapalı',
                    style: TextStyle(
                      color: _isActive ? Colors.green : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Yardım butonu
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white70),
            onPressed: _showHelp,
          ),
          // Ayarlar butonu
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),

            // ── Büyük ACİL Butonu (3 sn basılı tut) ──
            GestureDetector(
              onLongPressStart: (_) => _startHold(),
              onLongPressEnd: (_) => _cancelHold(),
              onLongPressCancel: _cancelHold,
              child: AnimatedBuilder(
                animation: Listenable.merge([_pulseAnimation, _holdController]),
                builder: (context, child) => Transform.scale(
                  scale: _triggerStatus != TriggerStatus.idle
                      ? _pulseAnimation.value
                      : 1.0,
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Dolum halkası
                        SizedBox(
                          width: 220,
                          height: 220,
                          child: CircularProgressIndicator(
                            value: _holdController.value,
                            strokeWidth: 8,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _isHolding
                                  ? Colors.white
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        // Ana daire
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isActive
                                ? const Color(0xFFE63946)
                                : Colors.grey[700],
                            boxShadow: _isActive
                                ? [
                                    BoxShadow(
                                      color: (_isHolding
                                              ? Colors.white
                                              : const Color(0xFFE63946))
                                          .withOpacity(0.5),
                                      blurRadius: _isHolding ? 50 : 30,
                                      spreadRadius: _isHolding ? 15 : 10,
                                    )
                                  ]
                                : [],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isActive
                                    ? Icons.shield
                                    : Icons.shield_outlined,
                                color: Colors.white,
                                size: 60,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isActive ? 'ACİL' : 'PASİF',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4,
                                ),
                              ),
                              Text(
                                _isActive
                                    ? (_isHolding
                                        ? 'Bırakma...'
                                        : '3 sn basılı tut')
                                    : 'Koruma kapalı',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Tetikleme durumu mesajı ──
            if (_triggerStatus != TriggerStatus.idle)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _statusColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_triggerStatus == TriggerStatus.gettingGps ||
                        _triggerStatus == TriggerStatus.calling)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _statusColor,
                        ),
                      ),
                    if (_triggerStatus == TriggerStatus.gettingGps ||
                        _triggerStatus == TriggerStatus.calling)
                      const SizedBox(width: 8),
                    Text(
                      _statusText,
                      style: TextStyle(
                        color: _statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // ── Son tetiklenme zamanı ──
            Text(
              _lastTriggerText,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 24),

            // ── Acil kişiler listesi ──
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Acil Kişiler (${_contacts.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SettingsScreen()),
                            ),
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Düzenle'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _contacts.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.person_add,
                                    color: Colors.white24,
                                    size: 40,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Acil kişi eklenmemiş',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _contacts.length,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              itemBuilder: (ctx, i) {
                                final contact = _contacts[i];
                                return _ContactTile(contact: contact);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Test butonu ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _isActive ? _runTest : null,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Test Et'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white60,
                  side: const BorderSide(color: Colors.white30),
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    _contactsSubscription?.cancel();
    _btConnectionSubscription?.cancel();
    _triggerStatusSubscription?.cancel();
    _pulseController.dispose();
    _holdController.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────
// Tek bir acil kişi satırı
// ─────────────────────────────────────────────
class _ContactTile extends StatelessWidget {
  final EmergencyContact contact;

  const _ContactTile({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            backgroundColor: const Color(0xFFE63946).withOpacity(0.3),
            radius: 20,
            child: Text(
              contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Color(0xFFE63946),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // İsim ve numara
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  contact.phone,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Aktif kanallar göstergesi
          Row(
            children: [
              if (contact.hasChannel(ContactChannel.notification))
                const _ChannelIcon(
                    icon: Icons.notifications, tooltip: 'Bildirim'),
              if (contact.hasChannel(ContactChannel.whatsapp))
                const _ChannelIcon(icon: Icons.chat, tooltip: 'WhatsApp'),
              if (contact.hasChannel(ContactChannel.call))
                const _ChannelIcon(icon: Icons.phone, tooltip: 'Arama'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Küçük kanal ikonu
class _ChannelIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;

  const _ChannelIcon({required this.icon, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(icon, color: Colors.green, size: 16),
      ),
    );
  }
}
