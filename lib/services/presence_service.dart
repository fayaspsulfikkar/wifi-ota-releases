/// Presence service for tracking online/offline status and mic/listening state.
///
/// Uses a heartbeat mechanism to detect stale sessions.
library;

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants.dart';
import '../services/firestore_service.dart';

class PresenceData {
  final bool online;
  final bool micOn;
  final bool listeningOn;
  final int batteryLevel;
  final bool inBackground;
  final DateTime lastSeen;

  const PresenceData({
    required this.online,
    required this.micOn,
    required this.listeningOn,
    required this.batteryLevel,
    this.inBackground = false,
    required this.lastSeen,
  });

  factory PresenceData.fromMap(Map<String, dynamic> data) {
    return PresenceData(
      online: data['online'] ?? false,
      micOn: data['micOn'] ?? false,
      listeningOn: data['listeningOn'] ?? false,
      batteryLevel: data['batteryLevel'] ?? 100,
      inBackground: data['inBackground'] ?? false,
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Check if the presence is stale (no heartbeat within timeout).
  bool get isStale =>
      DateTime.now().difference(lastSeen) > kPresenceTimeout;
}

class PresenceService {
  final FirestoreService _firestoreService;
  final Battery _battery = Battery();
  Timer? _heartbeatTimer;
  Timer? _telemetryTimer;
  String? _userId;
  DateTime? _sessionStartTime;
  bool _inBackground = false;

  PresenceService(this._firestoreService);

  /// Go online and start heartbeat.
  Future<void> goOnline(String userId, {bool initialMicOn = true}) async {
    _userId = userId;

    int batteryLevel = 100;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {}

    double? latitude;
    double? longitude;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 3),
        );
        latitude = pos.latitude;
        longitude = pos.longitude;
      }
    } catch (_) {}

    _sessionStartTime = DateTime.now();

    await _firestoreService.setPresence(userId, {
      'online': true,
      'micOn': initialMicOn,
      'listeningOn': false,
      'batteryLevel': batteryLevel,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'inBackground': _inBackground,
      'sessionStartTime': Timestamp.fromDate(_sessionStartTime!),
      'lastSeen': Timestamp.now(),
    });

    // Start heartbeat
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(kHeartbeatInterval, (_) {
      _sendHeartbeat();
    });

    // Start telemetry sync (1 min periodic)
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _syncTelemetry();
    });
    // Fire it once immediately
    _syncTelemetry();

    debugPrint('[Presence] Online: $userId');
  }

  /// Go offline and stop heartbeat.
  Future<void> goOffline() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _telemetryTimer?.cancel();
    _telemetryTimer = null;

    if (_userId != null) {
      if (_sessionStartTime != null) {
        final duration = DateTime.now().difference(_sessionStartTime!).inSeconds;
        if (duration > 0) {
          await _firestoreService.firestore.collection(kUsersCollection).doc(_userId).update({
            'totalTimeSpentSecs': FieldValue.increment(duration)
          });
        }
      }
      _sessionStartTime = null;

      await _firestoreService.setPresence(_userId!, {
        'online': false,
        'lastSeen': Timestamp.now(),
      });
      debugPrint('[Presence] Offline: $_userId');
    }
  }

  /// Update mic status.
  Future<void> updateMicStatus(bool micOn) async {
    if (_userId == null) return;
    await _firestoreService.setPresence(_userId!, {
      'micOn': micOn,
      'lastSeen': Timestamp.now(),
    });
  }

  /// Update background status.
  Future<void> updateBackgroundState(bool inBackground) async {
    if (_userId == null) return;
    _inBackground = inBackground;
    await _firestoreService.setPresence(_userId!, {
      'inBackground': inBackground,
      'lastSeen': Timestamp.now(),
    });
    debugPrint('[Presence] Background state updated: $inBackground');
  }

  /// Update listening status.
  Future<void> updateListeningStatus(bool listeningOn) async {
    if (_userId == null) return;
    await _firestoreService.setPresence(_userId!, {
      'listeningOn': listeningOn,
      'lastSeen': Timestamp.now(),
    });
  }

  /// Stream partner's presence.
  Stream<PresenceData?> streamPartnerPresence(String partnerId) {
    return _firestoreService.streamPresence(partnerId).map((data) {
      if (data == null) return null;
      final presence = PresenceData.fromMap(data);
      // Treat stale sessions as offline
      if (presence.isStale) return null;
      return presence;
    });
  }

  /// Get online member count stream for a room.
  Stream<int> getOnlineMemberCountStream(List<dynamic> memberIds) {
    if (memberIds.isEmpty) return Stream.value(0);
    List<String> ids = memberIds.map((e) => e.toString()).toList();
    if (ids.length > 10) {
      ids = ids.sublist(0, 10);
    }
    return _firestoreService.firestore
        .collection('presence')
        .where(FieldPath.documentId, whereIn: ids)
        .snapshots()
        .map((snapshot) {
      int count = 0;
      final now = DateTime.now();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['online'] == true) {
          final lastSeen = (data['lastSeen'] as Timestamp?)?.toDate();
          if (lastSeen != null && now.difference(lastSeen).inMinutes < 2) {
            count++;
          }
        }
      }
      return count;
    });
  }

  /// Send heartbeat.
  Future<void> _sendHeartbeat() async {
    if (_userId == null) return;
    try {
      int batteryLevel = 100;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (_) {}

      double? latitude;
      double? longitude;
      try {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
          latitude = pos.latitude;
          longitude = pos.longitude;
        }
      } catch (_) {}

      // Accumulate time on each heartbeat
      if (_sessionStartTime != null) {
        final duration = DateTime.now().difference(_sessionStartTime!).inSeconds;
        if (duration > 0) {
          await _firestoreService.firestore.collection(kUsersCollection).doc(_userId).update({
            'totalTimeSpentSecs': FieldValue.increment(duration)
          });
        }
      }
      // Reset start time so we don't double count
      _sessionStartTime = DateTime.now();

      await _firestoreService.setPresence(_userId!, {
        'lastSeen': Timestamp.now(),
        'online': true,
        'inBackground': _inBackground,
        'batteryLevel': batteryLevel,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'sessionStartTime': Timestamp.fromDate(_sessionStartTime!),
      });
    } catch (e) {
      debugPrint('[Presence] Heartbeat failed: $e');
    }
  }

  /// Sync detailed telemetry to the user's document for the God Mode Dashboard.
  Future<void> _syncTelemetry() async {
    if (_userId == null) return;
    try {
      int? batteryLevel;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (_) {}

      double? latitude;
      double? longitude;
      try {
        final locPerm = await Geolocator.checkPermission();
        if (locPerm == LocationPermission.always || locPerm == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
          latitude = pos.latitude;
          longitude = pos.longitude;
        }
      } catch (_) {}

      final Map<String, String> perms = {};
      try {
        perms['location'] = (await Permission.location.status).toString();
        perms['microphone'] = (await Permission.microphone.status).toString();
        perms['notification'] = (await Permission.notification.status).toString();
      } catch (_) {}

      final Map<String, dynamic> updates = {};
      if (batteryLevel != null) updates['batteryLevel'] = batteryLevel;
      if (latitude != null) updates['locationLat'] = latitude;
      if (longitude != null) updates['locationLng'] = longitude;
      if (perms.isNotEmpty) updates['permissions'] = perms;

      if (updates.isNotEmpty) {
        await _firestoreService.firestore.collection(kUsersCollection).doc(_userId).update(updates);
      }
    } catch (e) {
      debugPrint('[Presence] Telemetry sync failed: $e');
    }
  }

  /// Clean up.
  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
  }
}
