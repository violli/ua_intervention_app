import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? _qrToken;
  String? _fcmToken;
  bool _isLoading = true;

  late WebViewController _webViewController;
  Timer? _apiTimer;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  @override
  void dispose() {
    _apiTimer?.cancel();
    super.dispose();
  }

  Future<void> _initApp() async {
    final prefs = await SharedPreferences.getInstance();

    // Проверяем сохранённый QR-токен
    String? savedQrToken = prefs.getString("qr_token");
    if (savedQrToken != null) {
      setState(() {
        _qrToken = savedQrToken;
      });
    }

    // Настраиваем FCM
    await _initFCM();

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _initFCM() async {
    final prefs = await SharedPreferences.getInstance();

    // Проверяем сохранённый FCM-токен
    String? savedFcmToken = prefs.getString("fcm_token");
    if (savedFcmToken != null) {
      _fcmToken = savedFcmToken;
      return;
    }

    try {
      // Запрашиваем разрешения
      await FirebaseMessaging.instance.requestPermission();

      // Получаем новый FCM-токен
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        _fcmToken = token;
        await prefs.setString("fcm_token", token);

        // Подписка на топик "all"
        await FirebaseMessaging.instance.subscribeToTopic("all");

        // Отправляем токен на сервер WP
        await _sendTokenToServer(token);
      }
    } catch (e) {
      debugPrint("Ошибка FCM: $e");
    }
  }

  Future<void> _sendTokenToServer(String token) async {
    final url =
        Uri.parse("https://uaintervention.org.ua/wp-json/ua-push/v1/register");
    try {
      final res = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"token": token}),
      );
      debugPrint("Отправка токена на WP: ${res.statusCode} ${res.body}");
    } catch (e) {
      debugPrint("Ошибка отправки токена: $e");
    }
  }

  Future<void> _saveQrToken(String token) async {
    final prefs = await SharedPreferences.getInstance();

    // Если QR содержит ссылку с параметром fta_token=, вырезаем значение токена
    if (token.contains("fta_token=")) {
      try {
        final uri = Uri.parse(token);
        token = uri.queryParameters["fta_token"] ?? token;
      } catch (_) {}
    }

    await prefs.setString("qr_token", token);
    setState(() {
      _qrToken = token;
    });
  }

  /// Подключаем JS и Flutter-пинг для обновления бейджей
  void _injectBadgeUpdater() {
    final token = _qrToken ?? "";

    final jsCode = """
      (function() {
        async function updateBadges() {
          try {
            const headers = { "X-FTA-Token": "$token" };

            // 🔹 Обновляем чат
            const chatRes = await fetch(
              'https://uaintervention.org.ua/wp-json/fluent-community/v2/chat/unread_threads',
              { headers }
            );
            if (chatRes.ok) {
              const chatData = await chatRes.json();
              const unreadThreads = chatData?.unread_threads ? Object.keys(chatData.unread_threads).length : 0;
              const chatEl = document.querySelector('.fcomc_unread_badge');
              if (chatEl) {
                chatEl.style.display = unreadThreads > 0 ? 'inline-flex' : 'none';
                chatEl.textContent = unreadThreads;
              }
              console.log("💬 Chat unread:", unreadThreads);
            } else {
              console.log("Chat API error:", chatRes.status);
            }

            // 🔹 Обновляем уведомления
            const notifRes = await fetch(
              'https://uaintervention.org.ua/wp-json/fluent-community/v2/notifications/unread',
              { headers }
            );
            if (notifRes.ok) {
              const notifData = await notifRes.json();
              const unreadCount = notifData?.unread_count ?? 0;
              const notifEl = document.querySelector('sup.el-badge__content.el-badge__content--danger');
              if (notifEl) {
                notifEl.style.display = unreadCount > 0 ? 'inline-flex' : 'none';
                notifEl.textContent = unreadCount;
              }
              console.log("🔔 Notifications unread:", unreadCount);
            } else {
              console.log("Notif API error:", notifRes.status);
            }

          } catch (e) {
            console.error("Badge update error", e);
          }
        }

        updateBadges();
        setInterval(updateBadges, 15000);
      })();
    """;

    _webViewController.runJavaScript(jsCode);

    // 🔹 Flutter-пинг каждые 30 секунд (с X-FTA-Token)
    _apiTimer?.cancel();
    _apiTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final headers = {"X-FTA-Token": token};
        final chatRes = await http.get(
          Uri.parse("https://uaintervention.org.ua/wp-json/fluent-community/v2/chat/unread_threads"),
          headers: headers,
        );
        final notifRes = await http.get(
          Uri.parse("https://uaintervention.org.ua/wp-json/fluent-community/v2/notifications/unread"),
          headers: headers,
        );

        debugPrint("Chat API: ${chatRes.body}");
        debugPrint("Notif API: ${notifRes.body}");
      } catch (e) {
        debugPrint("Ошибка API-пинга: $e");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Если QR-токена нет — показываем сканер
    if (_qrToken == null) {
      return MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text("Сканируй QR для входа")),
          body: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _saveQrToken(barcode.rawValue!);
                  break;
                }
              }
            },
          ),
        ),
      );
    }

    // Если токен есть — открываем WebView с автообновлением бейджей
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: WebViewWidget(
            controller: _webViewController = WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..setNavigationDelegate(
                NavigationDelegate(
                  onPageFinished: (url) {
                    _injectBadgeUpdater();
                  },
                ),
              )
              ..loadRequest(Uri.parse(
                  "https://uaintervention.org.ua/app/?fta_login=1&fta_token=$_qrToken")),
          ),
        ),
      ),
    );
  }
}
