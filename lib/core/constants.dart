/// App-wide constants for WiFi voice room application.
///
/// WebRTC ICE server configuration is designed to be easily extensible
/// with TURN servers in the future without architectural changes.
library;

import 'package:flutter/material.dart';

// ─── WebRTC ICE Servers ─────────────────────────────────────────────────────
// Add TURN servers here when needed for production NAT traversal.
// The architecture supports any number of ICE servers.
const List<Map<String, dynamic>> kIceServers = [
  {
    'urls': ['stun:stun.l.google.com:19302'],
  },
  {
    'urls': ['stun:stun1.l.google.com:19302'],
  },
  {
    'urls': ['stun:stun2.l.google.com:19302'],
  },
  {
    'urls': ['stun:stun3.l.google.com:19302'],
  },
  {
    'urls': ['stun:stun4.l.google.com:19302'],
  },
  // Free TURN servers for NAT traversal when STUN fails
  {
    'urls': ['turn:openrelay.metered.ca:80'],
    'username': 'openrelayproject',
    'credential': 'openrelayproject',
  },
  {
    'urls': ['turn:openrelay.metered.ca:443'],
    'username': 'openrelayproject',
    'credential': 'openrelayproject',
  },
  {
    'urls': ['turn:openrelay.metered.ca:443?transport=tcp'],
    'username': 'openrelayproject',
    'credential': 'openrelayproject',
  },
];

const Map<String, dynamic> kPeerConnectionConfig = {
  'iceServers': kIceServers,
  'sdpSemantics': 'unified-plan',
};

const Map<String, dynamic> kOfferSdpConstraints = {
  'mandatory': {
    'OfferToReceiveAudio': true,
    'OfferToReceiveVideo': false,
  },
  'optional': [],
};

// ─── Audio Constraints ──────────────────────────────────────────────────────
const Map<String, dynamic> kMediaConstraints = {
  'audio': {
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
  },
  'video': false,
};

// ─── Presence ───────────────────────────────────────────────────────────────
const Duration kHeartbeatInterval = Duration(seconds: 30);
const Duration kPresenceTimeout = Duration(seconds: 90);

// ─── Pairing ────────────────────────────────────────────────────────────────
const int kPairingCodeLength = 6;

// ─── Colors ─────────────────────────────────────────────────────────────────
const Color kPrimaryBlue = Color(0xFF4A90D9);
const Color kDeepBlue = Color(0xFF1A2332);
const Color kDarkBackground = Color(0xFF0D1117);
const Color kCardBackground = Color(0xFF161B22);
const Color kSurfaceColor = Color(0xFF21262D);
const Color kAccentGlow = Color(0xFF58A6FF);
const Color kSuccessGreen = Color(0xFF3FB950);
const Color kWarningOrange = Color(0xFFD29922);
const Color kErrorRed = Color(0xFFF85149);
const Color kMutedText = Color(0xFF8B949E);
const Color kBorderColor = Color(0xFF30363D);

// ─── Gradients ──────────────────────────────────────────────────────────────
const LinearGradient kBackgroundGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF0D1117),
    Color(0xFF161B22),
    Color(0xFF0D1B2A),
  ],
);

const LinearGradient kSplashGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFF1B2838),
    Color(0xFF0F1923),
    Color(0xFF0D1117),
  ],
);

const LinearGradient kButtonActiveGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF58A6FF),
    Color(0xFF4A90D9),
    Color(0xFF388BFD),
  ],
);

// ─── Animation Durations ────────────────────────────────────────────────────
const Duration kFastAnimation = Duration(milliseconds: 200);
const Duration kMediumAnimation = Duration(milliseconds: 400);
const Duration kSlowAnimation = Duration(milliseconds: 800);
const Duration kPulseAnimation = Duration(milliseconds: 1500);
const Duration kSplashDuration = Duration(milliseconds: 2500);

// ─── Firestore Collections ──────────────────────────────────────────────────
const String kUsersCollection = 'users';
const String kRoomsCollection = 'rooms';
const String kPresenceCollection = 'presence';
const String kSignalingCollection = 'signaling';
const String kCandidatesSubcollection = 'candidates';

// ─── Foreground Service ─────────────────────────────────────────────────────
const String kNotificationChannelId = 'wifi_voice_room';
const String kNotificationChannelName = 'WiFi Voice Room';
const int kNotificationId = 100;
