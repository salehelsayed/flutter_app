import 'package:flutter/material.dart';

import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_card.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

/// Pure UI screen displaying a list of groups.
///
/// No business logic -- all data passed via props.
class GroupListScreen extends StatelessWidget {
  final List<GroupModel> groups;
  final Map<String, GroupMessage?> latestMessages;
  final Map<String, int> unreadCounts;
  final ValueChanged<GroupModel> onGroupTap;
  final ValueChanged<GroupType> onCreateGroup;
  final VoidCallback onBack;

  const GroupListScreen({
    super.key,
    required this.groups,
    this.latestMessages = const {},
    this.unreadCounts = const {},
    required this.onGroupTap,
    required this.onCreateGroup,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: groups.isEmpty ? _buildEmptyState() : _buildList(),
                  ),
                ],
              ),
              ExpandableFab(
                items: [
                  ExpandableFabItem(
                    label: 'New Group',
                    icon: Icons.group_outlined,
                    onTap: () => onCreateGroup(GroupType.chat),
                  ),
                  ExpandableFabItem(
                    label: 'New Announce',
                    icon: Icons.campaign_outlined,
                    onTap: () => onCreateGroup(GroupType.announcement),
                  ),
                  ExpandableFabItem(
                    label: 'New Q&A',
                    icon: Icons.quiz_outlined,
                    onTap: () => onCreateGroup(GroupType.qa),
                  ),
                ],
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
          lastMessagePreview: lastMsg != null
              ? '${lastMsg.senderUsername ?? 'Unknown'}: ${lastMsg.text}'
              : null,
          lastMessageTime: lastMsg != null ? _formatTime(lastMsg.timestamp) : null,
          unreadCount: unread,
          onTap: () => onGroupTap(group),
        );
      },
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
