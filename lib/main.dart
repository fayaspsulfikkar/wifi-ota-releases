/// WiFi — Persistent Private Audio Room Application
///
/// Entry point that initializes Firebase and starts the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'services/foreground_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/settings_provider.dart';

void main() async {
  // Wrap everything in a try-catch to display initialization errors on screen
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Lock orientation to portrait
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Set system UI overlay style
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D1117),
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize Analytics
    FirebaseAnalytics analytics = FirebaseAnalytics.instance;
    await analytics.logAppOpen();

    // Initialize foreground task
    initForegroundTask();

    // Initialize SharedPreferences
    final prefs = await SharedPreferences.getInstance();

    runApp(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const WifiApp(),
      ),
    );
  } catch (e, stackTrace) {
    // If it crashes before runApp, show the error directly on screen!
    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                'CRASH ERROR:\n$e\n\nSTACKTRACE:\n$stackTrace',
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
