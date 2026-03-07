import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/widgets/inline_reply_input.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// Body of a feed card in open mode (unread / active state).
///
/// Shows the friend header, scrollable unread message preview,
/// and an inline reply input with "Reply..." hint.
class OpenModeCardBody extends StatelessWidget {
  final CardThreadFeedItem thread;
  final VoidCallback? onViewEarlier;
  final VoidCallback? onCollapse;
  final ValueChanged<String>? onQuoteReply;
  final ValueChanged<String>? onSend;
  final bool sendEnabled;
  final String initialText;
  final bool shouldRequestFocus;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<bool>? onInputFocusChanged;
  final VoidCallback? onAttach;
  final Map<String, List<MessageReaction>> reactions;
  final ValueListenable<List<MessageReaction>>? Function(String messageId)?
  reactionListenableForMessage;
  final String? ownPeerId;
  final void Function(String messageId)? onMessageLongPress;
  final void Function(String messageId, String emoji)? onReactionTap;

  const OpenModeCardBody({
    super.key,
    required this.thread,
    this.onViewEarlier,
    this.onCollapse,
    this.onQuoteReply,
    this.onSend,
    this.sendEnabled = true,
    this.initialText = '',
    this.shouldRequestFocus = false,
    this.onDraftChanged,
    this.onInputFocusChanged,
    this.onAttach,
    this.reactions = const {},
    this.reactionListenableForMessage,
    this.ownPeerId,
    this.onMessageLongPress,
    this.onReactionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Friend indicator header
        _buildHeader(),
        // Scrollable unread messages
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ScrollableMessagePreview(
            messages: thread.unreadMessages,
            contactPeerId: thread.displayId,
            contactUsername: thread.displayName,
            hasEarlierHistory: true,
            onViewEarlier: onViewEarlier,
            onCollapse: onCollapse,
            onQuoteReply: onQuoteReply,
            reactions: reactions,
            reactionListenableForMessage: reactionListenableForMessage,
            ownPeerId: ownPeerId,
            onMessageLongPress: onMessageLongPress,
            onReactionTap: onReactionTap,
          ),
        ),
        // Footer with reply input
        _buildFooter(),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          if (thread.isGroup)
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: FeedColors.accentPurple.withValues(alpha: 0.15),
              ),
              child: const Icon(
                Icons.group_rounded,
                size: 20,
                color: FeedColors.accentPurple,
              ),
            )
          else
            UserAvatar(peerId: thread.displayId, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color.fromRGBO(255, 255, 255, 1.0),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  thread.latestMessage.time,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Color.fromRGBO(255, 255, 255, 0.55),
                  ),
                ),
              ],
            ),
          ),
          if (thread.unreadCount > 0)
            UnreadCountBadge(count: thread.unreadCount),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.08)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: InlineReplyInput(
        hintText: 'Reply...',
        onSend: (text) => onSend?.call(text),
        enabled: sendEnabled,
        initialText: initialText,
        shouldRequestFocus: shouldRequestFocus,
        onDraftChanged: onDraftChanged,
        onFocusChanged: onInputFocusChanged,
        onAttach: onAttach,
      ),
    );
  }
}
