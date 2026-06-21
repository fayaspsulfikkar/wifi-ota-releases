/// Utility functions for WiFi voice room application.
library;

import 'dart:math';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'constants.dart';

const _uuid = Uuid();

/// Generate a random pairing code (6-char uppercase alphanumeric).
String generatePairingCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Removed ambiguous: I,O,0,1
  final random = Random.secure();
  return List.generate(
    kPairingCodeLength,
    (_) => chars[random.nextInt(chars.length)],
  ).join();
}

/// Generate a unique device ID.
String generateDeviceId() => _uuid.v4();

/// Generate a unique room ID.
String generateRoomId() => _uuid.v4();

/// Copy text to clipboard and return true if successful.
Future<bool> copyToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}

/// Format a DateTime to a human-readable string.
String formatTimestamp(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);

  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';

  return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}
