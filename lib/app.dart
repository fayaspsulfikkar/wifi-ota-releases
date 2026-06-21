import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'core/theme.dart';
import 'core/app_theme.dart';
import 'screens/flashlight_stealth_screen.dart';
import 'providers/settings_provider.dart';
import 'providers/webrtc_provider.dart';
import 'providers/presence_provider.dart';
import 'providers/auth_provider.dart';
import 'services/notification_service.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class WifiApp extends ConsumerStatefulWidget {
  const WifiApp({super.key});

  @override
  ConsumerState<WifiApp> createState() => _WifiAppState();
}

class _WifiAppState extends ConsumerState<WifiApp> with WidgetsBindingObserver {
  bool _notificationsInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize notifications post-frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initNotifications();
    });
  }

  Future<void> _initNotifications() async {
    if (_notificationsInitialized) return;
    try {
      await ref.read(notificationServiceProvider).initialize();
      _notificationsInitialized = true;
    } catch (e) {
      debugPrint('[App] Error initializing notifications: $e');
    }
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = ref.read(settingsProvider);
    final webrtcService = ref.read(webrtcServiceProvider);
    final presenceService = ref.read(presenceServiceProvider);

    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      // App went to background -> check if telemetry cutoff (muteOnBackground) is enabled
      final prefs = ref.read(sharedPrefsProvider);
      final shouldMute = prefs.getBool('muteOnBackground') ?? true;
      presenceService.updateBackgroundState(true);
      if (shouldMute) {
        webrtcService.muteAllIncomingAudio(true);
      }
    } else if (state == AppLifecycleState.resumed) {
      // App came to foreground -> unmute incoming speakers
      presenceService.updateBackgroundState(false);
      webrtcService.muteAllIncomingAudio(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth state
    ref.listen(currentUserProvider, (prev, next) {
      final user = next.value;
      if (user != null) {
        ref.read(notificationServiceProvider).saveToken(user.userId);
      }
    });

    return WithForegroundTask(
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        title: 'WiFi',
        debugShowCheckedModeBanner: false,
        theme: WifiTheme.darkTheme.copyWith(
          brightness: Brightness.light,
        ),
        darkTheme: WifiTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const FlashlightStealthScreen(),
      ),
    );
  }
}
