import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/bluetooth_trigger_service.dart';
import '../services/emergency_service.dart';
import '../services/firestore_service.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final BluetoothTriggerService _btService = BluetoothTriggerService();
  final EmergencyService _emergencyService = EmergencyService();
  final FirestoreService _firestoreService = FirestoreService();

  bool _isActive = true;
  TriggerStatus _triggerStatus = TriggerStatus.idle;

  StreamSubscription? _settingsSubscription;
  StreamSubscription? _triggerStatusSubscription;

  // ACİL butonu
  late AnimationController _emergencyHoldController;
  bool _isEmergencyHolding = false;

  // GÜVENDEYİM butonu
  late AnimationController _safeHoldController;
  bool _isSafeHolding = false;
  bool _isSafeSending = false;

  // Pulse animasyonu (tetiklenince)
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

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
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _emergencyHoldController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _onEmergencyTriggered();
      });

    _safeHoldController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _onSafeTriggered();
      });
  }

  void _initSubscriptions() {
    _settingsSubscription = _firestoreService.watchSettings().listen((settings) {
      if (mounted) setState(() => _isActive = settings['isActive'] ?? true);
    });

    _triggerStatusSubscription = _emergencyService.statusStream.listen((status) {
      if (mounted) {
        setState(() => _triggerStatus = status);
        if (status == TriggerStatus.gettingGps || status == TriggerStatus.calling) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.reset();
        }
      }
    });
  }

  // ── ACİL buton ──
  void _startEmergencyHold() {
    if (!_isActive || _triggerStatus != TriggerStatus.idle) return;
    setState(() => _isEmergencyHolding = true);
    HapticFeedback.mediumImpact();
    _emergencyHoldController.forward(from: 0);
  }

  void _cancelEmergencyHold() {
    if (!_isEmergencyHolding) return;
    setState(() => _isEmergencyHolding = false);
    _emergencyHoldController.reverse();
  }

  void _onEmergencyTriggered() {
    setState(() => _isEmergencyHolding = false);
    HapticFeedback.heavyImpact();
    _emergencyService.trigger();
  }

  // ── GÜVENDEYİM buton ──
  void _startSafeHold() {
    if (_isSafeSending) return;
    setState(() => _isSafeHolding = true);
    HapticFeedback.mediumImpact();
    _safeHoldController.forward(from: 0);
  }

  void _cancelSafeHold() {
    if (!_isSafeHolding) return;
    setState(() => _isSafeHolding = false);
    _safeHoldController.reverse();
  }

  Future<void> _onSafeTriggered() async {
    setState(() { _isSafeHolding = false; _isSafeSending = true; });
    HapticFeedback.heavyImpact();

    final success = await _emergencyService.sendSafe();

    if (mounted) {
      setState(() => _isSafeSending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success
            ? '✅ Güvendeyim mesajı gönderildi'
            : '⚠ Mesaj gönderilemedi'),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ));
    }
  }

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

  String get _statusText {
    switch (_triggerStatus) {
      case TriggerStatus.gettingGps:
        return 'GPS konumu alınıyor...';
      case TriggerStatus.calling:
        return 'Acil kişiler bilgilendiriliyor...';
      case TriggerStatus.success:
        final result = _emergencyService.lastResult;
        if (result != null) return result.summary;
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
      case TriggerStatus.success: return Colors.green;
      case TriggerStatus.error: return Colors.red;
      case TriggerStatus.fallback: return Colors.orange;
      default: return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'AcilYardım',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        actions: [
          // Aktif/Pasif toggle
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
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white70),
            onPressed: _showHelp,
          ),
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
            // Durum mesajı
            if (_triggerStatus != TriggerStatus.idle)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: _statusColor,
                        ),
                      ),
                    if (_triggerStatus == TriggerStatus.gettingGps ||
                        _triggerStatus == TriggerStatus.calling)
                      const SizedBox(width: 8),
                    Text(_statusText,
                        style: TextStyle(color: _statusColor, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),

            const Spacer(),

            // ── ACİL butonu ──
            _HoldButton(
              holdController: _emergencyHoldController,
              isHolding: _isEmergencyHolding,
              isActive: _isActive,
              color: const Color(0xFFE63946),
              icon: Icons.sos,
              label: 'ACİL',
              sublabel: _isEmergencyHolding ? 'Bırakma...' : '3 sn basılı tut',
              onHoldStart: _startEmergencyHold,
              onHoldEnd: _cancelEmergencyHold,
              onHoldCancel: _cancelEmergencyHold,
              pulseController: _pulseController,
              pulseAnimation: _pulseAnimation,
              isTriggering: _triggerStatus != TriggerStatus.idle,
            ),

            const SizedBox(height: 32),

            // ── GÜVENDEYİM butonu ──
            _HoldButton(
              holdController: _safeHoldController,
              isHolding: _isSafeHolding,
              isActive: true,
              color: const Color(0xFF2ECC71),
              icon: _isSafeSending ? Icons.hourglass_top : Icons.check_circle,
              label: 'GÜVENDEYİM',
              sublabel: _isSafeSending
                  ? 'Gönderiliyor...'
                  : (_isSafeHolding ? 'Bırakma...' : '3 sn basılı tut'),
              onHoldStart: _startSafeHold,
              onHoldEnd: _cancelSafeHold,
              onHoldCancel: _cancelSafeHold,
              pulseController: _pulseController,
              pulseAnimation: _pulseAnimation,
              isTriggering: false,
            ),

            const Spacer(),

            // Alt bilgi
            Text(
              _isActive ? 'Sistem aktif — AB Shutter hazır' : 'Sistem pasif',
              style: TextStyle(
                color: _isActive ? Colors.green.withOpacity(0.7) : Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

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
            _helpItem(Icons.sos, 'ACİL Butonu',
                '3 saniye basılı tutunca GPS konumunuzla birlikte tüm acil kişilere WhatsApp mesajı gönderilir ve arama başlar.'),
            _helpItem(Icons.check_circle, 'GÜVENDEYİM Butonu',
                '3 saniye basılı tutunca tüm acil kişilere "Güvendeyim" mesajı gönderilir.'),
            _helpItem(Icons.radio_button_checked, 'AB Shutter 3',
                'Bluetooth düğmeye basınca ACİL tetiklenir. Uygulamanın açık ve AKTİF olması gerekir.'),
            _helpItem(Icons.settings, 'Ayarlar',
                'Sağ üstteki ayarlar ikonundan acil kişi ekleyebilir, mesaj şablonunu düzenleyebilirsiniz.'),
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
                Text(title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(desc,
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    _triggerStatusSubscription?.cancel();
    _pulseController.dispose();
    _emergencyHoldController.dispose();
    _safeHoldController.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────
// Basılı tut butonu widget'ı
// ─────────────────────────────────────────────
class _HoldButton extends StatelessWidget {
  final AnimationController holdController;
  final AnimationController pulseController;
  final Animation<double> pulseAnimation;
  final bool isHolding;
  final bool isActive;
  final bool isTriggering;
  final Color color;
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onHoldCancel;

  const _HoldButton({
    required this.holdController,
    required this.pulseController,
    required this.pulseAnimation,
    required this.isHolding,
    required this.isActive,
    required this.isTriggering,
    required this.color,
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onHoldCancel,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isActive ? color : Colors.grey[700]!;

    return GestureDetector(
      onLongPressStart: (_) => onHoldStart(),
      onLongPressEnd: (_) => onHoldEnd(),
      onLongPressCancel: onHoldCancel,
      child: AnimatedBuilder(
        animation: Listenable.merge([pulseAnimation, holdController]),
        builder: (context, child) => Transform.scale(
          scale: isTriggering ? pulseAnimation.value : 1.0,
          child: SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Dolum halkası
                SizedBox(
                  width: 200,
                  height: 200,
                  child: CircularProgressIndicator(
                    value: holdController.value,
                    strokeWidth: 7,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isHolding ? Colors.white : Colors.transparent,
                    ),
                  ),
                ),
                // Ana daire
                Container(
                  width: 184,
                  height: 184,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: effectiveColor,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: (isHolding ? Colors.white : effectiveColor)
                                  .withOpacity(0.5),
                              blurRadius: isHolding ? 50 : 30,
                              spreadRadius: isHolding ? 15 : 8,
                            )
                          ]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: Colors.white, size: 52),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sublabel,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 11,
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
    );
  }
}
