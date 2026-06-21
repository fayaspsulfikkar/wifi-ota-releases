/// Firestore service for CRUD operations on all collections.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';
import '../models/user_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Public getter for firestore instance
  FirebaseFirestore get firestore => _firestore;

  // ─── Users ──────────────────────────────────────────────────────────────

  /// Get user document.
  Future<UserModel?> getUser(String userId) async {
    final doc = await _firestore.collection(kUsersCollection).doc(userId).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromMap(doc.data()!);
  }

  /// Stream user document.
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

  /// Update user document fields.
  Future<void> updateUser(String userId, Map<String, dynamic> data) async {
    await _firestore.collection(kUsersCollection).doc(userId).update(data);
  }

  // ─── Rooms ──────────────────────────────────────────────────────────────

  /// Join a room
  Future<void> joinRoom(String userId, String roomId) async {
    // 1. Update user document
    await _firestore.collection(kUsersCollection).doc(userId).update({
      'roomId': roomId,
      'lastVisitedRoom': roomId,
    });
    
    // 2. Update room document
    await _firestore.collection(kRoomsCollection).doc(roomId).update({
      'memberIds': FieldValue.arrayUnion([userId]),
    });
  }

  // ─── Presence ───────────────────────────────────────────────────────────

  /// Set presence data.
  Future<void> setPresence(String userId, Map<String, dynamic> data) async {
    await _firestore
        .collection(kPresenceCollection)
        .doc(userId)
        .set(data, SetOptions(merge: true));
  }

  /// Stream partner's presence.
  Stream<Map<String, dynamic>?> streamPresence(String userId) {
    return _firestore
        .collection(kPresenceCollection)
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? doc.data() : null);
  }

  // ─── Signaling ──────────────────────────────────────────────────────────

  /// Helper to get the signaling collection for a room
  CollectionReference _signalingRef(String roomId) {
    return _firestore.collection(kRoomsCollection).doc(roomId).collection(kSignalingCollection);
  }

  /// Set signaling data (offer/answer).
  Future<void> setSignaling(String roomId, String connectionId, Map<String, dynamic> data) async {
    data['updatedAt'] = Timestamp.now();
    await _signalingRef(roomId).doc(connectionId).set(data, SetOptions(merge: true));
  }

  /// Stream signaling document.
  Stream<Map<String, dynamic>?> streamSignaling(String roomId, String connectionId) {
    return _signalingRef(roomId).doc(connectionId).snapshots().map((doc) => doc.exists ? doc.data() as Map<String, dynamic>? : null);
  }

  /// Add ICE candidate.
  Future<void> addIceCandidate(
      String roomId, String connectionId, Map<String, dynamic> candidate) async {
    await _signalingRef(roomId).doc(connectionId).collection(kCandidatesSubcollection).add(candidate);
  }

  /// Stream ICE candidates.
  Stream<QuerySnapshot> streamIceCandidates(String roomId, String connectionId) {
    return _signalingRef(roomId)
        .doc(connectionId)
        .collection(kCandidatesSubcollection)
        .orderBy('createdAt')
        .snapshots();
  }

  /// Clear all signaling data for renegotiation.
  Future<void> clearSignaling(String roomId, String connectionId) async {
    // Delete candidates subcollection
    final candidates = await _signalingRef(roomId)
        .doc(connectionId)
        .collection(kCandidatesSubcollection)
        .get();

    final batch = _firestore.batch();
    for (final doc in candidates.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    // Clear signaling document
    await _signalingRef(roomId).doc(connectionId).set({
      'offer': null,
      'answer': null,
      'updatedAt': Timestamp.now(),
    });
  }
}
