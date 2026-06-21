/// Signaling models for WebRTC SDP and ICE candidate exchange.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class SessionDescriptionModel {
  final String sdp;
  final String type; // 'offer' or 'answer'
  final String fromUserId;

  const SessionDescriptionModel({
    required this.sdp,
    required this.type,
    required this.fromUserId,
  });

  factory SessionDescriptionModel.fromMap(Map<String, dynamic> data) {
    return SessionDescriptionModel(
      sdp: data['sdp'] ?? '',
      type: data['type'] ?? '',
      fromUserId: data['fromUserId'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sdp': sdp,
      'type': type,
      'fromUserId': fromUserId,
    };
  }
}

class IceCandidateModel {
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
  final String fromUserId;
  final DateTime createdAt;

  const IceCandidateModel({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
    required this.fromUserId,
    required this.createdAt,
  });

  factory IceCandidateModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return IceCandidateModel(
      candidate: data['candidate'] ?? '',
      sdpMid: data['sdpMid'],
      sdpMLineIndex: data['sdpMLineIndex'],
      fromUserId: data['fromUserId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'candidate': candidate,
      'sdpMid': sdpMid,
      'sdpMLineIndex': sdpMLineIndex,
      'fromUserId': fromUserId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
