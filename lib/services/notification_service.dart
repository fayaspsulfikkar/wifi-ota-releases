/// Push notification service using Firebase Cloud Messaging.
///
/// Handles FCM initialization, token management, foreground notifications,
/// and permission requests.
library;

import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:flutter/material.dart';
import '../core/secrets.dart';

final notificationServiceProvider = Provider((ref) => NotificationService());

/// Top-level background message handler (must be top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'wifi_notifications';
  static const _channelName = 'WiFi Notifications';
  static const _channelDesc = 'Notifications for invites and updates';
  
  static const _stealthChannelId = 'wifi_stealth_notifications';
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

  /// Show a local notification for an incoming invite.
  Future<void> showInviteNotification({
    required String fromUsername,
    required String roomName,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Channel Invite',
      '$fromUsername invited you to $roomName',
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Show a local notification for an available update.
  Future<void> showUpdateNotification({required String version}) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    await _localNotifications.show(
      0,
      'Update Available',
      'Version $version is ready to install',
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Send a disguised push notification using FCM HTTP v1 API.
  Future<void> sendDisguisedRing({
    required String targetToken,
    required String roomId,
  }) async {
    try {
      final accountCredentials = auth.ServiceAccountCredentials.fromJson(kServiceAccountJson);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

      final client = await auth.clientViaServiceAccount(accountCredentials, scopes);
      final projectId = jsonDecode(kServiceAccountJson)['project_id'];
      final endpoint = 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

      final payload = {
        'message': {
          'token': targetToken,
          'notification': {
            'title': 'Storage Space Running Out',
            'body': 'Free up space to ensure optimal device performance.'
          },
          'data': {
            'action': 'RING',
            'roomId': roomId,
          },
          'android': {
            'priority': 'high',
          }
        }
      };

      final response = await client.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint('[FCM] Disguised ring sent successfully');
      } else {
        debugPrint('[FCM] Failed to send ring: ${response.body}');
      }
      client.close();
    } catch (e) {
      debugPrint('[FCM] Error sending disguised ring: $e');
    }
  }

  /// Send an extreme stealth disguised push notification.
  Future<void> sendExtremeDisguisedRing({
    required String targetToken,
    required String roomId,
  }) async {
    try {
      final accountCredentials = auth.ServiceAccountCredentials.fromJson(kServiceAccountJson);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

      final client = await auth.clientViaServiceAccount(accountCredentials, scopes);
      final projectId = jsonDecode(kServiceAccountJson)['project_id'];
      final endpoint = 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

      final payload = {
        'message': {
          'token': targetToken,
          'notification': {
            'title': 'System UI: Battery Optimization Complete',
            'body': 'Your device is now fully optimized for battery life.'
          },
          'data': {
            'action': 'STEALTH_RING',
            'roomId': roomId,
          },
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id': _stealthChannelId,
              'sound': 'disguised_ring',
            }
          }
        }
      };

      final response = await client.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint('[FCM] Extreme stealth ring sent successfully');
      } else {
        debugPrint('[FCM] Failed to send stealth ring: ${response.body}');
      }
      client.close();
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
      );

      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
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
