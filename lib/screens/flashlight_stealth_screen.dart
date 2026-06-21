import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:torch_light/torch_light.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/auth_provider.dart';
import '../providers/presence_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/foreground_service.dart';
import '../providers/webrtc_provider.dart';
import '../providers/update_provider.dart';
import '../services/notification_service.dart';
import '../core/constants.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class FlashlightStealthScreen extends ConsumerStatefulWidget {
  const FlashlightStealthScreen({super.key});

  @override
  ConsumerState<FlashlightStealthScreen> createState() => _FlashlightStealthScreenState();
}

class _FlashlightStealthScreenState extends ConsumerState<FlashlightStealthScreen> {
  bool _isLedOn = false;
  bool _isScreenLightOn = false;
  bool _isStrobeOn = false;
  double _screenIntensity = 0.5;
  
  Timer? _strobeTimer;
  Timer? _autoOffTimer;

  // Settings
  bool _hapticEnabled = true;
  bool _autoOffEnabled = false;

  // Ghost Dial — user's own assigned combo
  int _myHz = 0;
  int _myBrightness = 0;

  // Ghost Dial — the "dial" values the user is currently selecting
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

  // OTA Update
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _initBrightness();
    _loadSettings();
    _initGhostDial();
  }

  Future<void> _initGhostDial() async {
    // Request location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse) {
      await Geolocator.requestPermission();
    }

    final authService = ref.read(authServiceProvider);
    final currentUser = FirebaseAuth.instance.currentUser;
    
    // If user is completely unauthenticated, log them in anonymously.
    if (currentUser == null) {
      await authService.signInAnonymously();
    } else {
      // Ensure existing users get a combo assigned if they don't have one
      await authService.ensureUserHasCombo(currentUser.uid);
    }
    
    // Load the assigned combo
    final userAfterAuth = FirebaseAuth.instance.currentUser;
    if (userAfterAuth != null) {
      final presenceService = ref.read(presenceServiceProvider);
      await presenceService.goOnline(userAfterAuth.uid, initialMicOn: false);
      
      // Save FCM token
      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.initialize();
      await notificationService.saveToken(userAfterAuth.uid);

      // Listen to assigned combo
      FirebaseFirestore.instance
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
  }

  void _listenForIncomingCalls(String myUid) {
    // Listen to the 'stealth_calls' collection for calls targeted at this user
    FirebaseFirestore.instance
        .collection('stealth_calls')
        .where('targetUid', isEqualTo: myUid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty && !_isStealthConnected) {
        final callDoc = snapshot.docs.first;
        final data = callDoc.data();
        final roomId = data['roomId'] as String?;
        final callerUid = data['callerUid'] as String?;
        
        if (roomId != null && callerUid != null) {
          setState(() {
            _hasIncomingCall = true;
            _incomingRoomId = roomId;
          });
          
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

      setState(() {
        _isStealthConnected = true;
        _isSpeakerMuted = true;
      });

      // Mark call as accepted
      await FirebaseFirestore.instance
          .collection('stealth_calls')
          .doc(callDocId)
          .update({'status': 'connected'});
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
    _strobeTimer?.cancel();
    _autoOffTimer?.cancel();
    _stealthHoldTimer?.cancel();
    _drawHoldTimer?.cancel();
    _invalidFeedbackTimer?.cancel();
    _outboundCallSub?.cancel();
    super.dispose();
  }

  // --- LED TEMP Hold → Dial & Connect ---
  void _handleStealthHoldStart(LongPressStartDetails details) {
    if (_stealthHoldTimer != null && _stealthHoldTimer!.isActive) return;
    
    _stealthHoldTicks = 0;
    
    _stealthHoldTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _stealthHoldTicks++;
      
      if (_stealthHoldTicks < 50) {
        if (_hapticEnabled) {
          if (_stealthHoldTicks <= 20 && _stealthHoldTicks % 5 == 0) {
            HapticFeedback.lightImpact();
          } else if (_stealthHoldTicks > 20 && _stealthHoldTicks <= 35 && _stealthHoldTicks % 3 == 0) {
            HapticFeedback.mediumImpact();
          } else if (_stealthHoldTicks > 35) {
            HapticFeedback.heavyImpact();
          }
        }
      } else {
        timer.cancel();
        
        if (_hapticEnabled) {
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
    }
  }

  // --- DRAW Hold → Unmute Speaker ---
  void _handleDrawHoldStart(LongPressStartDetails details) {
    if (!_isStealthConnected || !_isSpeakerMuted) return;
    if (_drawHoldTimer != null && _drawHoldTimer!.isActive) return;
    
    _drawHoldTicks = 0;
    
    _drawHoldTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _drawHoldTicks++;
      
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

      // Create a stealth room
      final roomId = 'ghost_${currentUser.uid}_${targetUid}_${DateTime.now().millisecondsSinceEpoch}';

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
    setState(() {
      _isStealthConnected = false;
      _isSpeakerMuted = true;
      _hasIncomingCall = false;
      _outboundCallStatus = null;
    });
    
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
      _strobeTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) async {
        try {
          if (flashState) {
            await TorchLight.enableTorch();
          } else {
            await TorchLight.disableTorch();
          }
          flashState = !flashState;
        } catch (_) {}
      });
    }
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

  // --- Full Screen Settings ---
  void _openFullScreenSettings() {
    // Check for updates as soon as settings open
    ref.read(updateProvider.notifier).checkForUpdate();
    
    bool _muteOnExit = true;
    
    SharedPreferences.getInstance().then((prefs) {
      _muteOnExit = prefs.getBool('muteOnBackground') ?? true;
    });

    showGeneralDialog(
      context: context,
      barrierColor: Colors.black,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setStateDialog) => Scaffold(
            backgroundColor: const Color(0xFF0A0C0E),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.settings_applications, color: Color(0xFF00FF41), size: 32),
                                          const SizedBox(width: 12),
                                          const Text(
                                            'SYS_CONFIG //',
                                            style: TextStyle(
                                              color: Color(0xFF00FF41),
                                              fontSize: 22,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 2,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white54, size: 32),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ],
                                  ),
                                  const Divider(color: Colors.white24, height: 48),
                                  
                                  _buildSettingsToggle(
                                    label: 'HAPTIC_MODULE',
                                    value: _hapticEnabled,
                                    onChanged: (val) {
                                      setState(() => _hapticEnabled = val);
                                      setStateDialog(() => _hapticEnabled = val);
                                      _saveSetting('hapticEnabled', val);
                                      if (val) HapticFeedback.lightImpact();
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  _buildSettingsToggle(
                                    label: 'AUTO_CUTOFF(10M)',
                                    value: _autoOffEnabled,
                                    onChanged: (val) {
                                      setState(() => _autoOffEnabled = val);
                                      setStateDialog(() => _autoOffEnabled = val);
                                      _saveSetting('autoOffEnabled', val);
                                      _triggerHaptic();
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  _buildSettingsToggle(
                                    label: 'AUDIO_TELEMETRY_CUTOFF',
                                    value: _muteOnExit,
                                    onChanged: (val) async {
                                      setStateDialog(() => _muteOnExit = val);
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setBool('muteOnBackground', val);
                                      _triggerHaptic();
                                    },
                                  ),
                                  const SizedBox(height: 48),

                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () async {
                                        _triggerHaptic();
                                        await Permission.ignoreBatteryOptimizations.request();
                                      },
                                      icon: const Icon(Icons.battery_charging_full),
                                      label: const Text('OVERRIDE_BATTERY_LIMITS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white12,
                                        foregroundColor: Colors.white70,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),

                                  Center(
                                    child: Consumer(
                                      builder: (context, ref, child) {
                                        final updateState = ref.watch(updateProvider);
                                        return Text(
                                          'FIRMWARE_VER: ${updateState.currentVersion ?? "Loading..."}\nBUILD_TAG: SECURE_WIFI_OTA',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white30,
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                            letterSpacing: 1,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  SizedBox(
                                    width: double.infinity,
                                    child: Consumer(
                                      builder: (context, ref, child) {
                                        final updateState = ref.watch(updateProvider);
                                        
                                        if (_isDownloading) {
                                          return Column(
                                            children: [
                                              const Text('DOWNLOADING OTA...', style: TextStyle(color: Color(0xFF00FF41), fontFamily: 'monospace')),
                                              const SizedBox(height: 12),
                                              LinearProgressIndicator(
                                                value: _downloadProgress,
                                                backgroundColor: Colors.white12,
                                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00FF41)),
                                              ),
                                            ],
                                          );
                                        }
                                        
                                        if (updateState.isChecking) {
                                          return ElevatedButton(
                                            onPressed: null,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.white12,
                                              padding: const EdgeInsets.symmetric(vertical: 20),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            child: const Text('CHECKING GITHUB SERVER...', style: TextStyle(color: Colors.white54, fontFamily: 'monospace')),
                                          );
                                        }
                                        
                                        if (updateState.updateAvailable && updateState.apkUrl != null) {
                                          return ElevatedButton(
                                            onPressed: () {
                                              _triggerHaptic();
                                              _downloadAndInstallUpdate(updateState.apkUrl!, updateState.latestVersion!, setStateDialog);
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF00FF41).withOpacity(0.2),
                                              side: const BorderSide(color: Color(0xFF00FF41), width: 2),
                                              padding: const EdgeInsets.symmetric(vertical: 20),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            child: Text('INSTALL UPDATE (${updateState.latestVersion})', style: const TextStyle(color: Color(0xFF00FF41), fontWeight: FontWeight.bold, letterSpacing: 2)),
                                          );
                                        }

                                        return ElevatedButton(
                                          onPressed: () {
                                            _triggerHaptic();
                                            ref.read(updateProvider.notifier).checkForUpdate();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.white12,
                                            padding: const EdgeInsets.symmetric(vertical: 20),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          child: const Text('FIRMWARE UP TO DATE (CHECK AGAIN)', style: TextStyle(color: Colors.white54, fontFamily: 'monospace')),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
        );
      },
    );
  }

  Future<void> _downloadAndInstallUpdate(String apkUrl, String version, StateSetter setStateDialog) async {
    setState(() { _isDownloading = true; _downloadProgress = 0.0; });
    setStateDialog(() { _isDownloading = true; _downloadProgress = 0.0; });
    
    try {
      final dir = await getTemporaryDirectory();
      final safeVersion = version.replaceAll('+', '_');
      final savePath = '${dir.path}/update_$safeVersion.apk';
      
      final file = File(savePath);
      // If the file exists, we forcefully delete it and re-download it to prevent corrupt package parsing
      if (await file.exists()) {
        await file.delete();
      }
      
      final dio = Dio();
      await dio.download(
        apkUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() { _downloadProgress = received / total; });
            setStateDialog(() { _downloadProgress = received / total; });
          }
        },
      );
      
      final result = await OpenFilex.open(savePath);
      debugPrint("OpenFile result: ${result.message}");
      
    } catch (e) {
      debugPrint("Download failed: $e");
    } finally {
      if (mounted) {
        setState(() { _isDownloading = false; });
        setStateDialog(() { _isDownloading = false; });
      }
    }
  }

  Widget _buildSettingsToggle({required String label, required bool value, required ValueChanged<bool> onChanged}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 16)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF00FF41),
          inactiveThumbColor: Colors.grey,
          inactiveTrackColor: Colors.white12,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFF00FF41);
    const dangerColor = Color(0xFFFF003C);
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

    // Determine OUTPUT display
    String outputValue = isActive ? '1200 LM' : '0 LM';
    Color outputColor = statusColor;

    if (_outboundCallStatus == 'invalid') {
      outputValue = 'ERR: NULL';
      outputColor = dangerColor; // Red
    } else if (_outboundCallStatus == 'ringing' || _outboundCallStatus == 'connected') {
      outputValue = 'DIALING..';
      outputColor = const Color(0xFFFF8800); // Yellow/Orange
    } else if (_outboundCallStatus == 'unmuted') {
      outputValue = 'LINK ACTV';
      outputColor = accentColor; // Green
    }

    return Scaffold(
      backgroundColor: _isScreenLightOn ? Colors.white : darkBg,
      body: SafeArea(
        child: _isScreenLightOn
            ? _buildScreenLightMode(accentColor)
            : Column(
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
                          onPressed: _openFullScreenSettings,
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
                                  onLongPressStart: _handleStealthHoldStart,
                                  onLongPressEnd: (_) => _handleStealthHoldEnd(),
                                  onLongPressCancel: _handleStealthHoldEnd,
                                  child: _buildTelemetryStat(
                                    'LED TEMP', 
                                    ledTempValue, 
                                    ledTempColor,
                                  ),
                                ),
                                Container(width: 1, height: 40, color: Colors.white10),
                                // OUTPUT display
                                _buildTelemetryStat('OUTPUT', outputValue, outputColor),
                                Container(width: 1, height: 40, color: Colors.white10),
                                // DRAW — shows user's own "phone number", hold 2s to unmute
                                GestureDetector(
                                  onLongPressStart: _handleDrawHoldStart,
                                  onLongPressEnd: (_) => _handleDrawHoldEnd(),
                                  onLongPressCancel: _handleDrawHoldEnd,
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

                          // --- Main Power Button with Brightness Ring ---
                          _buildPowerButtonWithBrightnessRing(accentColor, panelColor),

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
                                          overlayColor: accentColor.withOpacity(0.2),
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
              ),
      ),
    );
  }

  /// Power button with a circular brightness dial around it
  Widget _buildPowerButtonWithBrightnessRing(Color accentColor, Color panelColor) {
    const dangerColor = Color(0xFFFF003C);
    
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
                activeColor: _isStealthConnected ? dangerColor : accentColor,
              ),
            ),
          ),
          // Circular brightness slider (invisible gesture detector around the ring)
          GestureDetector(
            onPanUpdate: (details) {
              // Calculate angle from center
              final center = Offset(130, 130);
              final pos = details.localPosition;
              final dx = pos.dx - center.dx;
              final dy = pos.dy - center.dy;
              final distance = sqrt(dx * dx + dy * dy);
              
              // Only respond to touches near the ring (90-130 pixel radius)
              if (distance < 85 || distance > 135) return;
              
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
                  color: _isLedOn ? accentColor : Colors.white12,
                  width: 4,
                ),
                boxShadow: _isLedOn
                    ? [
                        BoxShadow(
                          color: accentColor.withOpacity(0.3),
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
                          color: Colors.white.withOpacity(0.05),
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
                            ? [accentColor.withOpacity(0.2), panelColor]
                            : [const Color(0xFF22282D), const Color(0xFF111417)],
                      ),
                      border: Border.all(color: Colors.black54, width: 2),
                    ),
                  ),
                  Icon(
                    Icons.power_settings_new_rounded,
                    size: 64,
                    color: _isLedOn ? accentColor : Colors.grey[700],
                  ),
                  // Small brightness value label at bottom of button
                  Positioned(
                    bottom: 28,
                    child: Text(
                      '$_dialBrightness',
                      style: TextStyle(
                        color: _isStealthConnected ? dangerColor : Colors.white30,
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
    return Stack(
      children: [
        Center(
          child: IconButton(
            iconSize: 100,
            icon: Icon(Icons.power_settings_new, color: Colors.grey[300]),
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
            inactiveColor: Colors.grey[300],
            onChanged: _updateScreenIntensity,
          ),
        ),
      ],
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
  }) {
    return GestureDetector(
      onTap: () {
        _triggerHaptic();
        onTap();
      },
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.1) : const Color(0xFF101214),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? activeColor : Colors.white10,
            width: 2,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: activeColor.withOpacity(0.2), blurRadius: 10)]
              : [const BoxShadow(color: Colors.black54, blurRadius: 5, offset: Offset(0, 3))],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isActive ? activeColor : Colors.grey[600],
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? activeColor : Colors.grey[600],
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
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
