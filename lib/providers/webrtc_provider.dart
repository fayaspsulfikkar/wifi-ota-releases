/// WebRTC connection state providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/webrtc_service.dart';
import '../services/signaling_service.dart';
import 'auth_provider.dart';

/// WebRTC service provider (singleton).
final webrtcServiceProvider = Provider<WebRTCService>((ref) {
  final service = WebRTCService();
  ref.onDispose(() => service.disposeAll());
  return service;
});

/// Signaling service provider.
final signalingServiceProvider = Provider<SignalingService>((ref) {
  return SignalingService(
    ref.read(firestoreServiceProvider),
    ref.read(webrtcServiceProvider),
  );
});

/// WebRTC connection states (mapped by partnerId).
final webrtcConnectionStatesProvider =
    StateProvider<Map<String, WebRTCConnectionState>>((ref) => {});

/// Check if we are connected to at least one partner.
final isWebrtcActiveProvider = Provider<bool>((ref) {
  final states = ref.watch(webrtcConnectionStatesProvider);
  return states.values.any((state) => 
      state == WebRTCConnectionState.connected ||
      state == WebRTCConnectionState.connecting);
});

/// Individual partner mute states (true means muted locally).
final partnerMuteStatesProvider = StateProvider<Map<String, bool>>((ref) => {});

/// Globally tracks which room ID we are currently connected to (if any).
final joinedRoomIdProvider = StateProvider<String?>((ref) => null);
