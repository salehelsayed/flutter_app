import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// Shows a member's name, role badge, and optional action buttons.
class GroupMemberRow extends StatelessWidget {
  final GroupMember member;
  final bool isAdmin;
  final bool isSelf;
  final VoidCallback? onToggleAdminRole;
  final VoidCallback? onRemove;

  const GroupMemberRow({
    super.key,
    required this.member,
    this.isAdmin = false,
    this.isSelf = false,
    this.onToggleAdminRole,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          UserAvatar(peerId: member.peerId, size: 36, showPhotoFrame: false),
          const SizedBox(width: 12),
          // Name + role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSelf
                      ? 'You'
                      : (member.username ??
                            (member.peerId.length > 12
                                ? '${member.peerId.substring(0, 12)}...'
                                : member.peerId)),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: readableColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                _RoleBadge(role: member.role),
              ],
            ),
          ),
          if (isAdmin &&
              !isSelf &&
              (onToggleAdminRole != null || onRemove != null))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onToggleAdminRole != null)
                  PopupMenuButton<_GroupMemberAction>(
                    key: ValueKey('group-member-actions-${member.peerId}'),
                    tooltip: 'Manage role',
                    color: readableColors.surfaceRaised,
                    onSelected: (action) {
                      if (action == _GroupMemberAction.toggleAdminRole) {
                        onToggleAdminRole?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<_GroupMemberAction>(
                        key: ValueKey(
                          'group-member-toggle-admin-${member.peerId}',
                        ),
                        value: _GroupMemberAction.toggleAdminRole,
                        child: Text(
                          member.role == MemberRole.admin
                              ? 'Remove Admin'
                              : 'Make Admin',
                          style: TextStyle(color: readableColors.textPrimary),
                        ),
                      ),
                    ],
                    icon: Icon(
                      Icons.admin_panel_settings_outlined,
                      color: readableColors.iconMuted,
                      size: 20,
                    ),
                  ),
                if (onRemove != null)
                  IconButton(
                    key: ValueKey('group-member-remove-${member.peerId}'),
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: readableColors.iconMuted,
                      size: 20,
                    ),
                    onPressed: onRemove,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _GroupMemberAction { toggleAdminRole }

class _RoleBadge extends StatelessWidget {
  final MemberRole role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Text(
      role.toValue(),
      style: TextStyle(
        fontSize: 11,
        color: _colorForRole(role, readableColors),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Color _colorForRole(
    MemberRole role,
    BackgroundReadableColors readableColors,
  ) {
    if (readableColors.isLightSurface) {
      switch (role) {
        case MemberRole.admin:
          return const Color(0xFF8A4A00);
        case MemberRole.writer:
          return const Color(0xFF0F5F9C);
        case MemberRole.reader:
          return readableColors.textMuted;
      }
    }

    switch (role) {
      case MemberRole.admin:
        return const Color(0xFFFFB74D);
      case MemberRole.writer:
        return const Color(0xFF64B5F6);
      case MemberRole.reader:
        return readableColors.textMuted;
    }
  }
}
