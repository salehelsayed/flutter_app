import 'package:flutter/material.dart';

import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/presentation/group_backlog_retention_notice.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_card.dart';
import 'package:flutter_app/features/groups/presentation/widgets/pending_group_invite_card.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

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
  final ValueChanged<GroupModel> onGroupTap;
  final ValueChanged<PendingGroupInvite>? onAcceptPendingInvite;
  final ValueChanged<PendingGroupInvite>? onDeclinePendingInvite;
  final VoidCallback onBack;

  const GroupListScreen({
    super.key,
    required this.groups,
    this.latestMessages = const {},
    this.unreadCounts = const {},
    this.pendingInvites = const [],
    this.processingInviteIds = const <String>{},
    this.isLoading = false,
    required this.onGroupTap,
    this.onAcceptPendingInvite,
    this.onDeclinePendingInvite,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: groups.isNotEmpty || pendingInvites.isNotEmpty
                    ? _buildContent()
                    : isLoading
                    ? _buildLoadingState()
                    : _buildEmptyState(),
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
            'Groups',
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_outlined,
            size: 64,
            color: Colors.white.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No groups yet',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a group to get started',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (pendingInvites.isNotEmpty) ...[
          _buildSectionLabel('Pending Invites'),
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
            _buildSectionLabel('Joined Groups'),
            const SizedBox(height: 12),
          ],
          ...groups.map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildGroupCard(group),
            ),
          ),
        ] else if (pendingInvites.isNotEmpty) ...[
          _buildNoJoinedGroupsCard(),
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

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.white.withOpacity(0.5),
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildNoJoinedGroupsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x10FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x16FFFFFF)),
      ),
      child: Text(
        'No joined groups yet. Accept an invite to add it here.',
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withOpacity(0.5),
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: const [
        Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white54,
            ),
          ),
        ),
        SizedBox(height: 20),
        _GroupLoadingRow(index: 0),
        SizedBox(height: 12),
        _GroupLoadingRow(index: 1),
        SizedBox(height: 12),
        _GroupLoadingRow(index: 2),
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
    return Container(
      key: ValueKey('group-loading-row-$index'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1FFFFFFF)),
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
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0x12FFFFFF),
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
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0x12FFFFFF),
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}
