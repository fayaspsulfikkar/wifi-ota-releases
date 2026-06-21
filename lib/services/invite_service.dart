import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../models/user_model.dart';

final inviteServiceProvider = Provider((ref) => InviteService());

class InviteModel {
  final String id;
  final String fromUserId;
  final String fromUsername;
  final String toUserId;
  final String toUsername;
  final String roomId;
  final String roomName;
  final DateTime timestamp;

  InviteModel({
    required this.id,
    required this.fromUserId,
    required this.fromUsername,
    required this.toUserId,
    required this.toUsername,
    required this.roomId,
    required this.roomName,
    required this.timestamp,
  });

  factory InviteModel.fromMap(String id, Map<String, dynamic> data) {
    return InviteModel(
      id: id,
      fromUserId: data['fromUserId'] ?? '',
      fromUsername: data['fromUsername'] ?? '',
      toUserId: data['toUserId'] ?? '',
      toUsername: data['toUsername'] ?? '',
      roomId: data['roomId'] ?? '',
      roomName: data['roomName'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fromUserId': fromUserId,
      'fromUsername': fromUsername,
      'toUserId': toUserId,
      'toUsername': toUsername,
      'roomId': roomId,
      'roomName': roomName,
      'timestamp': Timestamp.now(), // Use client-side timestamp for immediate local query visibility
    };
  }
}

class InviteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Search for a user by exactly matching their username (case insensitive).
  Future<UserModel?> findUserByUsername(String username) async {
    final cleanUsername = username.toLowerCase().trim();
    final snapshot = await _firestore
        .collection(kUsersCollection)
        .where('username', isEqualTo: cleanUsername)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return UserModel.fromMap(snapshot.docs.first.data());
  }

  /// Sends an invite to a specific user.
  Future<void> sendInvite({
    required String fromUserId,
    required String fromUsername,
    required String toUserId,
    required String toUsername,
    required String roomId,
    required String roomName,
  }) async {
    final inviteRef = _firestore.collection('invites').doc();
    final invite = InviteModel(
      id: inviteRef.id,
      fromUserId: fromUserId,
      fromUsername: fromUsername,
      toUserId: toUserId,
      toUsername: toUsername,
      roomId: roomId,
      roomName: roomName,
      timestamp: DateTime.now(),
    );

    await inviteRef.set(invite.toMap());
  }

  /// Listen for incoming invites for the current user.
  Stream<List<InviteModel>> listenForInvites(String myUserId) {
    return _firestore
        .collection('invites')
        .where('toUserId', isEqualTo: myUserId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => InviteModel.fromMap(doc.id, doc.data())).toList();
    });
  }

  /// Listen for pending invites in a specific room.
  Stream<List<InviteModel>> listenForRoomInvites(String roomId) {
    return _firestore
        .collection('invites')
        .where('roomId', isEqualTo: roomId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => InviteModel.fromMap(doc.id, doc.data())).toList();
    });
  }

  /// Delete an invite once it has been accepted or dismissed.
  Future<void> deleteInvite(String inviteId) async {
    await _firestore.collection('invites').doc(inviteId).delete();
  }
}
