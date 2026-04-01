// AcilYardım — Uygulama giriş noktası
// Firebase başlatma, kimlik doğrulama akışı, tema ayarları

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'screens/home_screen.dart';

// Arka planda gelen FCM mesajlarını işle (top-level fonksiyon olmalı)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Arka plan FCM mesajı: ${message.messageId}');
  // Arka planda yerel bildirim göster
  await _showLocalNotification(message);
}

// Yerel bildirim eklentisi
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

// Arka plan mesajı için yerel bildirim göster
Future<void> _showLocalNotification(RemoteMessage message) async {
  const androidChannel = AndroidNotificationChannel(
    'emergency_channel',
    'Acil Yardım Bildirimleri',
    description: 'Acil yardım uyarıları için kanal',
    importance: Importance.max,
    playSound: true,
  );

  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);

  await _localNotifications.show(
    message.hashCode,
    message.notification?.title ?? '🚨 ACİL YARDIM',
    message.notification?.body ?? 'Acil yardım bildirimi alındı',
    NotificationDetails(
      android: AndroidNotificationDetails(
        androidChannel.id,
        androidChannel.name,
        channelDescription: androidChannel.description,
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase'i başlat
  await Firebase.initializeApp();

  // Arka plan FCM mesaj handler'ını kaydet
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Yerel bildirimleri başlat
  await _initLocalNotifications();

  // Durum çubuğunu şeffaf yap (Android)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const AcilYardimApp());
}

Future<void> _initLocalNotifications() async {
  const androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  await _localNotifications.initialize(
    const InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    ),
  );
}

class AcilYardimApp extends StatelessWidget {
  const AcilYardimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AcilYardım',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE63946),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      // Firebase Auth durumuna göre ekran göster
      home: const _AuthGate(),
    );
  }
}

// ─────────────────────────────────────────────
// Kimlik doğrulama geçidi
// Giriş yapılmışsa HomeScreen, yapılmamışsa LoginScreen göster
// ─────────────────────────────────────────────
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Yükleniyor
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1A1A2E),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFE63946)),
            ),
          );
        }

        // Giriş yapılmış — ana ekrana git
        if (snapshot.hasData) {
          return const HomeScreen();
        }

        // Giriş yapılmamış — giriş ekranını göster
        return const _LoginScreen();
      },
    );
  }
}

// ─────────────────────────────────────────────
// Giriş ekranı — Google ile giriş
// ─────────────────────────────────────────────
class _LoginScreen extends StatefulWidget {
  const _LoginScreen();

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  // Google ile giriş yap
  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Google giriş akışını başlat
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // Kullanıcı iptal etti
        setState(() => _isLoading = false);
        return;
      }

      // Google kimlik doğrulama bilgilerini al
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Firebase kimlik bilgisi oluştur
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Firebase ile giriş yap
      await FirebaseAuth.instance.signInWithCredential(credential);

      debugPrint('Giriş başarılı: ${googleUser.displayName}');
    } catch (e) {
      debugPrint('Giriş hatası: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Giriş yapılamadı. Lütfen tekrar deneyin.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo / İkon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE63946).withOpacity(0.1),
                  border: Border.all(
                    color: const Color(0xFFE63946).withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.shield,
                  size: 60,
                  color: Color(0xFFE63946),
                ),
              ),

              const SizedBox(height: 32),

              // Uygulama adı
              const Text(
                'AcilYardım',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'AB Shutter 3 ile anında acil yardım',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 64),

              // Hata mesajı
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Google ile giriş butonu
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(
                    _isLoading ? 'Giriş yapılıyor...' : 'Google ile Giriş Yap',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Gizlilik notu
              const Text(
                'Konumunuz yalnızca acil durum anında\npaylaşılır ve saklanmaz.',
                style: TextStyle(color: Colors.white30, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
