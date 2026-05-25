import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/presentation/group_backlog_retention_notice.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_card.dart';
import 'package:flutter_app/features/groups/presentation/widgets/pending_group_invite_card.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

/// Pure UI screen displaying a list of groups.
///
/// No business logic -- all data passed via props.
/// The ExpandableFab has been moved to OrbitScreen (Phase 1).
class GroupListScreen extends StatelessWidget {
  final List<GroupModel> groups;
  final Map<String, GroupMessage?> latestMessages;
  final Map<String, int> unreadCounts;
  final List<PendingGroupInvite> pendingInvites;
  final Set<String> processingInviteIds;
  final bool isLoading;
  final String? loadErrorMessage;
  final VoidCallback? onRetryLoad;
  final ValueChanged<GroupModel> onGroupTap;
  final ValueChanged<PendingGroupInvite>? onAcceptPendingInvite;
  final ValueChanged<PendingGroupInvite>? onDeclinePendingInvite;
  final VoidCallback onBack;
  final BackgroundPreference backgroundPreference;

  const GroupListScreen({
    super.key,
    required this.groups,
    this.latestMessages = const {},
    this.unreadCounts = const {},
    this.pendingInvites = const [],
    this.processingInviteIds = const <String>{},
    this.isLoading = false,
    this.loadErrorMessage,
    this.onRetryLoad,
    required this.onGroupTap,
    this.onAcceptPendingInvite,
    this.onDeclinePendingInvite,
    required this.onBack,
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
                  _buildHeader(context),
                  Expanded(
                    child: groups.isNotEmpty || pendingInvites.isNotEmpty
                        ? _buildContent(context)
                        : isLoading
                        ? _buildLoadingState(context)
                        : loadErrorMessage != null
                        ? _buildLoadErrorState(context)
                        : _buildEmptyState(context),
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
            'Groups',
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

  Widget _buildEmptyState(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_outlined, size: 64, color: readableColors.iconMuted),
          const SizedBox(height: 16),
          Text(
            'No groups yet',
            style: TextStyle(fontSize: 16, color: readableColors.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a group to get started',
            style: TextStyle(
              fontSize: 13,
              color: readableColors.disabledForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadErrorState(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: readableColors.iconMuted,
            ),
            const SizedBox(height: 16),
            Text(
              loadErrorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: readableColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: readableColors.disabledForeground,
              ),
            ),
            if (onRetryLoad != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRetryLoad,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (pendingInvites.isNotEmpty) ...[
          _buildSectionLabel(context, 'Pending Invites'),
          const SizedBox(height: 12),
          ...pendingInvites.map(
            (invite) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PendingGroupInviteCard(
                invite: invite,
                isProcessing: processingInviteIds.contains(invite.groupId),
                onAccept: onAcceptPendingInvite != null
                    ? () => onAcceptPendingInvite!(invite)
                    : null,
                onDecline: onDeclinePendingInvite != null
                    ? () => onDeclinePendingInvite!(invite)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (groups.isNotEmpty) ...[
          if (pendingInvites.isNotEmpty) ...[
            _buildSectionLabel(context, 'Joined Groups'),
            const SizedBox(height: 12),
          ],
          ...groups.map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildGroupCard(group),
            ),
          ),
        ] else if (pendingInvites.isNotEmpty) ...[
          _buildNoJoinedGroupsCard(context),
        ],
      ],
    );
  }

  Widget _buildGroupCard(GroupModel group) {
    final lastMsg = latestMessages[group.id];
    final unread = unreadCounts[group.id] ?? 0;
    final retentionNotice = groupBacklogRetentionNoticeFor(group);

    return GroupCard(
      group: group,
      statusText: retentionNotice?.listSummary,
      lastMessageSender: lastMsg != null
          ? lastMsg.senderUsername ?? 'Unknown'
          : null,
      lastMessageBody: lastMsg != null ? lastMsg.text : null,
      lastMessageTime: lastMsg != null ? _formatTime(lastMsg.timestamp) : null,
      unreadCount: unread,
      onTap: () => onGroupTap(group),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String label) {
    final readableColors = context.backgroundReadableColors;

    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: readableColors.textMuted,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildNoJoinedGroupsCard(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: readableColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: readableColors.divider),
      ),
      child: Text(
        'No joined groups yet. Accept an invite to add it here.',
        style: TextStyle(
          fontSize: 13,
          color: readableColors.textSecondary,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: readableColors.iconMuted,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _GroupLoadingRow(index: 0),
        const SizedBox(height: 12),
        const _GroupLoadingRow(index: 1),
        const SizedBox(height: 12),
        const _GroupLoadingRow(index: 2),
      ],
    );
  }

  String _formatTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    final hour = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}

class _GroupLoadingRow extends StatelessWidget {
  final int index;

  const _GroupLoadingRow({required this.index});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Container(
      key: ValueKey('group-loading-row-$index'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: readableColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: readableColors.divider),
      ),
      child: Row(
        children: const [
          _GroupLoadingAvatar(),
          SizedBox(width: 14),
          Expanded(child: _GroupLoadingTextBlock()),
        ],
      ),
    );
  }
}

class _GroupLoadingAvatar extends StatelessWidget {
  const _GroupLoadingAvatar();

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: readableColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class _GroupLoadingTextBlock extends StatelessWidget {
  const _GroupLoadingTextBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GroupLoadingBar(widthFactor: 0.42, height: 14),
        SizedBox(height: 10),
        _GroupLoadingBar(widthFactor: 0.68),
        SizedBox(height: 10),
        _GroupLoadingBar(widthFactor: 0.28, height: 10),
      ],
    );
  }
}

class _GroupLoadingBar extends StatelessWidget {
  final double widthFactor;
  final double height;

  const _GroupLoadingBar({required this.widthFactor, this.height = 12});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: readableColors.disabledSurface,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}
