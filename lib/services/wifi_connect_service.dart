/// Dart service wrapping the native Wi-Fi connection method channel.
library;

import 'package:flutter/services.dart';

class WifiConnectService {
  static const _channel = MethodChannel('wifi_connect');

  /// Connect to a Wi-Fi network.
  /// On Android 10+, this shows a system dialog to the user.
  /// Returns true if the connection was successful.
  static Future<bool> connect(String ssid, {String password = '', bool isOpen = false}) async {
    try {
      final result = await _channel.invokeMethod<bool>('connect', {
        'ssid': ssid,
        'password': password,
        'isOpen': isOpen,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Disconnect from the current Wi-Fi network.
  static Future<bool> disconnect() async {
    try {
      final result = await _channel.invokeMethod<bool>('disconnect');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Get the SSID of the currently connected Wi-Fi network.
  static Future<String?> getConnectedSSID() async {
    try {
      return await _channel.invokeMethod<String?>('getConnectedSSID');
    } catch (e) {
      return null;
    }
  }
}
