// AcilYardım — Uygulama giriş noktası
// Firebase başlatma, kimlik doğrulama akışı, tema ayarları

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';

// Arka planda gelen FCM mesajlarını işle (top-level fonksiyon olmalı)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await _initLocalNotifications();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    runApp(const AcilYardimApp());
  } catch (e, stack) {
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red[50],
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              const Text('Başlatma Hatası',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(e.toString(),
                  style: const TextStyle(fontSize: 14, color: Colors.red)),
              const SizedBox(height: 16),
              Text(stack.toString(),
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ),
    ));
  }
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
  bool _showEmailForm = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegister = false;

  // Apple ile giriş yap
  Future<void> _signInWithApple() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      await FirebaseAuth.instance.signInWithCredential(oauthCredential);
    } catch (e) {
      if (mounted) setState(() { _errorMessage = 'Apple ile giriş başarısız.'; _isLoading = false; });
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'E-posta adresini girin.');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Şifre sıfırlama linki e-postanıza gönderildi.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() {
        _errorMessage = e.code == 'user-not-found'
            ? 'Bu e-posta ile kayıtlı hesap bulunamadı.'
            : e.message ?? 'Şifre sıfırlama başarısız.';
        _isLoading = false;
      });
    }
  }

  // Email ile giriş/kayıt
  Future<void> _signInWithEmail() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      if (_isRegister) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() {
        _errorMessage = e.message ?? 'Giriş başarısız.';
        _isLoading = false;
      });
    }
  }

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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom -
                  64,
            ),
            child: IntrinsicHeight(
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

              if (_showEmailForm) ...[
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'E-posta',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Şifre',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signInWithEmail,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE63946), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text(_isRegister ? 'Hesap Oluştur' : 'Giriş Yap', style: const TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isRegister = !_isRegister),
                  child: Text(_isRegister ? 'Zaten hesabım var' : 'Yeni hesap oluştur', style: const TextStyle(color: Colors.white54)),
                ),
                if (!_isRegister)
                  TextButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    child: const Text('Şifremi Unuttum', style: TextStyle(color: Colors.white38)),
                  ),
                TextButton(
                  onPressed: () => setState(() => _showEmailForm = false),
                  child: const Text('Geri', style: TextStyle(color: Colors.white38)),
                ),
              ] else ...[
                // Google butonu
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                    label: Text(_isLoading ? 'Giriş yapılıyor...' : 'Google ile Giriş Yap', style: const TextStyle(fontSize: 16)),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
                const SizedBox(height: 12),
                // Apple butonu
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signInWithApple,
                    icon: const Icon(Icons.apple),
                    label: const Text('Apple ile Giriş Yap', style: TextStyle(fontSize: 16)),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
                const SizedBox(height: 12),
                // Email butonu
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : () => setState(() => _showEmailForm = true),
                    icon: const Icon(Icons.email_outlined),
                    label: const Text('E-posta ile Giriş Yap', style: TextStyle(fontSize: 16)),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Gizlilik notu
              const Text(
                'Konumunuz yalnızca acil durum anında\npaylaşılır ve saklanmaz.',
                style: TextStyle(color: Colors.white30, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('https://www.guvendeyim.net.tr');
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: const Text(
                  'www.guvendeyim.net.tr',
                  style: TextStyle(color: Color(0xFF2ECC71), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
