/// Foreground service for maintaining WebRTC connection in the background.
///
/// Uses flutter_foreground_task to run a persistent foreground service
/// with boot receiver support and wake lock.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Initialize foreground task settings.
void initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'wifi_voice_room',
      channelName: 'Flashlight',
      channelDescription: 'Maintains flashlight state',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(30000), // 30s health checks
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

/// Start the foreground service.
Future<ServiceRequestResult> startForegroundService() async {
  if (await FlutterForegroundTask.isRunningService) {
    return await FlutterForegroundTask.restartService();
  }

  return await FlutterForegroundTask.startService(
    notificationTitle: 'Flashlight',
    notificationText: 'Running',
    callback: startCallback,
  );
}

/// Stop the foreground service.
Future<ServiceRequestResult> stopForegroundService() async {
  return await FlutterForegroundTask.stopService();
}

/// Update the notification text.
Future<void> updateNotification(String text) async {
  FlutterForegroundTask.updateService(
    notificationTitle: 'Flashlight',
    notificationText: text,
  );
}

// This function is called from the native side to start the task handler.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(WifiTaskHandler());
}

/// Task handler that runs in the foreground service.
class WifiTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundService] Started at $timestamp by $starter');
  }

  /// Called every 30 seconds to perform health checks.
  @override
  void onRepeatEvent(DateTime timestamp) {
    debugPrint('[ForegroundService] Health check at $timestamp');
    // The main app handles reconnection via providers.
    // This just keeps the process alive.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[ForegroundService] Destroyed at $timestamp');
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('[ForegroundService] Received data: $data');
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('[ForegroundService] Button pressed: $id');
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/home');
  }

  @override
  void onNotificationDismissed() {
    debugPrint('[ForegroundService] Notification dismissed');
  }
}
