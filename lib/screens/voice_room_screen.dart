import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/constants.dart';
import '../core/app_theme.dart';
import '../models/room_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/webrtc_provider.dart';
import '../providers/presence_provider.dart';
import '../providers/audio_provider.dart';
import '../providers/settings_provider.dart';
import '../services/foreground_service.dart';
import '../services/webrtc_service.dart';
import '../services/notification_service.dart';
import '../services/invite_service.dart';

class VoiceRoomScreen extends ConsumerStatefulWidget {
  final RoomModel room;
  
  const VoiceRoomScreen({super.key, required this.room});

  @override
  ConsumerState<VoiceRoomScreen> createState() => _VoiceRoomScreenState();
}

class _VoiceRoomScreenState extends ConsumerState<VoiceRoomScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _connectionPulseController;
  bool _isInitialized = false;
  String _audioRoute = 'speaker'; // Default
  bool _hasBluetooth = false;

  Timer? _sessionTimer;
  Duration _sessionDuration = Duration.zero;

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionDuration = Duration.zero;
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _sessionDuration += const Duration(seconds: 1));
    });
  }

  void _stopSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    if (mounted) setState(() => _sessionDuration = Duration.zero);
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _changeAudioRoute(String? newRoute) {
    if (newRoute == null) return;
    HapticFeedback.selectionClick();
    setState(() => _audioRoute = newRoute);
    if (newRoute == 'speaker') {
      ref.read(webrtcServiceProvider).setSpeakerphoneOn(true);
    } else {
      ref.read(webrtcServiceProvider).setSpeakerphoneOn(false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _connectionPulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _checkAudioDevices();
  }

  Future<void> _checkAudioDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      bool foundBluetooth = false;
      for (var device in devices) {
        final label = device.label.toLowerCase();
        if (label.contains('bluetooth') || label.contains('ble') || label.contains('bt')) {
          foundBluetooth = true;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _hasBluetooth = foundBluetooth;
          if (_hasBluetooth) {
            _changeAudioRoute('bluetooth');
          }
        });
      }
    } catch (e) {
      debugPrint("Audio device check failed: $e");
    }
  }

  Future<void> _joinRoom() async {
    HapticFeedback.heavyImpact();
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    
    ref.read(joinedRoomIdProvider.notifier).state = widget.room.roomId;

    final settings = ref.read(settingsProvider);
    if (settings.autoMuteMic) {
      ref.read(micStateProvider.notifier).state = false;
      ref.read(webrtcServiceProvider).setMicEnabled(false);
    }

    _startSessionTimer();
    _initializeConnection();
  }

  Future<void> _initializeConnection() async {
    if (_isInitialized) return;

    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    _isInitialized = true;

    try {
      final micStatus = await Permission.microphone.request();
      if (micStatus != PermissionStatus.granted) {
        _isInitialized = false;
        if (mounted) Navigator.of(context).pop();
        return;
      }

      // Request battery optimization exemption to keep background connection active
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }

      try {
        await startForegroundService();
      } catch (e) {
        debugPrint('[VoiceRoom] ERROR starting foreground service: $e');
      }

      final presenceService = ref.read(presenceServiceProvider);
      await presenceService.goOnline(user.userId);

      final settings = ref.read(settingsProvider);

      final webrtcService = ref.read(webrtcServiceProvider);
      webrtcService.onConnectionStateChanged = (partnerId, state) {
        if (mounted) {
          final currentStates = ref.read(webrtcConnectionStatesProvider);
          ref.read(webrtcConnectionStatesProvider.notifier).state = {
            ...currentStates,
            partnerId: state,
          };

          if (state == WebRTCConnectionState.disconnected ||
              state == WebRTCConnectionState.failed) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) _renegotiate(partnerId);
            });
          }
        }
      };

      final signalingService = ref.read(signalingServiceProvider);
      await signalingService.startSignaling(
        roomId: widget.room.roomId,
        myUserId: user.userId,
        partnerIds: [], 
        echoCancellation: settings.echoCancellation,
        noiseSuppression: settings.noiseSuppression,
      );
      
      // Default to speakerphone on join so users can hear each other loudly
      await webrtcService.setSpeakerphoneOn(true);
    } catch (e) {
      _isInitialized = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _renegotiate(String partnerId) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    final signalingService = ref.read(signalingServiceProvider);
    await signalingService.removePartner(partnerId);
    await Future.delayed(const Duration(milliseconds: 500));
    await signalingService.addPartner(partnerId);
  }

  void _toggleHear() {
    HapticFeedback.lightImpact();
    final current = ref.read(listeningStateProvider);
    final newState = !current;
    ref.read(listeningStateProvider.notifier).state = newState;

    ref.read(webrtcServiceProvider).setListening(newState);

    final user = ref.read(currentUserProvider).value;
    if (user != null) {
      ref.read(presenceServiceProvider).updateListeningStatus(newState);
    }
  }

  void _toggleMic() {
    HapticFeedback.mediumImpact();
    final current = ref.read(micStateProvider);
    final newState = !current;
    ref.read(micStateProvider.notifier).state = newState;

    ref.read(webrtcServiceProvider).setMicEnabled(newState);

    final user = ref.read(currentUserProvider).value;
    if (user != null) {
      ref.read(presenceServiceProvider).updateMicStatus(newState);
    }
  }

  Future<void> _leaveRoom() async {
    HapticFeedback.vibrate();
    
    // Add confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Leave Channel?', style: AppTextStyles.heading3),
        content: Text('Are you sure you want to disconnect?', style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          GlassButton(
            label: 'Leave',
            filled: true,
            color: AppColors.danger,
            borderRadius: 12,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final user = ref.read(currentUserProvider).valueOrNull;
    if (user != null) {
      await FirebaseFirestore.instance.collection(kUsersCollection).doc(user.userId).update({
        'roomId': FieldValue.delete(),
      });
    }

    await ref.read(signalingServiceProvider).stopSignaling();
    await ref.read(webrtcServiceProvider).disposeAll();
    await stopForegroundService();
    _stopSessionTimer();
    
    _isInitialized = false;
    ref.read(joinedRoomIdProvider.notifier).state = null;
    ref.read(micStateProvider.notifier).state = true;
    ref.read(listeningStateProvider.notifier).state = true;
    
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showRenameDialog(RoomModel currentRoom) async {
    final TextEditingController controller = TextEditingController(text: currentRoom.roomName);
    
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rename Channel', style: AppTextStyles.heading3),
        content: GlassTextField(
          controller: controller,
          hintText: 'Channel Name',
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          GlassButton(
            label: 'Save',
            filled: true,
            borderRadius: 12,
            onTap: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(ctx).pop(name);
              }
            },
          ),
        ],
      ),
    );

    if (newName != null && newName != currentRoom.roomName) {
      HapticFeedback.lightImpact();
      await FirebaseFirestore.instance.collection(kRoomsCollection).doc(currentRoom.roomId).update({
        'roomName': newName,
      });
    }
  }

  Future<void> _deleteRoom() async {
    HapticFeedback.vibrate();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Channel?', style: AppTextStyles.heading3.copyWith(color: AppColors.danger)),
        content: Text('Are you sure you want to permanently delete this channel? All members will be disconnected.', style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppTextStyles.buttonText.copyWith(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger.withOpacity(0.2),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Delete', style: AppTextStyles.buttonText.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final user = ref.read(currentUserProvider).value;
    if (user != null) {
      await ref.read(presenceServiceProvider).goOffline();
    }
    
    await ref.read(signalingServiceProvider).stopSignaling();
    await ref.read(webrtcServiceProvider).disposeAll();
    await stopForegroundService();

    await FirebaseFirestore.instance.collection(kRoomsCollection).doc(widget.room.roomId).delete();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showInviteDialog(UserModel? currentUser, RoomModel currentRoom) async {
    if (currentUser == null) return;
    HapticFeedback.selectionClick();
    
    final TextEditingController controller = TextEditingController();
    final inviteService = ref.read(inviteServiceProvider);
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Invite Member', style: AppTextStyles.heading3),
        content: GlassTextField(
          controller: controller,
          hintText: 'Enter exact username',
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: AppTextStyles.buttonText.copyWith(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              HapticFeedback.lightImpact();
              final alias = controller.text.trim();
              if (alias.isEmpty) return;
              
              Navigator.of(ctx).pop();
              
              final targetUser = await inviteService.findUserByUsername(alias);
              if (targetUser == null) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User not found'), backgroundColor: AppColors.danger),
                  );
                }
                return;
              }

              final isAlreadyMember = (currentRoom.memberIds ?? []).contains(targetUser.userId);
              if (isAlreadyMember) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User is already in this room'), backgroundColor: AppColors.warning),
                  );
                }
                return;
              }
              
              await inviteService.sendInvite(
                fromUserId: currentUser.userId,
                fromUsername: currentUser.username,
                toUserId: targetUser.userId,
                toUsername: targetUser.username,
                roomId: currentRoom.roomId,
                roomName: currentRoom.roomName,
              );
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Invite sent to ${targetUser.username}'), backgroundColor: AppColors.success),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent.withOpacity(0.2),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Invite', style: AppTextStyles.buttonText.copyWith(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectionPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection(kRoomsCollection).doc(widget.room.roomId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(backgroundColor: AppColors.bgElevated, body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
        }
        
        final roomData = snapshot.data!.data() as Map<String, dynamic>?;
        if (roomData == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const Scaffold(backgroundColor: AppColors.bgElevated, body: Center(child: Text('Room deleted')));
        }
        
        final currentRoom = RoomModel.fromMap(roomData);
        
        final isListening = ref.watch(listeningStateProvider);
        final isMicOn = ref.watch(micStateProvider);
        final partners = ref.watch(partnersProvider).valueOrNull ?? [];
        final currentUser = ref.watch(currentUserProvider).valueOrNull;

        final isActive = ref.watch(isWebrtcActiveProvider);
        final joinedRoomId = ref.watch(joinedRoomIdProvider);
        final isJoined = joinedRoomId == currentRoom.roomId;
        final settings = ref.watch(settingsProvider);

        return GradientScaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: _buildTopSection(isActive, currentUser, isJoined, currentRoom),
                ),
                
                if (isJoined && currentUser != null && currentUser.userId == currentRoom.ownerId)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: GlassButton(
                      label: 'Invite Member',
                      filled: false,
                      onTap: () => _showInviteDialog(currentUser, currentRoom),
                      borderRadius: 12,
                    ),
                  ),

                Expanded(
                  child: StreamBuilder<List<InviteModel>>(
                    stream: ref.watch(inviteServiceProvider).listenForRoomInvites(currentRoom.roomId),
                    builder: (context, inviteSnapshot) {
                      final rawInvites = inviteSnapshot.data ?? [];
                      
                      // Filter out invites for users who are already members
                      final pendingInvites = rawInvites.where((invite) {
                        return !(currentRoom.memberIds ?? []).contains(invite.toUserId);
                      }).toList();
                      
                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: partners.length + pendingInvites.length + (currentUser != null ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == 0 && currentUser != null) {
                            return _MyUserCard(user: currentUser, isMicOn: isMicOn, isJoined: isJoined);
                          }
                          
                          final remainingIndex = currentUser != null ? index - 1 : index;
                          if (remainingIndex < partners.length) {
                            return _PartnerUserCard(partner: partners[remainingIndex], roomId: currentRoom.roomId);
                          }
                          
                          final inviteIndex = remainingIndex - partners.length;
                          return _PendingInviteCard(invite: pendingInvites[inviteIndex]);
                        },
                      );
                    }
                  ),
                ),

                if (isJoined)
                  _buildBottomControlBar(isMicOn, isListening, settings)
                else
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: GlassButton(
                        label: 'Join Channel',
                        filled: true,
                        onTap: _joinRoom,
                        borderRadius: 28,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildTopSection(bool isActive, UserModel? currentUser, bool isJoined, RoomModel currentRoom) {
    final isOwner = currentUser?.userId == currentRoom.ownerId;

    return Column(
      children: [
        // App title & actions
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentRoom.roomName,
                    style: AppTextStyles.heading2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isJoined ? AppColors.success.withOpacity(0.15) : AppColors.textSecondary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isJoined ? 'Connected' : 'Not Joined',
                          style: AppTextStyles.label.copyWith(color: isJoined ? AppColors.success : AppColors.textSecondary, fontSize: 10),
                        ),
                      ),
                      if (isJoined) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _formatDuration(_sessionDuration),
                            style: AppTextStyles.label.copyWith(color: AppColors.accent, fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
              Row(
                children: [
                  if (isOwner) ...[
                    GlassIconButton(
                      icon: Icons.edit_rounded,
                      size: 40,
                      onTap: () => _showRenameDialog(currentRoom),
                    ),
                    const SizedBox(width: 8),
                    GlassIconButton(
                      icon: Icons.delete_outline_rounded,
                      color: AppColors.danger,
                      size: 40,
                      onTap: _deleteRoom,
                    ),
                  ],
                if (isOwner) ...[
                  const SizedBox(width: 8),
                  GlassIconButton(
                    icon: Icons.person_add_alt_1_rounded,
                    size: 40,
                    onTap: () => _showInviteDialog(currentUser, currentRoom),
                  ),
                ],
                const SizedBox(width: 8),
                GlassIconButton(
                  icon: isJoined ? Icons.logout_rounded : Icons.close_rounded,
                  color: isJoined ? AppColors.danger : AppColors.textPrimary,
                  size: 40,
                  onTap: isJoined ? _leaveRoom : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Audio Routing segmented control style
        GlassPanel(
          padding: const EdgeInsets.all(4),
          borderRadius: 16,
          child: Row(
            children: [
              _AudioRouteChip(
                label: 'Earpiece',
                icon: Icons.phone_in_talk_rounded,
                isSelected: _audioRoute == 'earpiece',
                onTap: () => _changeAudioRoute('earpiece'),
              ),
              _AudioRouteChip(
                label: 'Speaker',
                icon: Icons.volume_up_rounded,
                isSelected: _audioRoute == 'speaker',
                onTap: () => _changeAudioRoute('speaker'),
              ),
              if (_hasBluetooth)
                _AudioRouteChip(
                  label: 'Bluetooth',
                  icon: Icons.bluetooth_audio_rounded,
                  isSelected: _audioRoute == 'bluetooth',
                  onTap: () => _changeAudioRoute('bluetooth'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomControlBar(bool isMicOn, bool isListening, SettingsState settings) {
    return GlassPanel(
      borderRadius: 0,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Speaker toggle
          GlassIconButton(
            icon: isListening ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            size: 56,
            isActive: !isListening,
            activeColor: AppColors.danger,
            onTap: _toggleHear,
          ),
          
          // Main Mic Toggle
          GestureDetector(
            onTap: _toggleMic,
            child: AnimatedScale(
              scale: isMicOn ? 1.0 : 0.95,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isMicOn ? AppColors.success.withOpacity(0.2) : AppColors.danger.withOpacity(0.15),
                  border: Border.all(
                    color: isMicOn ? AppColors.success : AppColors.danger.withOpacity(0.5),
                    width: isMicOn ? 3 : 1,
                  ),
                  boxShadow: isMicOn ? [BoxShadow(color: AppColors.success.withOpacity(0.3), blurRadius: 20)] : null,
                ),
                child: Icon(
                  isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                  color: isMicOn ? AppColors.success : AppColors.danger,
                  size: 36,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioRouteChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _AudioRouteChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accent.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: isSelected ? AppColors.textPrimary : AppColors.textSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTextStyles.label.copyWith(
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── User Cards ────────────────────────────────────────────────────────────

class _MyUserCard extends StatelessWidget {
  final UserModel user;
  final bool isMicOn;
  final bool isJoined;

  const _MyUserCard({required this.user, required this.isMicOn, required this.isJoined});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.2),
              shape: BoxShape.circle,
              border: isMicOn && isJoined
                  ? Border.all(color: AppColors.success, width: 2)
                  : Border.all(color: AppColors.accent.withOpacity(0.3)),
              boxShadow: isMicOn && isJoined ? [BoxShadow(color: AppColors.success.withOpacity(0.3), blurRadius: 12)] : null,
            ),
            child: Text(
              user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
              style: AppTextStyles.heading2.copyWith(color: AppColors.accentSoft),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            user.username,
            style: AppTextStyles.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text('(You)', style: AppTextStyles.caption.copyWith(fontSize: 11)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (isMicOn ? AppColors.success : AppColors.danger).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              color: isMicOn ? AppColors.success : AppColors.danger,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerUserCard extends ConsumerStatefulWidget {
  final UserModel partner;
  final String roomId;

  const _PartnerUserCard({required this.partner, required this.roomId});

  @override
  ConsumerState<_PartnerUserCard> createState() => _PartnerUserCardState();
}

class _PartnerUserCardState extends ConsumerState<_PartnerUserCard> {
  bool _canRing = true;

  String _formatLastSeen(DateTime lastSeen) {
    final diff = DateTime.now().difference(lastSeen);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  void _togglePartnerMute(WidgetRef ref, bool currentlyMuted) {
    HapticFeedback.selectionClick();
    final newState = !currentlyMuted;
    final currentMutedMap = ref.read(partnerMuteStatesProvider);
    ref.read(partnerMuteStatesProvider.notifier).state = {
      ...currentMutedMap,
      widget.partner.userId: newState,
    };
    
    ref.read(webrtcServiceProvider).setPartnerListening(widget.partner.userId, !newState);
  }

  void _ringPartner(WidgetRef ref) {
    if (!_canRing) return;
    HapticFeedback.heavyImpact();
    if (widget.partner.fcmToken != null) {
      ref.read(notificationServiceProvider).sendDisguisedRing(
        targetToken: widget.partner.fcmToken!,
        roomId: widget.roomId,
      );
      
      setState(() => _canRing = false);
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted) setState(() => _canRing = true);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ring sent ✓ (Cooldown: 30s)'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final presence = ref.watch(partnerPresenceProvider(widget.partner.userId)).valueOrNull;
    final isOnline = presence?.online ?? false;
    final isMicOn = presence?.micOn ?? false;
    final states = ref.watch(webrtcConnectionStatesProvider);
    final state = states[widget.partner.userId] ?? WebRTCConnectionState.idle;
    final isConnected = state == WebRTCConnectionState.connected;

    final mutedMap = ref.watch(partnerMuteStatesProvider);
    final isMutedLocally = mutedMap[widget.partner.userId] ?? false;
    final inBackground = presence?.inBackground ?? false;

    Color statusColor;
    if (isOnline) {
      if (inBackground) {
        statusColor = AppColors.warning;
      } else {
        statusColor = isConnected ? AppColors.success : AppColors.warning;
      }
    } else {
      statusColor = AppColors.textSecondary;
    }

    return GlassPanel(
      padding: const EdgeInsets.all(12),
      borderRadius: 20,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: statusColor.withOpacity(0.4)),
              boxShadow: isOnline && isConnected ? [
                BoxShadow(color: statusColor.withOpacity(0.2), blurRadius: 10)
              ] : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Text(
                  widget.partner.username.isNotEmpty ? widget.partner.username[0].toUpperCase() : '?',
                  style: AppTextStyles.heading3.copyWith(color: statusColor),
                ),
              ),
              if (isOnline)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(width: 3, height: 4, decoration: BoxDecoration(color: isConnected ? AppColors.success : AppColors.danger, borderRadius: BorderRadius.circular(1))),
                      const SizedBox(width: 1),
                      Container(width: 3, height: 7, decoration: BoxDecoration(color: isConnected ? AppColors.success : AppColors.textSecondary.withOpacity(0.3), borderRadius: BorderRadius.circular(1))),
                      const SizedBox(width: 1),
                      Container(width: 3, height: 10, decoration: BoxDecoration(color: isConnected ? AppColors.success : AppColors.textSecondary.withOpacity(0.3), borderRadius: BorderRadius.circular(1))),
                    ],
                  ),
                ),
            ],
          ),
        ),
          const SizedBox(height: 10),
          Text(
            widget.partner.username,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isOnline ? AppColors.textPrimary : AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            isOnline ? (inBackground ? 'Background' : 'Active') : (presence != null ? _formatLastSeen(presence.lastSeen) : 'Offline'),
            style: AppTextStyles.caption.copyWith(
              color: isOnline ? statusColor : AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isOnline) ...[
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isMicOn ? AppColors.success.withOpacity(0.2) : AppColors.danger.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    color: isMicOn ? AppColors.success : AppColors.danger,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _togglePartnerMute(ref, isMutedLocally),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isMutedLocally ? AppColors.danger.withOpacity(0.2) : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isMutedLocally ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: isMutedLocally ? AppColors.danger : AppColors.textSecondary,
                      size: 16,
                    ),
                  ),
                ),
              ] else ...[
                GestureDetector(
                  onTap: () => _ringPartner(ref),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _canRing ? AppColors.accent.withOpacity(0.2) : AppColors.textSecondary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _canRing ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                      color: _canRing ? AppColors.accent : AppColors.textSecondary,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingInviteCard extends StatelessWidget {
  final InviteModel invite;

  const _PendingInviteCard({required this.invite});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      borderRadius: 20,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.textSecondary.withOpacity(0.3)),
            ),
            child: Text(
              invite.toUsername.isNotEmpty ? invite.toUsername[0].toUpperCase() : '?',
              style: AppTextStyles.heading3.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            invite.toUsername,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            'Invited',
            style: AppTextStyles.caption.copyWith(color: AppColors.accent, fontSize: 10),
          ),
          const Spacer(),
          Container(
             padding: const EdgeInsets.all(4),
             decoration: BoxDecoration(
               color: AppColors.accent.withOpacity(0.1),
               shape: BoxShape.circle,
             ),
             child: const Icon(Icons.hourglass_empty_rounded, size: 14, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}
