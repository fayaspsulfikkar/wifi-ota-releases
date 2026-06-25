/// WebRTC service for managing peer connections and audio streams.
///
/// Handles the core WebRTC lifecycle: peer connection creation,
/// SDP negotiation, ICE candidate exchange, and audio stream management.
/// Audio only — no video is ever captured or transmitted.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/constants.dart';

/// Connection state for the WebRTC peer connection.
enum WebRTCConnectionState {
  idle,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

class WebRTCService {
  final Map<String, RTCPeerConnection> _peerConnections = {};
  MediaStream? _localStream;
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, WebRTCConnectionState> _connectionStates = {};

  bool _isMicEnabled = true;
  bool _isListening = true;
  bool _isAppInBackground = false;

  // Callbacks mapped by partnerUserId
  Function(String partnerId, RTCIceCandidate)? onIceCandidate;
  Function(String partnerId, WebRTCConnectionState)? onConnectionStateChanged;
  Function(String partnerId, MediaStream)? onRemoteStream;

  // ─── State Getters ──────────────────────────────────────────────────────

  bool get isMicEnabled => _isMicEnabled;
  bool get isListening => _isListening;
  
  WebRTCConnectionState getConnectionState(String partnerId) {
    return _connectionStates[partnerId] ?? WebRTCConnectionState.idle;
  }

  // ─── Initialization ─────────────────────────────────────────────────────

  /// Initialize local audio stream (called once per room).
  Future<void> initializeLocalStream({bool echoCancellation = true, bool noiseSuppression = true}) async {
    if (_localStream != null) return;
    
    final constraints = {
      'audio': {
        'echoCancellation': echoCancellation,
        'noiseSuppression': noiseSuppression,
        'autoGainControl': true,
      },
      'video': false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    debugPrint('[WebRTC] Local audio stream initialized (DSP: echo=$echoCancellation, noise=$noiseSuppression)');
  }

  /// Create a peer connection for a specific partner.
  Future<void> initializeConnection(String partnerId) async {
    if (_peerConnections.containsKey(partnerId)) return;

    final pc = await createPeerConnection(kPeerConnectionConfig);
    _peerConnections[partnerId] = pc;
    _connectionStates[partnerId] = WebRTCConnectionState.idle;

    // Listen for ICE candidates
    pc.onIceCandidate = (candidate) {
      onIceCandidate?.call(partnerId, candidate);
    };

    // Listen for remote stream
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        final stream = event.streams.first;
        _remoteStreams[partnerId] = stream;
        
        // Apply current listening state to the new stream
        final isPartnerListening = !_mutedPartners.contains(partnerId);
        for (final track in stream.getAudioTracks()) {
          track.enabled = _isListening && isPartnerListening && !_isAppInBackground;
        }
        
        onRemoteStream?.call(partnerId, stream);
      }
    };

    // Track connection state changes
    pc.onConnectionState = (state) {
      final mappedState = _mapConnectionState(state);
      _connectionStates[partnerId] = mappedState;
      onConnectionStateChanged?.call(partnerId, mappedState);
    };

    pc.onIceConnectionState = (state) {
      debugPrint('[WebRTC] ICE state for $partnerId: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _connectionStates[partnerId] = WebRTCConnectionState.failed;
        onConnectionStateChanged?.call(partnerId, WebRTCConnectionState.failed);
      }
    };

    // Add local stream tracks to this peer connection
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    debugPrint('[WebRTC] Initialized connection for $partnerId');
  }

  // ─── SDP Negotiation ───────────────────────────────────────────────────

  /// Create an SDP offer for a specific partner (initiator role).
  Future<RTCSessionDescription> createOffer(String partnerId) async {
    final pc = _peerConnections[partnerId];
    if (pc == null) throw Exception('No peer connection for $partnerId');

    final offer = await pc.createOffer(kOfferSdpConstraints);
    await pc.setLocalDescription(offer);
    debugPrint('[WebRTC] Created offer for $partnerId');
    return offer;
  }

  /// Create an SDP answer for a specific partner (responder role).
  Future<RTCSessionDescription> createAnswer(String partnerId) async {
    final pc = _peerConnections[partnerId];
    if (pc == null) throw Exception('No peer connection for $partnerId');

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    debugPrint('[WebRTC] Created answer for $partnerId');
    return answer;
  }

  final Map<String, List<RTCIceCandidate>> _candidateQueues = {};
  final Set<String> _remoteDescriptionSet = {};

  /// Set the remote description (partner's offer or answer).
  Future<void> setRemoteDescription(String partnerId, RTCSessionDescription description) async {
    final pc = _peerConnections[partnerId];
    if (pc == null) throw Exception('No peer connection for $partnerId');

    await pc.setRemoteDescription(description);
    _remoteDescriptionSet.add(partnerId);
    debugPrint('[WebRTC] Set remote description for $partnerId: ${description.type}');

    // Process queued candidates
    final queue = _candidateQueues[partnerId] ?? [];
    for (final candidate in queue) {
      await pc.addCandidate(candidate);
    }
    _candidateQueues.remove(partnerId);
  }

  /// Add a remote ICE candidate.
  Future<void> addIceCandidate(String partnerId, RTCIceCandidate candidate) async {
    final pc = _peerConnections[partnerId];
    if (pc == null) return; 

    // Queue if remote description is not set yet
    if (!_remoteDescriptionSet.contains(partnerId)) {
      _candidateQueues.putIfAbsent(partnerId, () => []).add(candidate);
      return;
    }
    await pc.addCandidate(candidate);
  }

  // ─── Audio Control ─────────────────────────────────────────────────────

  final Set<String> _mutedPartners = {};

  /// Toggle microphone on/off (controls outgoing audio).
  void setMicEnabled(bool enabled) {
    _isMicEnabled = enabled;
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = enabled;
      }
    }
    debugPrint('[WebRTC] Mic ${enabled ? "ON" : "OFF"}');
  }

  /// Toggle listening for a specific partner
  void setPartnerListening(String partnerId, bool listening) {
    if (listening) {
      _mutedPartners.remove(partnerId);
    } else {
      _mutedPartners.add(partnerId);
    }
    
    final stream = _remoteStreams[partnerId];
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = listening && _isListening && !_isAppInBackground;
      }
    }
    debugPrint('[WebRTC] Partner $partnerId listening ${listening ? "ON" : "OFF"}');
  }

  /// Toggle listening on/off (controls incoming audio for all partners).
  void setListening(bool listening) {
    _isListening = listening;
    for (final entry in _remoteStreams.entries) {
      final partnerId = entry.key;
      final stream = entry.value;
      final isPartnerListening = !_mutedPartners.contains(partnerId);
      for (final track in stream.getAudioTracks()) {
        track.enabled = listening && isPartnerListening && !_isAppInBackground;
      }
    }
    debugPrint('[WebRTC] Listening ${listening ? "ON" : "OFF"}');
  }

  /// Temporarily mute all incoming audio when app goes to background.
  void muteAllIncomingAudio(bool mute) {
    _isAppInBackground = mute;
    for (final entry in _remoteStreams.entries) {
      final partnerId = entry.key;
      final stream = entry.value;
      final isPartnerListening = !_mutedPartners.contains(partnerId);
      for (final track in stream.getAudioTracks()) {
        track.enabled = !mute && _isListening && isPartnerListening;
      }
    }
    debugPrint('[WebRTC] App background mute: ${mute ? "ON" : "OFF"}');
  }

  /// Toggle speakerphone
  Future<void> setSpeakerphoneOn(bool enable) async {
    try {
      await Helper.setSpeakerphoneOn(enable);
      debugPrint('[WebRTC] Speakerphone ${enable ? "ON" : "OFF"}');
    } catch (e) {
      debugPrint('[WebRTC] Error setting speakerphone: $e');
    }
  }

  // ─── Cleanup ────────────────────────────────────────────────────────────

  /// Close a specific peer connection (e.g. if a user leaves).
  Future<void> closeConnection(String partnerId) async {
    final pc = _peerConnections.remove(partnerId);
    await pc?.close();
    _remoteStreams.remove(partnerId);
    _connectionStates.remove(partnerId);
    _remoteDescriptionSet.remove(partnerId);
    _candidateQueues.remove(partnerId);
    debugPrint('[WebRTC] Closed connection for $partnerId');
  }

  /// Close all peer connections and release local audio.
  Future<void> disposeAll() async {
    // Stop local stream tracks
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        try { await track.stop(); } catch (_) {}
      }
      try { await _localStream!.dispose(); } catch (_) {}
      _localStream = null;
    }

    // Stop remote stream tracks
    for (final stream in _remoteStreams.values) {
      for (final track in stream.getTracks()) {
        try { await track.stop(); } catch (_) {}
      }
      try { await stream.dispose(); } catch (_) {}
    }

    // Close all peer connections
    await Future.wait(_peerConnections.values.map((pc) async {
      try {
        await pc.close();
        pc.dispose();
      } catch (_) {}
    }));

    
    // Ensure native audio routing is reset
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}

    _peerConnections.clear();
    _remoteStreams.clear();
    _connectionStates.clear();
    _remoteDescriptionSet.clear();
    _candidateQueues.clear();
    
    debugPrint('[WebRTC] Disposed all connections');
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  WebRTCConnectionState _mapConnectionState(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        return WebRTCConnectionState.idle;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return WebRTCConnectionState.connecting;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return WebRTCConnectionState.connected;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return WebRTCConnectionState.disconnected;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return WebRTCConnectionState.failed;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return WebRTCConnectionState.closed;
    }
  }
}
