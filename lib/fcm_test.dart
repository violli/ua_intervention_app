import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const FcmApp());
}

class FcmApp extends StatefulWidget {
  const FcmApp({super.key});

  @override
  State<FcmApp> createState() => _FcmAppState();
}

class _FcmAppState extends State<FcmApp> {
  String? _token;

  @override
  void initState() {
    super.initState();
    _initFCM();
  }

  Future<void> _initFCM() async {
    // Запрос разрешений (только для iOS, на Android не мешает)
    await FirebaseMessaging.instance.requestPermission();

    // Получение токена
    String? token = await FirebaseMessaging.instance.getToken();
    setState(() {
      _token = token;
    });
    debugPrint("🔥 FCM Token: $token");
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text("FCM Test")),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              _token ?? "Получение токена...",
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
