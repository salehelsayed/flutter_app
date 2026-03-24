import 'package:flutter/material.dart';

import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_card.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

/// Pure UI screen displaying a list of groups.
///
/// No business logic -- all data passed via props.
/// The ExpandableFab has been moved to OrbitScreen (Phase 1).
class GroupListScreen extends StatelessWidget {
  final List<GroupModel> groups;
  final Map<String, GroupMessage?> latestMessages;
  final Map<String, int> unreadCounts;
  final bool isLoading;
  final ValueChanged<GroupModel> onGroupTap;
  final VoidCallback onBack;

  const GroupListScreen({
    super.key,
    required this.groups,
    this.latestMessages = const {},
    this.unreadCounts = const {},
    this.isLoading = false,
    required this.onGroupTap,
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
                child: groups.isNotEmpty
                    ? _buildList()
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

  Widget _buildList() {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final lastMsg = latestMessages[group.id];
        final unread = unreadCounts[group.id] ?? 0;

        return GroupCard(
          group: group,
          lastMessageSender: lastMsg != null
              ? lastMsg.senderUsername ?? 'Unknown'
              : null,
          lastMessageBody: lastMsg != null ? lastMsg.text : null,
          lastMessageTime: lastMsg != null
              ? _formatTime(lastMsg.timestamp)
              : null,
          unreadCount: unread,
          onTap: () => onGroupTap(group),
        );
      },
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
