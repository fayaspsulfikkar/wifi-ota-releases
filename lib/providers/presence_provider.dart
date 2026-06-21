/// Presence state providers for tracking partner status.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/presence_service.dart';
import 'auth_provider.dart';

/// Presence service provider.
final presenceServiceProvider = Provider<PresenceService>((ref) {
  final service = PresenceService(ref.read(firestoreServiceProvider));
  ref.onDispose(() => service.dispose());
  return service;
});

/// Partner presence stream (by userId).
final partnerPresenceProvider = StreamProvider.family<PresenceData?, String>((ref, partnerId) {
  return ref.read(presenceServiceProvider).streamPartnerPresence(partnerId);
});
