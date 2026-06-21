/// Authentication state providers.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../models/user_model.dart';
import '../models/room_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

/// Singleton auth service provider.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Singleton Firestore service provider.
final firestoreServiceProvider = Provider<FirestoreService>((ref) => FirestoreService());

/// Firebase auth state stream.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.read(authServiceProvider).authStateChanges;
});

/// Current user model from Firestore (reactive).
final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);

  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return ref.read(firestoreServiceProvider).streamUser(user.uid);
    },
    loading: () => Stream.value(null),
    error: (e, _) => Stream.value(null),
  );
});

/// Current room model from Firestore (reactive).
final currentRoomProvider = StreamProvider<RoomModel?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  if (user == null || user.roomId == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection(kRoomsCollection)
      .doc(user.roomId)
      .snapshots()
      .map((doc) {
    if (!doc.exists || doc.data() == null) return null;
    return RoomModel.fromMap(doc.data()!);
  });
});

/// Partner user models from Firestore (reactive).
/// Resolves based on room membership — all other members in the same room.
final partnersProvider = StreamProvider<List<UserModel>>((ref) {
  final user = ref.watch(currentUserProvider).value;
  final room = ref.watch(currentRoomProvider).value;
  if (user == null || room == null) return Stream.value([]);

  // Find all partners = all other members in this room
  final partnerIds = room.memberIds.where((id) => id != user.userId).toList();
  if (partnerIds.isEmpty) return Stream.value([]);

  // Firestore whereIn has a limit of 10, which is fine for small group calls.
  // If a group has more than 11 members, this needs pagination or batching.
  return FirebaseFirestore.instance
      .collection(kUsersCollection)
      .where(FieldPath.documentId, whereIn: partnerIds.take(10).toList())
      .snapshots()
      .map((snapshot) {
    return snapshot.docs.map((doc) => UserModel.fromMap(doc.data())).toList();
  });
});

/// Auth loading state for sign-in/sign-up operations.
final authLoadingProvider = StateProvider<bool>((ref) => false);

/// Auth error message.
final authErrorProvider = StateProvider<String?>((ref) => null);
