import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_member_identity_safety.dart';
import 'package:flutter_app/features/groups/presentation/group_invite_status_presentation.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Shows a member's name, role badge, and optional action buttons.
class GroupMemberRow extends StatelessWidget {
  final GroupMember member;
  final GroupMemberIdentitySafety? identitySafety;
  final GroupInviteDeliveryStatus inviteStatus;
  final GroupInviteDeliveryAttempt? inviteAttempt;
  final bool isAdmin;
  final bool isSelf;
  final bool isResendingInvite;
  final VoidCallback? onToggleAdminRole;
  final VoidCallback? onRemove;
  final VoidCallback? onResendInvite;

  const GroupMemberRow({
    super.key,
    required this.member,
    this.identitySafety,
    this.inviteStatus = GroupInviteDeliveryStatus.unknown,
    this.inviteAttempt,
    this.isAdmin = false,
    this.isSelf = false,
    this.isResendingInvite = false,
    this.onToggleAdminRole,
    this.onRemove,
    this.onResendInvite,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

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
                      ? l10n.feed_you
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
                _RoleBadge(role: member.role, l10n: l10n),
                if (!isSelf) ...[
                  const SizedBox(height: 6),
                  _InviteStatusBadge(
                    peerId: member.peerId,
                    status: inviteStatus,
                    lastError: inviteAttempt?.lastError,
                    l10n: l10n,
                  ),
                ],
                if (identitySafety?.identityChanged == true) ...[
                  const SizedBox(height: 6),
                  _IdentityChangedWarning(
                    peerId: member.peerId,
                    safety: identitySafety!,
                    l10n: l10n,
                  ),
                ],
              ],
            ),
          ),
          if (isAdmin &&
              !isSelf &&
              (onToggleAdminRole != null ||
                  onRemove != null ||
                  onResendInvite != null))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onResendInvite != null)
                  TextButton(
                    key: ValueKey(
                      'group-member-resend-invite-${member.peerId}',
                    ),
                    onPressed: isResendingInvite ? null : onResendInvite,
                    child: Text(
                      isResendingInvite
                          ? l10n.group_member_sending
                          : l10n.group_member_resend,
                    ),
                  ),
                if (onToggleAdminRole != null)
                  PopupMenuButton<_GroupMemberAction>(
                    key: ValueKey('group-member-actions-${member.peerId}'),
                    tooltip: l10n.group_member_manage_role,
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
                              ? l10n.group_info_remove_admin_action
                              : l10n.group_info_make_admin_action,
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

class _InviteStatusBadge extends StatelessWidget {
  final String peerId;
  final GroupInviteDeliveryStatus status;
  final String? lastError;
  final AppLocalizations l10n;

  const _InviteStatusBadge({
    required this.peerId,
    required this.status,
    this.lastError,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final color = _color(readableColors);
    final detail = groupInviteStatusDetail(
      l10n: l10n,
      status: status,
      lastError: lastError,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: ValueKey('group-member-invite-status-$peerId'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(
              readableColors.isLightSurface ? 0.08 : 0.14,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color.withOpacity(
                readableColors.isLightSurface ? 0.22 : 0.26,
              ),
              width: 0.5,
            ),
          ),
          child: Text(
            groupInviteStatusLabel(l10n, status),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(
            detail,
            key: ValueKey('group-member-invite-status-detail-$peerId'),
            style: TextStyle(
              color: readableColors.textSecondary,
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }

  Color _color(BackgroundReadableColors readableColors) {
    switch (status) {
      case GroupInviteDeliveryStatus.sent:
      case GroupInviteDeliveryStatus.joined:
        return readableColors.isLightSurface
            ? const Color(0xFF116A3A)
            : const Color(0xFF7BD88F);
      case GroupInviteDeliveryStatus.queued:
        return readableColors.isLightSurface
            ? const Color(0xFF0F5F9C)
            : const Color(0xFF64B5F6);
      case GroupInviteDeliveryStatus.needsResend:
        return readableColors.isLightSurface
            ? const Color(0xFF8A4A00)
            : const Color(0xFFFFC857);
      case GroupInviteDeliveryStatus.cannotSend:
        return readableColors.isLightSurface
            ? const Color(0xFF9D1C12)
            : const Color(0xFFFFB3AD);
      case GroupInviteDeliveryStatus.unknown:
        return readableColors.textMuted;
    }
  }
}

class _IdentityChangedWarning extends StatelessWidget {
  final String peerId;
  final GroupMemberIdentitySafety safety;
  final AppLocalizations l10n;

  const _IdentityChangedWarning({
    required this.peerId,
    required this.safety,
    required this.l10n,
  });

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
                  l10n.group_identity_changed,
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
            label: l10n.group_current_safety,
            value: safety.currentSafetyNumber,
          ),
          _SafetyNumberLine(
            label: l10n.group_saved_safety,
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
  final AppLocalizations l10n;

  const _RoleBadge({required this.role, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Text(
      _roleLabel(role),
      style: TextStyle(
        fontSize: 11,
        color: _colorForRole(role, readableColors),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  String _roleLabel(MemberRole role) {
    switch (role) {
      case MemberRole.admin:
        return l10n.group_role_admin;
      case MemberRole.writer:
        return l10n.group_role_writer;
      case MemberRole.reader:
        return l10n.group_role_reader;
    }
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
