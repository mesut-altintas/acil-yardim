import 'dart:async';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/trigger_log.dart';
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
  bool _accessibilityEnabled = true; // ignore: unused_field
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
      if (mounted) _logAndShowNotification(message);
    }
  }

  // Gelen bildirimi Firestore'a kaydet ve bottom sheet göster
  void _logAndShowNotification(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] ?? 'emergency';
    final title = message.notification?.title ?? (type == 'safe' ? '✅ GÜVENDEYİM' : '🚨 ACİL YARDIM');
    final body = message.notification?.body ?? '';
    final lat = double.tryParse(data['latitude'] ?? '');
    final lng = double.tryParse(data['longitude'] ?? '');

    // Firestore'a kaydet (async, bekleme)
    _firestoreService.logReceivedAlert(
      type: type,
      title: title,
      body: body,
      latitude: lat,
      longitude: lng,
    );

    _showNotificationSheet(message);
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

    // Ön planda gelen FCM — bottom sheet göster + geçmişe kaydet
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (!mounted) return;
      _logAndShowNotification(message);
    });

    // Arka planda bildirime tıklanınca
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (!mounted) return;
      _logAndShowNotification(message);
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
        title: const Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Acil',
                style: TextStyle(
                  color: Color(0xFFE63946),
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              TextSpan(
                text: 'Yardım',
                style: TextStyle(
                  color: Color(0xFF2ECC71),
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ],
          ),
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
            icon: const Icon(Icons.history, color: Colors.white70),
            onPressed: _showHistory,
            tooltip: 'Son bildirimler',
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Her yarının yüksekliği — başlık + boşluk + durum alanı için 100px bırak
          final halfH = constraints.maxHeight / 2;
          final buttonSize = (halfH - 100).clamp(120.0, 180.0);
      return Column(
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
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: halfH),
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
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
                      size: buttonSize,
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
            ),
          ),

          // ── ALT BÖLÜM: GÜVENDEYİM ──
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFF0A2D0F),
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: halfH),
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
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
                    size: buttonSize,
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
            ),
          ),
        ],
      );
        },
      ),
    );
  }

  void _showLogDetail(BuildContext sheetCtx, log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              log.isSafe ? Icons.check_circle : Icons.warning_rounded,
              color: log.isSafe ? Colors.green : const Color(0xFFE63946),
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              log.isSafe ? 'Güvendeyim' : 'Acil Alarm',
              style: TextStyle(
                color: log.isSafe ? Colors.green : const Color(0xFFE63946),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.white38, size: 14),
                const SizedBox(width: 6),
                Text(log.formattedTime, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.group, color: Colors.white38, size: 14),
                const SizedBox(width: 6),
                Text('${log.contactCount} kişi bilgilendirildi', style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
            if (log.message != null) ...[
              const SizedBox(height: 12),
              const Text('Gönderilen mesaj:', style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(log.message!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ],
            if (log.hasLocation && log.mapsLink != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(log.mapsLink!);
                    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.map, size: 16),
                  label: const Text('Haritada Aç'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE63946),
                    side: const BorderSide(color: Color(0xFFE63946)),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat', style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  // Gönderilen ve gelen bildirimleri birleştir, zamana göre sırala
  Stream<List<TriggerLog>> _mergedLogsStream() {
    final sentStream = _firestoreService.watchTriggerLogs();
    final receivedStream = _firestoreService.watchReceivedAlerts();

    final controller = StreamController<List<TriggerLog>>();
    List<TriggerLog> sent = [];
    List<TriggerLog> received = [];

    void emit() {
      final all = [...sent, ...received];
      all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (!controller.isClosed) controller.add(all);
    }

    final s1 = sentStream.listen((data) { sent = data; emit(); }, onError: controller.addError);
    final s2 = receivedStream.listen((data) { received = data; emit(); }, onError: controller.addError);

    controller.onCancel = () { s1.cancel(); s2.cancel(); };

    return controller.stream;
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.history, color: Colors.white70, size: 20),
                  SizedBox(width: 8),
                  Text('Son Bildirimler',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder(
                stream: _mergedLogsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFFE63946)));
                  }
                  final logs = (snapshot.data ?? []).take(20).toList();
                  if (logs.isEmpty) {
                    return const Center(
                      child: Text('Henüz bildirim yok', style: TextStyle(color: Colors.white38)),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: logs.length,
                    itemBuilder: (_, i) {
                      final log = logs[i];
                      return GestureDetector(
                        onTap: () => _showLogDetail(ctx, log),
                        child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFE63946).withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  log.isSafe ? Icons.check_circle : Icons.warning_rounded,
                                  color: log.isSafe ? Colors.green : const Color(0xFFE63946),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  log.isSafe ? 'Güvendeyim' : 'Acil Alarm',
                                  style: TextStyle(
                                    color: log.isSafe ? Colors.green : const Color(0xFFE63946),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: log.isReceived
                                        ? Colors.blue.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    log.isReceived ? 'Gelen' : 'Gönderilen',
                                    style: TextStyle(
                                      color: log.isReceived ? Colors.blue[300] : Colors.white54,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  log.formattedTime,
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                                const Spacer(),
                                if (log.contactCount > 0)
                                  Text(
                                    '${log.contactCount} kişi',
                                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                                  ),
                              ],
                            ),
                            if (log.hasLocation && log.mapsLink != null) ...[
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () async {
                                  final uri = Uri.parse(log.mapsLink!);
                                  if (await canLaunchUrl(uri)) {
                                    launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                },
                                child: Row(
                                  children: [
                                    const Icon(Icons.location_on, color: Color(0xFFE63946), size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${log.latitude!.toStringAsFixed(4)}, ${log.longitude!.toStringAsFixed(4)}',
                                      style: const TextStyle(color: Color(0xFFE63946), fontSize: 12),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.open_in_new, color: Color(0xFFE63946), size: 12),
                                  ],
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 4),
                              const Text('Konum alınamadı', style: TextStyle(color: Colors.white38, fontSize: 12)),
                            ],
                          ],
                        ),
                      ));
                    },
                  );
                },
              ),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _showHelp() {
    final isIOS = Platform.isIOS;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Başlık
              Row(
                children: [
                  const Icon(Icons.help_outline, color: Color(0xFF2ECC71), size: 24),
                  const SizedBox(width: 10),
                  Text(
                    isIOS ? 'Kullanım Kılavuzu — iPhone' : 'Kullanım Kılavuzu — Android',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── TEMEL KULLANIM ──
              _helpSection('TEMEL KULLANIM'),
              _helpItem(Icons.warning_rounded, 'ACİL Butonu',
                  '3 saniye basılı tutun.\n'
                  'GPS konumunuzla birlikte tüm aktif acil kişilere:\n'
                  '  • WhatsApp mesajı gönderilir\n'
                  '  • Uygulama bildirimi (FCM) iletilir\n'
                  '  • SMS gönderilir (${isIOS ? 'iOS desteklemez' : 'Android'})\n'
                  '  • Telefon araması başlatılır (ayarlandıysa)'),
              _helpItem(Icons.check_circle, 'GÜVENDEYİM Butonu',
                  '3 saniye basılı tutun.\n'
                  'Tüm aktif acil kişilere "güvende" mesajı gönderilir.\n'
                  'Endişelenmeyin mesajının ardından rahatlama bildirimi iletilir.'),
              _helpItem(Icons.history, 'Geçmiş',
                  'Ekranın üst kısmındaki saat ikonuna basın.\n'
                  'Gönderdiğiniz ve aldığınız tüm acil bildirimler listelenir.'),

              const SizedBox(height: 8),

              // ── AB SHUTTER 3 (platform bazlı) ──
              _helpSection('AB SHUTTER 3 BLUETOOTH DÜĞME'),
              if (isIOS) ...[
                _helpItem(Icons.bluetooth, 'Bağlantı',
                    '1. iPhone\'un Bluetooth\'unu açın.\n'
                    '2. AB Shutter 3\'ün pil kapağını açıp kapatarak uyandırın.\n'
                    '3. iPhone Ayarlar → Bluetooth\'ta "AB Shutter3" görününce eşleştirin.'),
                _helpItem(Icons.touch_app, 'Kullanım',
                    'Ses açma (+) düğmesi → ACİL\n'
                    'Ses kapatma (−) düğmesi → GÜVENDEYİM\n\n'
                    'Ekran kilitliyken de çalışır.\n'
                    'Uygulama arka planda veya ön planda AKTİF olmalı.\n'
                    'Uygulamayı tamamen kapatırsanız (uygulama yöneticisinden silerseniz) çalışmaz.'),
                _helpItem(Icons.battery_alert, 'Pil & Sorun Giderme',
                    '• Düğme yanıt vermiyorsa pili yenileyin (CR2032).\n'
                    '• Bluetooth bağlantısı kopuksa telefon yakında tutun (≤10 m).\n'
                    '• Eşleştirmeyi kaldırıp tekrar bağlayın.\n'
                    '• Uygulamayı kapatıp yeniden açın.'),
              ] else ...[
                _helpItem(Icons.bluetooth, 'Bağlantı',
                    '1. Android Bluetooth\'u açın.\n'
                    '2. AB Shutter 3\'ü uyandırın (pil kapağı).\n'
                    '3. Ayarlar → Bluetooth → "AB Shutter3"\'ü seçip eşleştirin.'),
                _helpItem(Icons.touch_app, 'Kullanım',
                    'Ses açma (+) 3 sn basılı tut → ACİL\n'
                    'Ses kapatma (−) 3 sn basılı tut → GÜVENDEYİM\n\n'
                    'Normal (kısa) basış ses kontrolü yapar, tetikleme yapmaz.'),
                _helpItem(Icons.lock_open, 'Kilitli Ekranda Çalışma',
                    'Kilitli ekranda tetikleme için:\n'
                    '1. Erişilebilirlik iznini etkinleştirin:\n'
                    '   Ayarlar → Erişilebilirlik → Yüklü Uygulamalar\n'
                    '   → Güvendeyim Ses Tuşu → Aç\n'
                    '2. Konum iznini "Her zaman izin ver" yapın:\n'
                    '   Ayarlar → Uygulamalar → Güvendeyim\n'
                    '   → İzinler → Konum → Her zaman izin ver\n'
                    '3. Pil optimizasyonunu kapatın:\n'
                    '   Ayarlar → Pil → Güvendeyim → Kısıtlama yok'),
                _helpItem(Icons.battery_alert, 'Pil & Sorun Giderme',
                    '• APK güncellemesinden sonra Erişilebilirlik iznini\n'
                    '  yeniden açmanız gerekir (Android güvenlik kısıtı).\n'
                    '• Düğme yanıt vermiyorsa pili yenileyin (CR2032).\n'
                    '• Bağlantı kopuksa Bluetooth\'u kapatıp açın.'),
              ],

              const SizedBox(height: 8),

              // ── AYARLAR ──
              _helpSection('AYARLAR'),
              _helpItem(Icons.person_add, 'Acil Kişi Ekleme',
                  'Sağ üstteki ⚙ ikonuna basın.\n'
                  '"+" ile yeni kişi ekleyin.\n'
                  'Her kişi için ad, telefon ve bildirim kanallarını seçin.\n'
                  'Checkbox ile kişiyi geçici olarak devre dışı bırakabilirsiniz.'),
              _helpItem(Icons.message, 'Mesaj Şablonu',
                  'Ayarlar\'dan ACİL ve GÜVENDEYİM mesaj metinlerini\n'
                  'kişiselleştirebilirsiniz.\n'
                  '"Arayan Adı" alanı mesajlarda imza olarak görünür.'),
              if (!isIOS)
                _helpItem(Icons.sms, 'WhatsApp Sandbox',
                    'WhatsApp mesajlarını alabilmek için acil kişilerin\n'
                    '"join battle-figure" mesajını\n'
                    '+1 415 523 8886 numarasına WhatsApp\'tan göndermesi gerekir.\n'
                    'Bu adım tamamlanana kadar WhatsApp bildirimleri iletilmez.'),
              if (isIOS)
                _helpItem(Icons.sms, 'WhatsApp Sandbox',
                    'WhatsApp mesajlarını alabilmek için acil kişilerin\n'
                    '"join battle-figure" mesajını\n'
                    '+1 415 523 8886 numarasına WhatsApp\'tan göndermesi gerekir.'),

              const SizedBox(height: 8),

              // ── BİLDİRİM ALIMLARI ──
              _helpSection(isIOS ? 'BİLDİRİM AYARLARI — iPhone' : 'BİLDİRİM AYARLARI — Android'),
              if (isIOS) ...[
                _helpItem(Icons.notifications_active, 'Bildirim İzni',
                    'Uygulama ilk açıldığında bildirim izni ister.\n'
                    'İzin vermediyseniz:\n'
                    'iPhone Ayarlar → Güvendeyim → Bildirimler → İzin Ver'),
                _helpItem(Icons.do_not_disturb_off, 'Odaklanma Modu',
                    'iPhone\'un "Rahatsız Etme" veya Odaklanma modu açıksa\n'
                    'acil bildirimler engellenebilir.\n'
                    'Ayarlar → Odaklanma → İzin Verilen Uygulamalar\'a Güvendeyim\'i ekleyin.'),
              ] else ...[
                _helpItem(Icons.notifications_active, 'Bildirim İzni',
                    'Uygulama ilk açıldığında bildirim izni ister.\n'
                    'İzin vermediyseniz:\n'
                    'Ayarlar → Uygulamalar → Güvendeyim → Bildirimler → Aç'),
                _helpItem(Icons.battery_saver, 'Pil Tasarrufu',
                    'Pil tasarrufu bildirimleri geciktirebilir.\n'
                    'Ayarlar → Pil → Güvendeyim → Kısıtlama yok\n'
                    'veya Arka plan veri kullanımına izin verin.'),
              ],

              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('https://www.guvendeyim.net.tr');
                  if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: const Text('www.guvendeyim.net.tr',
                    style: TextStyle(color: Color(0xFF2ECC71), fontSize: 13)),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('mailto:bilgi@guvendeyim.net.tr');
                  if (await canLaunchUrl(uri)) launchUrl(uri);
                },
                child: const Text('bilgi@guvendeyim.net.tr',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helpSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF2ECC71),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _helpItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFE63946), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 3),
                Text(desc,
                    style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.5)),
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
  final double size;

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
    this.size = 180,
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
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Dolum halkası
                SizedBox(
                  width: size,
                  height: size,
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
                  width: size * 0.91,
                  height: size * 0.91,
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
