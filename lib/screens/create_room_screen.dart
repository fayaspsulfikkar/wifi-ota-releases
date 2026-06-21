import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../core/app_theme.dart';
import '../models/room_model.dart';
import '../providers/auth_provider.dart';

class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  final _roomNameController = TextEditingController();
  final _searchController = TextEditingController();
  
  final List<Map<String, String>> _invitedUsers = []; // {userId, username}
  bool _isCreating = false;
  bool _isSearching = false;
  
  List<Map<String, String>> _searchResults = [];

  @override
  void dispose() {
    _roomNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isSearching = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(kUsersCollection)
          .where('username', isGreaterThanOrEqualTo: query)
          .where('username', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(5)
          .get();

      final currentUser = ref.read(currentUserProvider).value;

      final results = snapshot.docs
          .map((doc) => {
                'userId': doc.id,
                'username': doc.data()['username'] as String,
              })
          .where((user) => user['userId'] != currentUser?.userId)
          .toList();

      setState(() => _searchResults = results);
    } catch (e) {
      debugPrint('Error searching users: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _toggleInvite(Map<String, String> user) {
    HapticFeedback.selectionClick();
    setState(() {
      final exists = _invitedUsers.any((u) => u['userId'] == user['userId']);
      if (exists) {
        _invitedUsers.removeWhere((u) => u['userId'] == user['userId']);
      } else {
        _invitedUsers.add(user);
      }
    });
  }

  Future<void> _createRoom() async {
    final roomName = _roomNameController.text.trim();
    if (roomName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Please enter a channel name'), backgroundColor: AppColors.bgElevated),
      );
      return;
    }

    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    setState(() => _isCreating = true);

    try {
      final roomId = const Uuid().v4();
      
      final memberIds = [
        currentUser.userId,
        ..._invitedUsers.map((u) => u['userId']!),
      ];

      final room = RoomModel(
        roomId: roomId,
        roomName: roomName,
        ownerId: currentUser.userId,
        memberIds: memberIds,
      );

      await FirebaseFirestore.instance
          .collection(kRoomsCollection)
          .doc(roomId)
          .set(room.toMap());

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating channel: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).value;
    final isCreator = currentUser?.username == 'fayaspss';

    return GradientScaffold(
      appBar: AppBar(
        title: Text('New Channel', style: AppTextStyles.heading3),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Room Name Input
              const SectionHeader(title: 'Channel Name'),
              GlassTextField(
                controller: _roomNameController,
                hintText: 'e.g. Design Team Sync',
                autofocus: true,
                prefixIcon: const Icon(Icons.tag_rounded, color: AppColors.accentSoft, size: 20),
              ),

              const SizedBox(height: 32),

              if (isCreator) ...[
                // Invite Users
                const SectionHeader(title: 'Add Members'),
                GlassTextField(
                  controller: _searchController,
                  onChanged: _searchUsers,
                  hintText: 'Search by username...',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.accentSoft, size: 20),
                ),

                const SizedBox(height: 16),

                // Selected users chips
                if (_invitedUsers.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _invitedUsers.map((user) {
                      return Chip(
                        backgroundColor: AppColors.accent.withOpacity(0.15),
                        label: Text(user['username']!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.accent)),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16, color: AppColors.accent),
                        onDeleted: () => _toggleInvite(user),
                        side: BorderSide(color: AppColors.accent.withOpacity(0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      );
                    }).toList(),
                  ),

                if (_invitedUsers.isNotEmpty) const SizedBox(height: 16),

                // Search Results
                Expanded(
                  child: _isSearching
                      ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final user = _searchResults[index];
                            final isInvited = _invitedUsers.any((u) => u['userId'] == user['userId']);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: GlassPanel(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                borderRadius: 16,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppColors.accent.withOpacity(0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        user['username']![0].toUpperCase(),
                                        style: AppTextStyles.heading3.copyWith(color: AppColors.accentSoft),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(user['username']!, style: AppTextStyles.bodyMedium),
                                    ),
                                    GlassButton(
                                      label: isInvited ? 'Remove' : 'Add',
                                      color: isInvited ? AppColors.danger : AppColors.accent,
                                      filled: !isInvited,
                                      onTap: () => _toggleInvite(user),
                                      borderRadius: 20,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ], // End of isCreator block

              if (!isCreator) const Spacer(),

              // Create Button
              SizedBox(
                width: double.infinity,
                child: GlassButton(
                  label: 'Create Channel',
                  onTap: _isCreating ? null : _createRoom,
                  isLoading: _isCreating,
                  filled: true,
                  borderRadius: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
