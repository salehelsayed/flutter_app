import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/inline_reply_input.dart';
import 'package:flutter_app/features/feed/presentation/widgets/replied_indicator.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

/// Body of a feed card in collapsed mode (replied / read / session-reply).
///
/// Shows friend header, single message preview line, optional reply indicator,
/// and "Continue..." inline input. Tappable to expand or navigate.
class CollapsedModeCardBody extends StatelessWidget {
  final ThreadFeedItem thread;
  final SessionReply? sessionReply;
  final bool isExpanded;
  final VoidCallback? onTapExpand;
  final VoidCallback? onCollapse;
  final VoidCallback? onViewFullConversation;
  final ValueChanged<String>? onQuoteReply;
  final ValueChanged<String>? onSend;
  final bool sendEnabled;
  final String initialText;
  final bool shouldRequestFocus;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<bool>? onInputFocusChanged;
  final VoidCallback? onAttach;

  const CollapsedModeCardBody({
    super.key,
    required this.thread,
    this.sessionReply,
    this.isExpanded = false,
    this.onTapExpand,
    this.onCollapse,
    this.onViewFullConversation,
    this.onQuoteReply,
    this.onSend,
    this.sendEnabled = true,
    this.initialText = '',
    this.shouldRequestFocus = false,
    this.onDraftChanged,
    this.onInputFocusChanged,
    this.onAttach,
  });

  bool get _isReplied =>
      sessionReply != null ||
      thread.conversationState == ConversationState.replied;

  /// True when expanded state should show ScrollableMessagePreview
  /// (not during session reply collapse).
  bool get _showExpandedMessages =>
      isExpanded && sessionReply == null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header is always tappable to toggle expand/collapse
        GestureDetector(
          onTap: onTapExpand,
          behavior: HitTestBehavior.opaque,
          child: _buildHeader(),
        ),
        // Content area: single-line preview or expanded messages
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _showExpandedMessages
              ? _buildExpandedContent()
              : GestureDetector(
                  onTap: onTapExpand,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    children: [
                      _buildPreviewContent(),
                      _buildExpandHint(),
                    ],
                  ),
                ),
        ),
        // Footer with input — not wrapped in the tap target
        _buildFooter(),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          UserAvatar(peerId: thread.contactPeerId, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread.contactUsername,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color.fromRGBO(255, 255, 255, 1.0),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      thread.latestMessage.time,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Color.fromRGBO(255, 255, 255, 0.55),
                      ),
                    ),
                    if (_isReplied) ...[
                      const SizedBox(width: 8),
                      if (sessionReply != null)
                        RepliedIndicator(repliedAt: sessionReply!.time)
                      else if (thread.lastRepliedAt != null)
                        RepliedIndicator(repliedAt: thread.lastRepliedAt!),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (_isReplied) _buildRepliedCheckmark(),
        ],
      ),
    );
  }

  Widget _buildRepliedCheckmark() {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: FeedColors.accentTeal.withValues(alpha: 0.15),
      ),
      child: Icon(
        Icons.check_rounded,
        size: 14,
        color: FeedColors.accentTeal.withValues(alpha: 0.70),
      ),
    );
  }

  Widget _buildPreviewContent() {
    final ThreadMessage previewMsg;
    final String? displayText;
    final bool isMediaOnly;

    if (sessionReply != null) {
      // Show the session reply text
      displayText = sessionReply!.text;
      previewMsg = thread.latestMessage; // for label logic
      isMediaOnly = false;
    } else {
      previewMsg = thread.collapsedPreviewMessage;
      displayText = _previewText(previewMsg);
      isMediaOnly = previewMsg.text.isEmpty && previewMsg.media.isNotEmpty;
    }

    final isSent = sessionReply != null || !previewMsg.isIncoming;
    final label = isSent ? 'You' : thread.contactUsername;
    final labelColor = isSent
        ? FeedColors.accentTeal.withValues(alpha: 0.70)
        : const Color.fromRGBO(255, 255, 255, 0.70);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
          if (isMediaOnly)
            Padding(
              padding: const EdgeInsets.only(right: 4, top: 2),
              child: Icon(
                mediaPreviewIcon(previewMsg.media),
                size: 14,
                color: const Color.fromRGBO(255, 255, 255, 0.55),
              ),
            ),
          Expanded(
            child: Text(
              displayText ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color.fromRGBO(255, 255, 255, 0.85),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent() {
    return ScrollableMessagePreview(
      messages: thread.recentInteractionMessages,
      contactPeerId: thread.contactPeerId,
      contactUsername: thread.contactUsername,
      hasEarlierHistory: thread.hasEarlierInteractionHistory,
      onViewEarlier: onViewFullConversation,
      onCollapse: onCollapse,
      onQuoteReply: onQuoteReply,
    );
  }

  Widget _buildExpandHint() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'Tap to expand',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: FeedColors.viewEarlierText,
          ),
        ),
      ),
    );
  }

  String? _previewText(ThreadMessage msg) {
    if (msg.text.isNotEmpty) return msg.text;
    if (msg.media.isNotEmpty) return mediaPreviewText(msg.media);
    return null;
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
        hintText: 'Continue...',
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
