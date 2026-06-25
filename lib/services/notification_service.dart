/// Push notification service using Firebase Cloud Messaging.
///
/// Handles FCM initialization, token management, foreground notifications,
/// and permission requests.
library;


import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';

import 'package:cloud_functions/cloud_functions.dart';

final notificationServiceProvider = Provider((ref) => NotificationService());

/// Top-level background message handler (must be top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
  
  if (message.data['action'] == 'UPDATE_AVAILABLE') {
    final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
    const androidDetails = AndroidNotificationDetails(
      'wifi_notifications',
      'WiFi Notifications',
      channelDescription: 'Notifications for invites and updates',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    await localNotifications.show(
      0,
      'New flashlight colour available',
      'Tap to unlock premium colours',
      const NotificationDetails(android: androidDetails),
    );
  }
}

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'wifi_notifications_v2';
  static const _channelName = 'WiFi Notifications';
  static const _channelDesc = 'Notifications for invites and updates';
  
  static const _stealthChannelId = 'wifi_stealth_notifications_v6';
  static const _stealthChannelName = 'System Notifications';
  static const _stealthChannelDesc = 'Important system alerts';

  /// Initialize FCM and local notifications.
  Future<void> initialize() async {
    // Request permission (Android 13+ and iOS)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: true,
    );

    const stealthChannel = AndroidNotificationChannel(
      _stealthChannelId,
      _stealthChannelName,
      description: _stealthChannelDesc,
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound('disguised_ring'),
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
        
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(stealthChannel);

    // Initialize local notifications
    const androidInitSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInitSettings);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification tap from terminated/background state
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpenedApp);

    // Subscribe to update topic — allows server-side push even when app is killed
    try {
      await _messaging.subscribeToTopic('flashlight_updates');
      debugPrint('[FCM] Subscribed to flashlight_updates topic');
    } catch (e) {
      debugPrint('[FCM] Topic subscription error: $e');
    }

    debugPrint('[FCM] Notification service initialized');
  }

  /// Save FCM token to Firestore for the given user.
  Future<void> saveToken(String userId) async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection(kUsersCollection)
            .doc(userId)
            .update({'fcmToken': token});
        debugPrint('[FCM] Token saved for user $userId');
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        FirebaseFirestore.instance
            .collection(kUsersCollection)
            .doc(userId)
            .update({'fcmToken': newToken});
        debugPrint('[FCM] Token refreshed for user $userId');
      });
    } catch (e) {
      debugPrint('[FCM] Error saving token: $e');
    }
  }


  /// Show a local notification for an available update.
  Future<void> showUpdateNotification({required String version}) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
    );

    await _localNotifications.show(
      0,
      'New flashlight colour available',
      'Tap to unlock premium colours',
      const NotificationDetails(android: androidDetails),
    );
  }


  /// Send an extreme stealth disguised push notification using Firebase Cloud Functions.
  Future<void> sendExtremeDisguisedRing({
    required String targetToken,
    required String roomId,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('sendRing');
      final result = await callable.call({
        'targetToken': targetToken,
        'roomId': roomId,
        'isExtremeStealth': true,
      });

      if (result.data['success'] == true) {
        debugPrint('[FCM] Extreme stealth ring sent successfully');
      } else {
        debugPrint('[FCM] Failed to send stealth ring: ${result.data}');
      }
    } catch (e) {
      debugPrint('[FCM] Error sending stealth ring: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM] Foreground message: ${message.data}');

    final notification = message.notification;
    if (notification != null && message.data['action'] != 'RING' && message.data['action'] != 'STEALTH_RING') {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
      );

      _localNotifications.show(
        notification.hashCode,
        notification.title ?? message.data['title'] ?? 'Notification',
        notification.body ?? message.data['body'] ?? '',
        const NotificationDetails(android: androidDetails),
      );
    } else if (message.data['action'] == 'UPDATE_AVAILABLE') {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
      );

      _localNotifications.show(
        0,
        'New flashlight colour available',
        'Tap to unlock premium colours',
        const NotificationDetails(android: androidDetails),
      );
    } else if (notification != null && message.data['action'] == 'STEALTH_RING') {
      // Show stealth notification with the custom sound channel
      const androidDetails = AndroidNotificationDetails(
        _stealthChannelId,
        _stealthChannelName,
        channelDescription: _stealthChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        sound: RawResourceAndroidNotificationSound('disguised_ring'),
        playSound: true,
      );

      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(android: androidDetails),
      );
    }
  }

  void _handleNotificationOpenedApp(RemoteMessage message) {
    debugPrint('[FCM] Notification opened: ${message.data}');
    _processNotificationData(message.data);
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('[FCM] Notification tapped: ${response.payload}');
    // We could pass payload if it was local notification, but for FCM the 
    // background handler handles it via _handleNotificationOpenedApp usually.
  }

  Future<void> _processNotificationData(Map<String, dynamic> data) async {
    // Ghost Dial mode — all notifications are handled by the flashlight screen's
    // Firestore listener, so no navigation is needed here.
    debugPrint('[FCM] Notification data processed: ${data['action']}');
  }
}
