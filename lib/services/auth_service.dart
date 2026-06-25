/// Firebase Authentication service.
///
/// Wraps Firebase Auth for email/password authentication.
/// Users sign in with a username that gets mapped to an email format.
/// On first sign-up, users are automatically added to the default room.
library;

import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../core/constants.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Current Firebase user.
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Convert username to email format for Firebase Auth.
  String _usernameToEmail(String username) => '${username.toLowerCase().trim()}@wifi.app';

  /// Get a unique device ID and model.
  Future<Map<String, String>> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return {
        'id': androidInfo.id,
        'model': '${androidInfo.manufacturer} ${androidInfo.model}'
      };
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return {
        'id': iosInfo.identifierForVendor ?? 'unknown_ios_device',
        'model': iosInfo.name
      };
    }
    return {
      'id': 'unknown_device',
      'model': 'Unknown Model'
    };
  }

  Future<UserModel> _enforceDeviceStitching(User firebaseUser, String cleanUsername, String email) async {
    final deviceInfo = await _getDeviceInfo();
    final currentDeviceId = deviceInfo['id']!;
    final currentDeviceModel = deviceInfo['model'];
    
    // Check if user exists in Firestore
    final doc = await _firestore.collection(kUsersCollection).doc(firebaseUser.uid).get();
    
    UserModel user;
    if (!doc.exists || doc.data() == null) {
      // First time creating user doc
      user = UserModel(
        userId: firebaseUser.uid,
        username: cleanUsername,
        email: email,
        deviceId: currentDeviceId,
        deviceModel: currentDeviceModel,
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
      );
      await _firestore.collection(kUsersCollection).doc(firebaseUser.uid).set(user.toMap());
    } else {
      user = UserModel.fromMap(doc.data()!);
      
      // If the user has no stitched device yet, stitch it now
      if (user.deviceId == null || user.deviceId!.isEmpty) {
        user = UserModel(
          userId: user.userId,
          username: user.username,
          email: user.email,
          roomId: user.roomId,
          deviceId: currentDeviceId,
          deviceModel: currentDeviceModel,
          createdAt: user.createdAt ?? DateTime.now(),
          lastLogin: DateTime.now(),
          lastVisitedRoom: user.lastVisitedRoom,
          totalTimeSpentSecs: user.totalTimeSpentSecs,
        );
        await _firestore.collection(kUsersCollection).doc(user.userId).update({
          'deviceId': currentDeviceId,
          'deviceModel': currentDeviceModel,
          'lastLogin': Timestamp.now(),
        });
      } else {
        // Enforce strict stitching
        if (user.deviceId != currentDeviceId) {
          await _auth.signOut();
          throw FirebaseAuthException(
            code: 'device-mismatch',
            message: 'Account bound to another device. Access Denied.',
          );
        } else {
          // Update lastLogin
          await _firestore.collection(kUsersCollection).doc(user.userId).update({
            'lastLogin': Timestamp.now(),
          });
        }
      }
    }
    
    return user;
  }

  /// Sign in with username and password.
  Future<UserModel?> signIn(String username, String password) async {
    final cleanUsername = username.toLowerCase().trim();
    final cleanPassword = password.trim();
    final email = _usernameToEmail(cleanUsername);
    
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: cleanPassword,
      );
      if (result.user == null) return null;
      return await _enforceDeviceStitching(result.user!, cleanUsername, email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential' || e.code == 'invalid-login-credentials') {
        // Auto-create the user if they don't exist yet!
        try {
          final result = await _auth.createUserWithEmailAndPassword(
            email: email,
            password: cleanPassword,
          );
          if (result.user != null) {
            return await _enforceDeviceStitching(result.user!, cleanUsername, email);
          }
        } catch (_) {
          throw _mapAuthException(e);
        }
      } else if (e.code == 'device-mismatch') {
        rethrow; // Bubble up the strict error
      } else {
        throw _mapAuthException(e);
      }
    }
    return null;
  }

  /// Sign up with username and password (now just an alias for signIn).
  Future<UserModel?> signUp(String username, String password) async {
    return signIn(username, password);
  }

  /// Sign in silently as an anonymous user (Ghost Dial mode).
  Future<void> signInAnonymously() async {
    try {
      final result = await _auth.signInAnonymously();
      if (result.user != null) {
        await ensureUserHasCombo(result.user!.uid);
      }
    } catch (e) {
      // Ignore errors for anonymous auth (might be disabled or offline)
    }
  }

  /// Ensures that the user has a Ghost Dial combo. Assigns one if they don't.
  Future<void> ensureUserHasCombo(String uid) async {
    debugPrint('[ensureUserHasCombo] START for uid: $uid');
    try {
      final deviceInfo = await _getDeviceInfo();
      debugPrint('[ensureUserHasCombo] got device info');
      final currentDeviceId = deviceInfo['id']!;
      final currentDeviceModel = deviceInfo['model'];
      
      // Check if this user already has a combo assigned
      debugPrint('[ensureUserHasCombo] fetching user doc');
      final doc = await _firestore.collection(kUsersCollection).doc(uid).get();
      debugPrint('[ensureUserHasCombo] user doc exists: ${doc.exists}, data: ${doc.data()}');
      
      if (!doc.exists || doc.data()?['assignedHz'] == null) {
        debugPrint('[ensureUserHasCombo] Needs a combo! Calling _reserveUniqueCombo');
        // First time — assign a unique combo
        final combo = await _reserveUniqueCombo(uid);
        debugPrint('[ensureUserHasCombo] reserved combo: $combo');
        
        await _firestore.collection(kUsersCollection).doc(uid).set({
          'userId': uid,
          'username': 'FLASHLIGHT',
          'email': 'anonymous@wifi.app',
          'deviceId': currentDeviceId,
          'deviceModel': currentDeviceModel,
          'createdAt': Timestamp.now(),
          'lastLogin': Timestamp.now(),
          'totalTimeSpentSecs': 0,
          'assignedHz': combo['hz'],
          'assignedBrightness': combo['brightness'],
        }, SetOptions(merge: true));
        debugPrint('[ensureUserHasCombo] Updated user doc with combo');
      } else {
        // Existing user — just update lastLogin
        debugPrint('[ensureUserHasCombo] User already has combo: ${doc.data()?['assignedHz']}');
        await _firestore.collection(kUsersCollection).doc(uid).update({
          'lastLogin': Timestamp.now(),
        });
      }
    } catch (e, stack) {
      debugPrint('[ensureUserHasCombo] CRITICAL ERROR: $e\n$stack');
    }
  }

  /// Reserve a unique Hz+Brightness combo atomically.
  /// Uses a 'combos' collection where doc ID = 'hz_brightness' to prevent collisions.
  Future<Map<String, int>> _reserveUniqueCombo(String uid) async {
    final random = Random();
    const maxAttempts = 100;
    
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final hz = (random.nextInt(250) + 1); // 1 to 250
      final brightness = (random.nextInt(100) + 1); // 1 to 100
      final comboId = '${hz}_$brightness';
      
      final comboRef = _firestore.collection('combos').doc(comboId);
      
      try {
        await _firestore.runTransaction((transaction) async {
          final snapshot = await transaction.get(comboRef);
          if (snapshot.exists) {
            throw Exception('Combo already taken');
          }
          transaction.set(comboRef, {
            'userId': uid,
            'hz': hz,
            'brightness': brightness,
            'createdAt': Timestamp.now(),
          });
        });
        
        return {'hz': hz, 'brightness': brightness};
      } catch (e) {
        if (e.toString().contains('already taken')) {
           continue; // Collision — try again
        } else {
           debugPrint('[_reserveUniqueCombo] Unexpected error: $e');
           rethrow; // Stop on permission errors or network issues
        }
      }
    }
    
    // Extremely unlikely fallback
    throw Exception('Could not find a unique combo after $maxAttempts attempts');
  }

  /// Get user model from Firestore.
  Future<UserModel?> getUser(String userId) async {
    final doc = await _firestore.collection(kUsersCollection).doc(userId).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromMap(doc.data()!);
  }

  /// Stream user document changes.
  Stream<UserModel?> streamUser(String userId) {
    return _firestore
        .collection(kUsersCollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return UserModel.fromMap(doc.data()!);
    });
  }

  /// Sign out.
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Map Firebase Auth exceptions to user-friendly messages.
  Exception _mapAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return Exception('No account found with this username.');
      case 'wrong-password':
        return Exception('Incorrect password.');
      case 'email-already-in-use':
        return Exception('This username is already taken.');
      case 'weak-password':
        return Exception('Password is too weak. Use at least 6 characters.');
      case 'invalid-email':
        return Exception('Invalid username format.');
      case 'invalid-credential':
        return Exception('Invalid username or password.');
      case 'device-mismatch':
        return Exception(e.message ?? 'Access Denied: Unrecognized hardware.');
      default:
        return Exception(e.message ?? 'Authentication failed.');
    }
  }
}
