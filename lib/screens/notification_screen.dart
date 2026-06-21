import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/app_theme.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/invite_service.dart';
import '../services/firestore_service.dart';

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;

    return GradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Notifications', style: AppTextStyles.heading3),
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : StreamBuilder<List<InviteModel>>(
              stream: ref.watch(inviteServiceProvider).listenForInvites(user.userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.accent));
                }

                final invites = snapshot.data ?? [];

                if (invites.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_none_rounded, size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No notifications',
                          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  itemCount: invites.length,
                  itemBuilder: (context, index) {
                    final invite = invites[index];
                    return _InviteCard(invite: invite, user: user);
                  },
                );
              },
            ),
    );
  }
}

class _InviteCard extends ConsumerWidget {
  final InviteModel invite;
  final UserModel user;

  const _InviteCard({required this.invite, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeFormat = DateFormat.jm().format(invite.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        borderRadius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: AppColors.accentSoft),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invite.fromUsername,
                        style: AppTextStyles.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Invited you to join ${invite.roomName}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                Text(
                  timeFormat,
                  style: AppTextStyles.label.copyWith(fontWeight: FontWeight.normal),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Decline',
                    color: AppColors.textSecondary,
                    filled: false,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref.read(inviteServiceProvider).deleteInvite(invite.id);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: 'Accept',
                    color: AppColors.accent,
                    filled: true,
                    onTap: () async {
                      HapticFeedback.mediumImpact();
                      ref.read(inviteServiceProvider).deleteInvite(invite.id);
                      final firestoreService = ref.read(firestoreServiceProvider);
                      await firestoreService.joinRoom(user.userId, invite.roomId);
                      
                      if (context.mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(
                             content: Text('Joined ${invite.roomName}'),
                             backgroundColor: AppColors.bgElevated,
                             behavior: SnackBarBehavior.floating,
                           )
                         );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
