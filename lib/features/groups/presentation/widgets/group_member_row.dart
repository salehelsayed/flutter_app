import 'package:flutter/material.dart';

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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
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
                    color: const Color(0xFF141A24),
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
                        ),
                      ),
                    ],
                    icon: Icon(
                      Icons.admin_panel_settings_outlined,
                      color: Colors.white.withOpacity(0.5),
                      size: 20,
                    ),
                  ),
                if (onRemove != null)
                  IconButton(
                    key: ValueKey('group-member-remove-${member.peerId}'),
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: Colors.white.withOpacity(0.4),
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
    return Text(
      role.toValue(),
      style: TextStyle(
        fontSize: 11,
        color: _colorForRole(role),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Color _colorForRole(MemberRole role) {
    switch (role) {
      case MemberRole.admin:
        return const Color(0xFFFFB74D);
      case MemberRole.writer:
        return const Color(0xFF64B5F6);
      case MemberRole.reader:
        return Colors.white.withOpacity(0.4);
    }
  }
}
