/// Signaling service for WebRTC SDP and ICE exchange via Firestore.
///
/// Uses Firestore as the signaling channel. The initiator is determined
/// by lexicographic comparison of user IDs to prevent race conditions.
library;

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/firestore_service.dart';
import '../services/webrtc_service.dart';

class SignalingService {
  final FirestoreService _firestoreService;
  final WebRTCService _webrtcService;

  final Map<String, StreamSubscription> _signalingSubscriptions = {};
  final Map<String, StreamSubscription> _candidatesSubscriptions = {};

  String? _roomId;
  String? _myUserId;
  final Set<String> _processedCandidateIds = {};
  final Set<String> _connectedPartners = {};
  final Set<String> _activelyConnecting = {}; // Guard against concurrent _startSignalingForPartner calls
  StreamSubscription<DocumentSnapshot>? _roomSubscription;

  SignalingService(this._firestoreService, this._webrtcService);

  /// Helper to get a deterministic connection ID for two users.
  String _getConnectionId(String user1, String user2) {
    final list = [user1, user2]..sort();
    return list.join('_');
  }

  /// Start signaling for a room with multiple partners (Mesh Topology).
  Future<void> startSignaling({
    required String roomId,
    required String myUserId,
    required List<String> partnerIds,
    bool echoCancellation = true,
    bool noiseSuppression = true,
  }) async {
    _roomId = roomId;
    _myUserId = myUserId;

    debugPrint('[Signaling] ============================================');
    debugPrint('[Signaling] Starting Mesh for room $roomId');
    debugPrint('[Signaling] My userId: $myUserId');
    debugPrint('[Signaling] ============================================');

    // Initialize local stream once for the room
    await _webrtcService.initializeLocalStream(
      echoCancellation: echoCancellation,
      noiseSuppression: noiseSuppression,
    );
    debugPrint('[Signaling] Local stream initialized');

    // Set up WebRTC callbacks (now passing partnerId)
    _webrtcService.onIceCandidate = (partnerId, candidate) {
      _sendIceCandidate(partnerId, candidate);
    };

    // Dynamically track room members
    _roomSubscription?.cancel();
    _roomSubscription = FirebaseFirestore.instance
        .collection('rooms')
        .doc(roomId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return;
      
      final List<dynamic> members = snapshot.data()!['memberIds'] ?? [];
      final currentPartnerIds = members
          .map((e) => e.toString())
          .where((id) => id != _myUserId)
          .toSet();

      debugPrint('[Signaling] Room snapshot: ${members.length} members, ${currentPartnerIds.length} partners: $currentPartnerIds');

      final added = currentPartnerIds.difference(_connectedPartners);
      final removed = _connectedPartners.difference(currentPartnerIds);

      for (final id in added) {
        debugPrint('[Signaling] Detected NEW partner: $id');
        _startSignalingForPartner(id);
      }
      for (final id in removed) {
        debugPrint('[Signaling] Detected REMOVED partner: $id');
        removePartner(id);
      }
    });
  }

  Future<void> _startSignalingForPartner(String partnerId) async {
    if (_roomId == null || _myUserId == null) {
      debugPrint('[Signaling] ERROR: Cannot start signaling - roomId or myUserId is null');
      return;
    }
    if (_connectedPartners.contains(partnerId)) {
      debugPrint('[Signaling] SKIP: Already connected to $partnerId');
      return;
    }
    if (_activelyConnecting.contains(partnerId)) {
      debugPrint('[Signaling] SKIP: Already connecting to $partnerId');
      return;
    }
    
    _activelyConnecting.add(partnerId);
    _connectedPartners.add(partnerId);
    
    final connectionId = _getConnectionId(_myUserId!, partnerId);
    final isInitiator = _myUserId!.compareTo(partnerId) < 0;

    debugPrint('[Signaling] ────────────────────────────────────');
    debugPrint('[Signaling] Starting connection with $partnerId');
    debugPrint('[Signaling] Connection ID: $connectionId');
    debugPrint('[Signaling] I am ${isInitiator ? "INITIATOR" : "RESPONDER"}');
    debugPrint('[Signaling] ────────────────────────────────────');

    try {
      // Only the initiator clears old signaling data.
      // The responder must NOT clear, or it will wipe the initiator's offer.
      if (isInitiator) {
        await _firestoreService.clearSignaling(_roomId!, connectionId);
        debugPrint('[Signaling] Cleared old signaling data for $connectionId');
      }

      // Initialize peer connection for this specific partner
      await _webrtcService.initializeConnection(partnerId);
      debugPrint('[Signaling] Peer connection created for $partnerId');

      // Listen for candidates from the partner
      _listenForCandidates(partnerId, connectionId);

      if (isInitiator) {
        // Create and send offer
        debugPrint('[Signaling] Creating offer for $partnerId...');
        final offer = await _webrtcService.createOffer(partnerId);
        debugPrint('[Signaling] Offer created, writing to Firestore...');
        
        await _firestoreService.setSignaling(_roomId!, connectionId, {
          'offer': {
            'sdp': offer.sdp,
            'type': offer.type,
            'fromUserId': _myUserId,
            'createdAt': Timestamp.now(),
          },
        });
        debugPrint('[Signaling] Offer written to Firestore for $partnerId');

        // Listen for answer
        _listenForAnswer(partnerId, connectionId);
      } else {
        // Responder: Listen for offer from initiator
        debugPrint('[Signaling] Waiting for offer from $partnerId...');
        _listenForOffer(partnerId, connectionId);
      }
    } catch (e, st) {
      debugPrint('[Signaling] ERROR starting signaling for $partnerId: $e');
      debugPrint('[Signaling] Stack: $st');
      _connectedPartners.remove(partnerId);
    } finally {
      _activelyConnecting.remove(partnerId);
    }
  }

  final Map<String, String> _lastProcessedOffers = {};

  /// Listen for the offer (responder role).
  void _listenForOffer(String partnerId, String connectionId) {
    _signalingSubscriptions[partnerId]?.cancel();
    
    debugPrint('[Signaling] [RESPONDER] Attaching offer listener for $connectionId');
    
    _signalingSubscriptions[partnerId] = _firestoreService
        .streamSignaling(_roomId!, connectionId)
        .listen((data) async {
      if (data == null) {
        debugPrint('[Signaling] [RESPONDER] Signaling doc is null/missing for $connectionId');
        return;
      }

      final offer = data['offer'];
      if (offer == null) {
        debugPrint('[Signaling] [RESPONDER] Offer field is null in signaling doc');
        return;
      }
      
      // Accept offer from the partner (initiator)
      if (offer['fromUserId'] != partnerId) {
        debugPrint('[Signaling] [RESPONDER] Offer fromUserId mismatch: ${offer['fromUserId']} != $partnerId');
        return;
      }
      
      final offerSdp = offer['sdp'] as String?;
      if (offerSdp == null) {
        debugPrint('[Signaling] [RESPONDER] Offer SDP is null');
        return;
      }
      
      if (offerSdp == _lastProcessedOffers[partnerId]) {
        return; // Already processed this exact offer
      }
      _lastProcessedOffers[partnerId] = offerSdp;

      debugPrint('[Signaling] [RESPONDER] ✓ Received valid offer from $partnerId');

      try {
        // Set remote description
        await _webrtcService.setRemoteDescription(
          partnerId,
          RTCSessionDescription(offer['sdp'], offer['type']),
        );
        debugPrint('[Signaling] [RESPONDER] Remote description set');

        // Create and send answer
        final answer = await _webrtcService.createAnswer(partnerId);
        debugPrint('[Signaling] [RESPONDER] Answer created, writing to Firestore...');
        
        await _firestoreService.setSignaling(_roomId!, connectionId, {
          'answer': {
            'sdp': answer.sdp,
            'type': answer.type,
            'fromUserId': _myUserId,
            'createdAt': Timestamp.now(),
          },
        });
        debugPrint('[Signaling] [RESPONDER] ✓ Answer written to Firestore');
      } catch (e) {
        debugPrint('[Signaling] [RESPONDER] ERROR processing offer: $e');
      }
    });
  }

  /// Listen for the answer (initiator role).
  void _listenForAnswer(String partnerId, String connectionId) {
    _signalingSubscriptions[partnerId]?.cancel();
    
    debugPrint('[Signaling] [INITIATOR] Attaching answer listener for $connectionId');
    
    _signalingSubscriptions[partnerId] = _firestoreService
        .streamSignaling(_roomId!, connectionId)
        .listen((data) async {
      if (data == null) return;

      final answer = data['answer'];
      if (answer == null) return;
      
      if (answer['fromUserId'] != partnerId) return;

      debugPrint('[Signaling] [INITIATOR] ✓ Received answer from $partnerId');

      try {
        await _webrtcService.setRemoteDescription(
          partnerId,
          RTCSessionDescription(answer['sdp'], answer['type']),
        );
        debugPrint('[Signaling] [INITIATOR] ✓ Remote description set from answer');

        // Stop listening after successfully receiving answer
        _signalingSubscriptions[partnerId]?.cancel();
      } catch (e) {
        debugPrint('[Signaling] [INITIATOR] ERROR processing answer: $e');
      }
    });
  }

  /// Listen for ICE candidates from a specific partner.
  void _listenForCandidates(String partnerId, String connectionId) {
    _candidatesSubscriptions[partnerId]?.cancel();
    
    debugPrint('[Signaling] [ICE] Attaching candidates listener for $connectionId');
    
    _candidatesSubscriptions[partnerId] = _firestoreService
        .streamIceCandidates(_roomId!, connectionId)
        .listen((snapshot) {
      int added = 0;
      int skipped = 0;
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final docId = change.doc.id;

          // Skip own candidates and already-processed ones
          if (data['fromUserId'] == _myUserId) { skipped++; continue; }
          if (_processedCandidateIds.contains(docId)) { skipped++; continue; }

          _processedCandidateIds.add(docId);

          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );

          _webrtcService.addIceCandidate(partnerId, candidate);
          added++;
        }
      }
      if (added > 0 || skipped > 0) {
        debugPrint('[Signaling] [ICE] Processed $added candidates, skipped $skipped for $partnerId');
      }
    });
  }

  /// Send a local ICE candidate to Firestore for a specific connection.
  Future<void> _sendIceCandidate(String partnerId, RTCIceCandidate candidate) async {
    if (_roomId == null || _myUserId == null) return;
    final connectionId = _getConnectionId(_myUserId!, partnerId);

    await _firestoreService.addIceCandidate(_roomId!, connectionId, {
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
      'fromUserId': _myUserId,
      'createdAt': Timestamp.now(),
    });
  }

  /// Add a new partner dynamically (if someone joins later).
  Future<void> addPartner(String partnerId) async {
    if (_roomId == null || _myUserId == null) return;
    await _startSignalingForPartner(partnerId);
  }

  /// Remove a partner dynamically (if someone leaves).
  Future<void> removePartner(String partnerId) async {
    debugPrint('[Signaling] Removing partner: $partnerId');
    _connectedPartners.remove(partnerId);
    _activelyConnecting.remove(partnerId);
    _signalingSubscriptions[partnerId]?.cancel();
    _signalingSubscriptions.remove(partnerId);
    
    _candidatesSubscriptions[partnerId]?.cancel();
    _candidatesSubscriptions.remove(partnerId);
    
    _lastProcessedOffers.remove(partnerId);
    
    await _webrtcService.closeConnection(partnerId);
  }

  /// Stop all signaling and clean up subscriptions.
  Future<void> stopSignaling() async {
    debugPrint('[Signaling] Stopping all signaling');
    
    for (final sub in _signalingSubscriptions.values) {
      sub.cancel();
    }
    _signalingSubscriptions.clear();

    for (final sub in _candidatesSubscriptions.values) {
      sub.cancel();
    }
    _candidatesSubscriptions.clear();

    _processedCandidateIds.clear();
    _lastProcessedOffers.clear();
    _connectedPartners.clear();
    _activelyConnecting.clear();
    
    _roomSubscription?.cancel();
    _roomSubscription = null;
    
    _roomId = null;
    _myUserId = null;
  }
}
