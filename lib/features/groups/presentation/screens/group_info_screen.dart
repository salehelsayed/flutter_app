import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_dissolved_badge.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_member_row.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

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
  final VoidCallback? onDeleteLocally;
  final ValueChanged<GroupMember>? onRemoveMember;
  final ValueChanged<GroupMember>? onToggleAdminRole;
  final VoidCallback? onAddMember;
  final BackgroundPreference backgroundPreference;

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
    this.onDeleteLocally,
    this.onRemoveMember,
    this.onToggleAdminRole,
    this.onAddMember,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      preference: backgroundPreference,
      child: Builder(
        builder: (context) {
          return Scaffold(
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
                        _buildGroupInfo(context),
                        const SizedBox(height: 24),
                        // Members section
                        _buildMembersSection(context),
                        const SizedBox(height: 32),
                        if (!group.isDissolved &&
                            isAdmin &&
                            onDissolve != null) ...[
                          _buildDissolveButton(context),
                          const SizedBox(height: 12),
                        ],
                        if (group.isDissolved && onDeleteLocally != null) ...[
                          _buildDeleteLocallyCard(context),
                          const SizedBox(height: 24),
                        ],
                        if (!group.isDissolved) ...[
                          _buildLeaveButton(context),
                          const SizedBox(height: 24),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: readableColors.iconPrimary,
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Text(
            'Group Info',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: readableColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupInfo(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final actionBlue = _blueAccent(readableColors);

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
                style: TextButton.styleFrom(foregroundColor: actionBlue),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: readableColors.textPrimary,
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
                color: readableColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${members.length} member${members.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, color: readableColors.textMuted),
          ),
          if (group.isDissolved) ...[
            const SizedBox(height: 20),
            _buildDissolvedStatusCard(context),
          ],
          const SizedBox(height: 20),
          _buildMutePreferenceCard(context),
        ],
      ),
    );
  }

  Widget _buildDissolvedStatusCard(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final danger = _dangerColor(readableColors);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: danger.withOpacity(readableColors.isLightSurface ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: danger.withOpacity(
            readableColors.isLightSurface ? 0.28 : 0.24,
          ),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: danger.withOpacity(
                readableColors.isLightSurface ? 0.10 : 0.18,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.block_outlined, color: danger),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Group dissolved',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: readableColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This conversation is now read-only. Previous messages stay available for reference.',
                  style: TextStyle(
                    fontSize: 13,
                    color: readableColors.textSecondary,
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

  Widget _buildMutePreferenceCard(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final muteAccent = _amberAccent(readableColors);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: readableColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: readableColors.divider, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: readableColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isMuted
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_active_outlined,
              color: isMuted ? muteAccent : readableColors.iconSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mute Notifications',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: readableColors.textPrimary,
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
                    color: readableColors.textSecondary,
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
            activeColor: muteAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildMembersSection(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

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
              color: readableColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (!group.isDissolved && isAdmin && onAddMember != null)
          _buildAddMemberButton(context),
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

  Widget _buildAddMemberButton(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final actionBlue = _blueAccent(readableColors);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: onAddMember,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: actionBlue.withOpacity(
              readableColors.isLightSurface ? 0.08 : 0.10,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: actionBlue.withOpacity(
                readableColors.isLightSurface ? 0.20 : 0.18,
              ),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_outlined, size: 20, color: actionBlue),
              const SizedBox(width: 8),
              Text(
                'Add Member',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: actionBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaveButton(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final danger = _dangerColor(readableColors);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        key: const ValueKey('group-leave-button'),
        onTap: onLeave,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: danger.withOpacity(
              readableColors.isLightSurface ? 0.08 : 0.10,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: danger.withOpacity(
                readableColors.isLightSurface ? 0.24 : 0.20,
              ),
              width: 0.5,
            ),
          ),
          child: Text(
            'Leave Group',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: danger,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDissolveButton(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final danger = _dangerColor(readableColors);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        key: const ValueKey('group-dissolve-button'),
        onTap: onDissolve,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: danger.withOpacity(
              readableColors.isLightSurface ? 0.08 : 0.12,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: danger.withOpacity(
                readableColors.isLightSurface ? 0.28 : 0.24,
              ),
              width: 0.5,
            ),
          ),
          child: Text(
            'Dissolve Group',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: danger,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteLocallyCard(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final danger = _dangerColor(readableColors);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: readableColors.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: readableColors.divider, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete from this device',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: readableColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Keep this dissolved history as long as you want, or remove it from this device only. This will not affect anyone else.',
              style: TextStyle(
                fontSize: 13,
                color: readableColors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              key: const ValueKey('group-delete-local-button'),
              onTap: onDeleteLocally,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: danger.withOpacity(
                    readableColors.isLightSurface ? 0.08 : 0.10,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: danger.withOpacity(
                      readableColors.isLightSurface ? 0.24 : 0.20,
                    ),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  'Delete Group Locally',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: danger,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _blueAccent(BackgroundReadableColors readableColors) {
    return readableColors.isLightSurface
        ? const Color(0xFF0F5F9C)
        : const Color(0xFF64B5F6);
  }

  Color _amberAccent(BackgroundReadableColors readableColors) {
    return readableColors.isLightSurface
        ? const Color(0xFF8A4A00)
        : const Color(0xFFFFC857);
  }

  Color _dangerColor(BackgroundReadableColors readableColors) {
    return readableColors.isLightSurface
        ? const Color(0xFF9D1C12)
        : const Color(0xFFFFB3AD);
  }
}
