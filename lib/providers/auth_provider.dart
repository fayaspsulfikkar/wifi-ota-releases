/// Authentication state providers.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../models/user_model.dart';
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



/// Auth loading state for sign-in/sign-up operations.
final authLoadingProvider = StateProvider<bool>((ref) => false);

/// Auth error message.
final authErrorProvider = StateProvider<String?>((ref) => null);
