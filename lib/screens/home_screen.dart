import 'dart:async';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
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

  // Erişilebilirlik servisi durumu (Android)
  bool _accessibilityEnabled = true;
  static const _accessibilityChannel = MethodChannel('com.acilyardim/accessibility');

  // Güvendeyim durumu
  bool _isSafeSending = false;
  String? _safeResultText;

  StreamSubscription? _settingsSubscription;
  StreamSubscription? _triggerStatusSubscription;
  StreamSubscription? _btTriggerSubscription;

  // ACİL basılı tut
  late AnimationController _emergencyHoldController;
  bool _isEmergencyHolding = false;

  // GÜVENDEYİM basılı tut
  late AnimationController _safeHoldController;
  bool _isSafeHolding = false;

  // Pulse (tetiklenince)
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initSubscriptions();
    _btService.start();
    _checkAccessibility();
    _requestBackgroundLocation();
    _registerFcmToken();
    _handleInitialNotification();
  }

  // Uygulama kapalıyken bildirime tıklanınca açılma
  Future<void> _handleInitialNotification() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    if (message != null && mounted) {
      // Kısa gecikme — widget tam yerleşsin
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _showNotificationSheet(message);
    }
  }

  void _showNotificationSheet(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] ?? 'emergency';
    final isSafe = type == 'safe';
    final title = message.notification?.title ?? (isSafe ? '✅ GÜVENDEYİM' : '🚨 ACİL YARDIM');
    final body = message.notification?.body ?? '';
    final lat = double.tryParse(data['latitude'] ?? '');
    final lng = double.tryParse(data['longitude'] ?? '');
    final hasLocation = lat != null && lng != null;

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
            Row(
              children: [
                Icon(
                  isSafe ? Icons.check_circle : Icons.warning_rounded,
                  color: isSafe ? Colors.green : const Color(0xFFE63946),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSafe ? Colors.green : const Color(0xFFE63946),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              body,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (hasLocation) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
                    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.map),
                  label: const Text('Haritada Aç'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE63946)),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Kapat', style: TextStyle(color: Colors.white38)),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  // FCM token'ı uygulama her açıldığında phoneRegistry'ye yaz
  Future<void> _registerFcmToken() async {
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      final settings = await _firestoreService.getSettings();
      final myPhone = settings['myPhone'] as String? ?? '';
      print('[HomeScreen] FCM myPhone: "$myPhone"');
      if (myPhone.isNotEmpty) {
        await _firestoreService.registerPhoneWithFcmToken(myPhone, token);
        print('[HomeScreen] FCM token kaydedildi: $myPhone → ${token.substring(0, 15)}...');
      } else {
        print('[HomeScreen] FCM kaydı atlandı: myPhone boş');
      }
    } catch (e) {
      print('[HomeScreen] FCM token kayıt hatası: $e');
    }
    // Token yenilenince de güncelle
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      try {
        final settings = await _firestoreService.getSettings();
        final myPhone = settings['myPhone'] as String? ?? '';
        if (myPhone.isNotEmpty) {
          await _firestoreService.registerPhoneWithFcmToken(myPhone, newToken);
          print('[HomeScreen] FCM token yenilendi');
        }
      } catch (_) {}
    });
  }

  Future<void> _requestBackgroundLocation() async {
    try {
      // Önce ön plan iznini al
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      // Sonra arka plan iznini iste ("Her zaman izin ver")
      // Android 11+: tekrar requestPermission gerekir
      // iOS: aynı API "Always Allow" seçeneğini sunar
      if (perm == LocationPermission.whileInUse) {
        await Geolocator.requestPermission();
      }
    } catch (_) {}
  }

  Future<void> _checkAccessibility() async {
    if (!Platform.isAndroid) return;
    try {
      final enabled = await _accessibilityChannel.invokeMethod<bool>('isEnabled') ?? false;
      if (!mounted) return;
      setState(() => _accessibilityEnabled = enabled);
      // Sadece ilk açılışta ve etkin değilse sor
      if (!enabled && !_accessibilityDialogShown) {
        _accessibilityDialogShown = true;
        _showAccessibilityDialog();
      }
    } catch (_) {}
  }

  bool _accessibilityDialogShown = false;

  void _showAccessibilityDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Kilitli Ekran Desteği', style: TextStyle(color: Colors.white)),
          content: const Text(
            'AB Shutter\'ın kilitli ekranda çalışması için Erişilebilirlik iznini etkinleştirmeniz gerekiyor.\n\n'
            'Ayarlar → Erişilebilirlik → Yüklü uygulamalar → AcilYardım Ses Tuşu → Aç',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Sonra', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _accessibilityChannel.invokeMethod('openSettings');
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE63946)),
              child: const Text('Ayarları Aç', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    });
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

    // Ön planda gelen FCM — bottom sheet göster
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (!mounted) return;
      _showNotificationSheet(message);
    });

    // Arka planda bildirime tıklanınca
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (!mounted) return;
      _showNotificationSheet(message);
    });

    // AB Shutter hold tetiklemelerini dinle
    _btTriggerSubscription = _btService.triggerStream.listen((event) {
      if (!mounted) return;
      if (event == 'emergency') {
        if (_isActive && _triggerStatus == TriggerStatus.idle) {
          HapticFeedback.heavyImpact();
          _emergencyService.trigger();
        }
      } else if (event == 'safe') {
        if (!_isSafeSending) {
          _onSafeTriggered();
        }
      }
    });
  }

  // ── ACİL ──
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

  // ── GÜVENDEYİM ──
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
    setState(() {
      _isSafeHolding = false;
      _isSafeSending = true;
      _safeResultText = null;
    });
    HapticFeedback.heavyImpact();

    final success = await _emergencyService.sendSafe();

    if (mounted) {
      setState(() {
        _isSafeSending = false;
        _safeResultText = success
            ? '✓ Güvendeyim mesajı gönderildi'
            : '⚠ Mesaj gönderilemedi';
      });

      // 5 saniye sonra temizle
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) setState(() => _safeResultText = null);
      });
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

  String get _emergencyStatusText {
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

  Color get _emergencyStatusColor {
    switch (_triggerStatus) {
      case TriggerStatus.success: return Colors.green;
      case TriggerStatus.error: return Colors.red;
      case TriggerStatus.fallback: return Colors.orange;
      default: return Colors.white70;
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
      body: Column(
        children: [
          // ── ÜST BÖLÜM: ACİL ──
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF2D0A0A),
                border: Border(
                  bottom: BorderSide(color: Colors.white12, width: 1),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Başlık
                  const Text(
                    'ACİL YARDIM',
                    style: TextStyle(
                      color: Color(0xFFE63946),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Buton
                  _HoldButton(
                    holdController: _emergencyHoldController,
                    pulseController: _pulseController,
                    pulseAnimation: _pulseAnimation,
                    isHolding: _isEmergencyHolding,
                    isActive: _isActive,
                    isTriggering: _triggerStatus != TriggerStatus.idle,
                    color: const Color(0xFFE63946),
                    icon: Icons.warning_rounded,
                    label: 'ACİL',
                    sublabel: _isEmergencyHolding ? 'Bırakma...' : '3 sn basılı tut',
                    onHoldStart: _startEmergencyHold,
                    onHoldEnd: _cancelEmergencyHold,
                    onHoldCancel: _cancelEmergencyHold,
                  ),

                  const SizedBox(height: 16),

                  // Durum mesajı
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _triggerStatus != TriggerStatus.idle
                        ? Container(
                            key: ValueKey(_triggerStatus),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _emergencyStatusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _emergencyStatusColor.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_triggerStatus == TriggerStatus.gettingGps ||
                                    _triggerStatus == TriggerStatus.calling)
                                  SizedBox(
                                    width: 14, height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _emergencyStatusColor,
                                    ),
                                  ),
                                if (_triggerStatus == TriggerStatus.gettingGps ||
                                    _triggerStatus == TriggerStatus.calling)
                                  const SizedBox(width: 8),
                                Text(
                                  _emergencyStatusText,
                                  style: TextStyle(
                                    color: _emergencyStatusColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox(height: 36),
                  ),
                ],
              ),
            ),
          ),

          // ── ALT BÖLÜM: GÜVENDEYİM ──
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFF0A2D0F),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Başlık
                  const Text(
                    'GÜVENDEYİM',
                    style: TextStyle(
                      color: Color(0xFF2ECC71),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Buton
                  _HoldButton(
                    holdController: _safeHoldController,
                    pulseController: _pulseController,
                    pulseAnimation: _pulseAnimation,
                    isHolding: _isSafeHolding,
                    isActive: true,
                    isTriggering: false,
                    color: const Color(0xFF2ECC71),
                    icon: _isSafeSending ? Icons.hourglass_top : Icons.check_circle,
                    label: 'GÜVENDEYİM',
                    sublabel: _isSafeSending
                        ? 'Gönderiliyor...'
                        : (_isSafeHolding ? 'Bırakma...' : '3 sn basılı tut'),
                    onHoldStart: _startSafeHold,
                    onHoldEnd: _cancelSafeHold,
                    onHoldCancel: _cancelSafeHold,
                  ),

                  const SizedBox(height: 16),

                  // Sonuç mesajı
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _safeResultText != null
                        ? Container(
                            key: ValueKey(_safeResultText),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: (_safeResultText!.startsWith('✓')
                                      ? Colors.green
                                      : Colors.red)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: (_safeResultText!.startsWith('✓')
                                        ? Colors.green
                                        : Colors.red)
                                    .withOpacity(0.5),
                              ),
                            ),
                            child: Text(
                              _safeResultText!,
                              style: TextStyle(
                                color: _safeResultText!.startsWith('✓')
                                    ? Colors.green
                                    : Colors.red,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : const SizedBox(height: 36),
                  ),
                ],
              ),
            ),
          ),
        ],
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
            _helpItem(Icons.warning_rounded, 'ACİL Butonu',
                '3 saniye basılı tutunca GPS konumunuzla birlikte tüm acil kişilere WhatsApp mesajı gönderilir.'),
            _helpItem(Icons.check_circle, 'GÜVENDEYİM Butonu',
                '3 saniye basılı tutunca tüm acil kişilere güvende olduğunuz bildirilir.'),
            _helpItem(Icons.radio_button_checked, 'AB Shutter 3 — iOS',
                'Ses açma (+) 2 kez hızlıca bas → ACİL.\nSes kapatma (−) 2 kez hızlıca bas → GÜVENDEYİM.\nEkran kilitliyken de çalışır. Uygulama AKTİF olmalı.'),
            _helpItem(Icons.radio_button_checked, 'AB Shutter 3 — Android',
                'Ses açma (+) 3 saniye basılı tut → ACİL.\nSes kapatma (−) 3 saniye basılı tut → GÜVENDEYİM.\nEkran kilitliyken çalışması için Erişilebilirlik iznini ve "Her zaman izin ver" konum iznini etkinleştirin.'),
            _helpItem(Icons.settings, 'Ayarlar',
                'Sağ üstten acil kişi ekleyebilir, mesaj şablonunu düzenleyebilirsiniz.'),
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

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    _triggerStatusSubscription?.cancel();
    _btTriggerSubscription?.cancel();
    _pulseController.dispose();
    _emergencyHoldController.dispose();
    _safeHoldController.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────
// Basılı tut butonu
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
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Dolum halkası
                SizedBox(
                  width: 180,
                  height: 180,
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
                  width: 164,
                  height: 164,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: effectiveColor,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: (isHolding ? Colors.white : effectiveColor).withOpacity(0.4),
                              blurRadius: isHolding ? 40 : 20,
                              spreadRadius: isHolding ? 10 : 5,
                            )
                          ]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: Colors.white, size: 44),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sublabel,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 10,
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
