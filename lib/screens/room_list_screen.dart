/// Room List screen with Liquid Glass aesthetic.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants.dart';
import '../core/app_theme.dart';
import '../providers/presence_provider.dart';
import '../providers/update_provider.dart';
import '../models/user_model.dart';
import '../models/room_model.dart';
import '../providers/auth_provider.dart';
import '../providers/webrtc_provider.dart';
import '../services/invite_service.dart';
import 'voice_room_screen.dart';
import 'create_room_screen.dart';

class RoomListScreen extends ConsumerStatefulWidget {
  const RoomListScreen({super.key});

  @override
  ConsumerState<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends ConsumerState<RoomListScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final permissions = [
      Permission.microphone,
      Permission.notification,
      Permission.locationWhenInUse,
      Permission.camera,
      Permission.photos,
      Permission.storage,
    ];
    
    for (var perm in permissions) {
      final status = await perm.status;
      if (!status.isGranted) {
        await perm.request();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Channels', style: AppTextStyles.heading1),
                      const SizedBox(height: 4),
                      Text(
                        user != null ? 'Logged in as ${user.username}' : 'Connecting...',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Notification Bell
                      if (user != null)
                        StreamBuilder<List<InviteModel>>(
                          stream: ref.watch(inviteServiceProvider).listenForInvites(user.userId),
                          builder: (context, snapshot) {
                            final invites = snapshot.data ?? [];
                            final hasUnread = invites.isNotEmpty;
                            return BadgeDot(
                              show: hasUnread,
                              child: GlassIconButton(
                                icon: Icons.notifications_none_rounded,
                                size: 44,
                                onTap: () {
                                  Navigator.of(context).pushNamed('/notifications');
                                },
                              ),
                            );
                          },
                        ),
                      const SizedBox(width: 12),
                      // Settings Gear
                      BadgeDot(
                        show: ref.watch(updateProvider).updateAvailable,
                        child: GlassIconButton(
                          icon: Icons.settings_outlined,
                          size: 44,
                          onTap: () {
                            Navigator.of(context).pushNamed('/settings');
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (user != null && user.lastVisitedRoom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection(kRoomsCollection).doc(user.lastVisitedRoom).get(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
                    final room = RoomModel.fromMap(snapshot.data!.data() as Map<String, dynamic>);
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => VoiceRoomScreen(room: room)));
                      },
                      child: GlassPanel(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        tint: AppColors.accent.withOpacity(0.1),
                        borderRadius: 16,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.2), shape: BoxShape.circle),
                              child: const Icon(Icons.history_rounded, color: AppColors.accent, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Quick Rejoin', style: AppTextStyles.caption.copyWith(color: AppColors.accent)),
                                  Text(room.roomName, style: AppTextStyles.bodyMedium, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Room List
            Expanded(
              child: user == null
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : StreamBuilder<QuerySnapshot>(
                      stream: user.username == 'fayaspss'
                          ? FirebaseFirestore.instance
                              .collection(kRoomsCollection)
                              .snapshots()
                          : FirebaseFirestore.instance
                              .collection(kRoomsCollection)
                              .where('memberIds', arrayContains: user.userId)
                              .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: GlassPanel(
                              padding: const EdgeInsets.all(20),
                              tint: AppColors.danger.withOpacity(0.1),
                              child: const Text(
                                'Failed to load channels',
                                style: TextStyle(color: AppColors.danger),
                              ),
                            ),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return _buildEmptyState();
                        }

                        return RefreshIndicator(
                          color: AppColors.accent,
                          backgroundColor: AppColors.bgElevated,
                          onRefresh: () async {
                            HapticFeedback.lightImpact();
                            await Future.delayed(const Duration(milliseconds: 500));
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final room = RoomModel.fromMap(
                                  docs[index].data() as Map<String, dynamic>);
                              final joinedRoomId = ref.watch(joinedRoomIdProvider);
                              return _buildRoomCard(context, room, user, joinedRoomId);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: user == null ? null : GlassButton(
        label: 'New Channel',
        icon: Icons.add_rounded,
        filled: true,
        borderRadius: 24,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CreateRoomScreen()),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            'No Channels Yet',
            style: AppTextStyles.heading3.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new channel to start talking',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 48),
          const Icon(Icons.arrow_downward_rounded, size: 32, color: AppColors.accent),
          const SizedBox(height: 8),
          Text('Tap New Channel', style: AppTextStyles.caption.copyWith(color: AppColors.accent)),
        ],
      ),
    );
  }

  Widget _buildRoomCard(BuildContext context, RoomModel room, dynamic user, String? joinedRoomId) {
    final isOwner = room.ownerId == user.userId;
    final isCreator = user.username == 'fayaspss';
    final isActive = room.roomId == joinedRoomId;

    Widget cardContent = GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        
        // Fire and forget the Firestore updates to ensure navigation happens instantly
        FirebaseFirestore.instance.collection(kUsersCollection).doc(user.userId).update({
          'roomId': room.roomId,
          'lastVisitedRoom': room.roomId,
        });

        if (isCreator && !room.memberIds.contains(user.userId)) {
          FirebaseFirestore.instance.collection(kRoomsCollection).doc(room.roomId).update({
            'memberIds': FieldValue.arrayUnion([user.userId]),
          });
        }

        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => VoiceRoomScreen(room: room)),
          );
        }
      },
      child: GlassPanel(
        padding: const EdgeInsets.all(20),
        borderRadius: 20,
        borderColor: isActive ? AppColors.success : null,
        borderWidth: isActive ? 2.0 : 1.0,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent.withOpacity(0.3)),
              ),
              child: const Icon(Icons.graphic_eq_rounded, color: AppColors.accent, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.roomName,
                          style: AppTextStyles.heading3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isOwner || isCreator)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: (isOwner ? AppColors.warning : AppColors.accent).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isOwner ? 'Owner' : 'Root',
                            style: AppTextStyles.label.copyWith(
                              color: isOwner ? AppColors.warning : AppColors.accent,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.success.withOpacity(0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6, height: 6,
                                decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'ACTIVE',
                                style: AppTextStyles.label.copyWith(
                                  color: AppColors.success,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${room.memberIds.length} members',
                        style: AppTextStyles.caption,
                      ),
                      const SizedBox(width: 8),
                      StreamBuilder<int>(
                        stream: ref.read(presenceServiceProvider).getOnlineMemberCountStream(room.memberIds),
                        builder: (context, snapshot) {
                          final count = snapshot.data ?? 0;
                          if (count == 0) return const SizedBox.shrink();
                          return Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$count online',
                                style: AppTextStyles.caption.copyWith(color: AppColors.success),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );

    if (isOwner) {
      return Padding(padding: const EdgeInsets.only(bottom: 16), child: cardContent);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Dismissible(
        key: Key(room.roomId),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: AppColors.danger.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.exit_to_app_rounded, color: AppColors.danger),
        ),
        confirmDismiss: (direction) async {
          HapticFeedback.selectionClick();
          return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.bgElevated,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Leave Channel?', style: AppTextStyles.heading3),
              content: Text('Are you sure you want to leave ${room.roomName}? You will need an invite to rejoin.', style: AppTextStyles.bodyMedium),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                ),
                GlassButton(
                  label: 'Leave',
                  filled: true,
                  color: AppColors.danger,
                  borderRadius: 12,
                  onTap: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          );
        },
        onDismissed: (direction) async {
          await FirebaseFirestore.instance.collection(kRoomsCollection).doc(room.roomId).update({
            'memberIds': FieldValue.arrayRemove([user.userId]),
          });
          if (user.lastVisitedRoom == room.roomId) {
            await FirebaseFirestore.instance.collection(kUsersCollection).doc(user.userId).update({
              'lastVisitedRoom': FieldValue.delete(),
            });
          }
        },
        child: cardContent,
      ),
    );
  }
}
