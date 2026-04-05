import 'package:flutter/material.dart';

import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_dissolved_badge.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_member_row.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

/// Pure UI screen for group info.
///
/// Shows group name, type, description, member list, and action buttons.
class GroupInfoScreen extends StatelessWidget {
  final GroupModel group;
  final List<GroupMember> members;
  final bool isAdmin;
  final String? ownPeerId;
  final bool isMuted;
  final bool isUpdatingMute;
  final VoidCallback onBack;
  final VoidCallback onLeave;
  final ValueChanged<bool>? onMuteChanged;
  final VoidCallback? onEditDetails;
  final VoidCallback? onDissolve;
  final ValueChanged<GroupMember>? onRemoveMember;
  final ValueChanged<GroupMember>? onToggleAdminRole;
  final VoidCallback? onAddMember;

  const GroupInfoScreen({
    super.key,
    required this.group,
    required this.members,
    required this.isAdmin,
    this.ownPeerId,
    this.isMuted = false,
    this.isUpdatingMute = false,
    required this.onBack,
    required this.onLeave,
    this.onMuteChanged,
    this.onEditDetails,
    this.onDissolve,
    this.onRemoveMember,
    this.onToggleAdminRole,
    this.onAddMember,
  });

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(context),
              // Body
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    const SizedBox(height: 24),
                    // Group info section
                    _buildGroupInfo(),
                    const SizedBox(height: 24),
                    // Members section
                    _buildMembersSection(),
                    const SizedBox(height: 32),
                    if (!group.isDissolved &&
                        isAdmin &&
                        onDissolve != null) ...[
                      _buildDissolveButton(),
                      const SizedBox(height: 12),
                    ],
                    if (!group.isDissolved) ...[
                      _buildLeaveButton(),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: Colors.white,
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          const Text(
            'Group Info',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + type badge
          Center(
            child: GroupAvatar(
              groupId: group.id,
              name: group.name,
              avatarPath: group.avatarPath,
              size: 88,
              borderRadius: const BorderRadius.all(Radius.circular(28)),
              cacheBustKey: group.lastMetadataEventAt?.toIso8601String(),
            ),
          ),
          if (!group.isDissolved && isAdmin && onEditDetails != null) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                key: const ValueKey('group-edit-details-button'),
                onPressed: onEditDetails,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit Details'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF64B5F6),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GroupTypeBadge(type: group.type),
              if (group.isDissolved) ...[
                const SizedBox(width: 8),
                const GroupDissolvedBadge(),
              ],
            ],
          ),
          if (group.description != null && group.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              group.description!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${members.length} member${members.length == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.35),
            ),
          ),
          if (group.isDissolved) ...[
            const SizedBox(height: 20),
            _buildDissolvedStatusCard(),
          ],
          const SizedBox(height: 20),
          _buildMutePreferenceCard(),
        ],
      ),
    );
  }

  Widget _buildDissolvedStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x14FF8A80),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FF8A80), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0x1FFF8A80),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.block_outlined, color: Color(0xFFFFB3AD)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Group dissolved',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This conversation is now read-only. Previous messages stay available for reference.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.62),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMutePreferenceCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isMuted
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_active_outlined,
              color: isMuted ? const Color(0xFFFFC857) : Colors.white70,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mute Notifications',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isMuted
                      ? 'New messages still arrive, but this group stays quiet.'
                      : 'Get notified when new messages arrive in this group.',
                  key: const ValueKey('group-mute-subtitle'),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.58),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            key: const ValueKey('group-mute-switch'),
            value: isMuted,
            onChanged: isUpdatingMute ? null : onMuteChanged,
            activeColor: const Color(0xFFFFC857),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Members',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.5),
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (!group.isDissolved && isAdmin && onAddMember != null)
          _buildAddMemberButton(),
        ...members.map((member) {
          final isSelf = ownPeerId != null && member.peerId == ownPeerId;
          return GroupMemberRow(
            member: member,
            isAdmin: isAdmin,
            isSelf: isSelf,
            onToggleAdminRole:
                !group.isDissolved &&
                    isAdmin &&
                    !isSelf &&
                    onToggleAdminRole != null
                ? () => onToggleAdminRole!(member)
                : null,
            onRemove:
                !group.isDissolved &&
                    isAdmin &&
                    !isSelf &&
                    onRemoveMember != null
                ? () => onRemoveMember!(member)
                : null,
          );
        }),
      ],
    );
  }

  Widget _buildAddMemberButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: onAddMember,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF64B5F6).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF64B5F6).withOpacity(0.15),
              width: 0.5,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_add_outlined,
                size: 20,
                color: Color(0xFF64B5F6),
              ),
              SizedBox(width: 8),
              Text(
                'Add Member',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64B5F6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaveButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        key: const ValueKey('group-leave-button'),
        onTap: onLeave,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withOpacity(0.2), width: 0.5),
          ),
          child: const Text(
            'Leave Group',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDissolveButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        key: const ValueKey('group-dissolve-button'),
        onTap: onDissolve,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0x14FF8A80),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x33FF8A80), width: 0.5),
          ),
          child: const Text(
            'Dissolve Group',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFFB3AD),
            ),
          ),
        ),
      ),
    );
  }
}
