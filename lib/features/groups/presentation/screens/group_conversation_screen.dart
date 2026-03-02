import 'package:flutter/material.dart';

import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_compose_area.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

/// Pure UI screen for group conversation.
///
/// Displays header with group name/type, message list using letter cards,
/// and compose area. No business logic -- all data passed via props.
class GroupConversationScreen extends StatelessWidget {
  final GroupModel group;
  final List<GroupMessage> messages;
  final String? ownPeerId;
  final ValueChanged<String> onSend;
  final VoidCallback onBack;
  final VoidCallback? onInfo;
  final bool canWrite;
  final ScrollController? scrollController;

  const GroupConversationScreen({
    super.key,
    required this.group,
    required this.messages,
    this.ownPeerId,
    required this.onSend,
    required this.onBack,
    this.onInfo,
    this.canWrite = true,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
      child: Column(
        children: [
          // Header
          _buildHeader(context),
          // Body
          Expanded(
            child: messages.isEmpty ? _buildEmptyState() : _buildMessageList(),
          ),
          // Compose area
          GroupComposeArea(
            onSend: onSend,
            canWrite: canWrite,
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withOpacity(0.06),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              color: Colors.white,
              onPressed: onBack,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GroupTypeBadge(type: group.type),
                    ],
                  ),
                ],
              ),
            ),
            if (onInfo != null)
              IconButton(
                icon: Icon(
                  Icons.info_outline,
                  color: Colors.white.withOpacity(0.6),
                  size: 22,
                ),
                onPressed: onInfo,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 12),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            canWrite
                ? 'Send a message to start the conversation'
                : 'Waiting for messages',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: scrollController,
      reverse: true,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        // Reversed list: index 0 = newest
        final message = messages[messages.length - 1 - index];
        final isSent = message.senderPeerId == ownPeerId;

        return Padding(
          key: ValueKey('grp-msg-${message.id}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: _GroupLetterCard(
            message: message,
            isSent: isSent,
          ),
        );
      },
    );
  }
}

/// Letter card for group messages.
///
/// Full-width card with left accent for received, right accent for sent.
class _GroupLetterCard extends StatelessWidget {
  final GroupMessage message;
  final bool isSent;

  const _GroupLetterCard({
    required this.message,
    required this.isSent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: isSent
              ? BorderSide.none
              : const BorderSide(
                  color: Color(0xFF64B5F6),
                  width: 3,
                ),
          right: isSent
              ? const BorderSide(
                  color: Color(0xFF81C784),
                  width: 3,
                )
              : BorderSide.none,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sender name + time
          Row(
            children: [
              Text(
                isSent ? 'You' : (message.senderUsername ?? 'Unknown'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSent
                      ? const Color(0xFF81C784)
                      : const Color(0xFF64B5F6),
                ),
              ),
              const Spacer(),
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Message text
          Text(
            message.text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.85),
              height: 1.4,
            ),
          ),
        ],
      ),
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
