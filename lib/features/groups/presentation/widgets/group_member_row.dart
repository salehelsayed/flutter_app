import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_member_identity_safety.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// Shows a member's name, role badge, and optional action buttons.
class GroupMemberRow extends StatelessWidget {
  final GroupMember member;
  final GroupMemberIdentitySafety? identitySafety;
  final bool isAdmin;
  final bool isSelf;
  final VoidCallback? onToggleAdminRole;
  final VoidCallback? onRemove;

  const GroupMemberRow({
    super.key,
    required this.member,
    this.identitySafety,
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
                if (identitySafety?.identityChanged == true) ...[
                  const SizedBox(height: 6),
                  _IdentityChangedWarning(
                    peerId: member.peerId,
                    safety: identitySafety!,
                  ),
                ],
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

class _IdentityChangedWarning extends StatelessWidget {
  final String peerId;
  final GroupMemberIdentitySafety safety;

  const _IdentityChangedWarning({required this.peerId, required this.safety});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final warningColor = readableColors.isLightSurface
        ? const Color(0xFF9A5300)
        : const Color(0xFFFFC857);

    return Container(
      key: ValueKey('group-member-identity-warning-$peerId'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: warningColor.withOpacity(
          readableColors.isLightSurface ? 0.08 : 0.14,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: warningColor.withOpacity(
            readableColors.isLightSurface ? 0.24 : 0.26,
          ),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: warningColor, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Identity changed',
                  style: TextStyle(
                    color: warningColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _SafetyNumberLine(
            label: 'Current safety',
            value: safety.currentSafetyNumber,
          ),
          _SafetyNumberLine(
            label: 'Saved safety',
            value: safety.savedSafetyNumber,
          ),
        ],
      ),
    );
  }
}

class _SafetyNumberLine extends StatelessWidget {
  final String label;
  final String value;

  const _SafetyNumberLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Text(
      '$label $value',
      style: TextStyle(
        color: readableColors.textSecondary,
        fontSize: 11,
        height: 1.25,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

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
