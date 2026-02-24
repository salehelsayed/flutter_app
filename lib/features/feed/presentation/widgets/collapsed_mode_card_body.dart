import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/inline_reply_input.dart';
import 'package:flutter_app/features/feed/presentation/widgets/replied_indicator.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

/// Body of a feed card in collapsed mode (replied / read / session-reply).
///
/// Shows friend header, single message preview line, optional reply indicator,
/// and "Continue..." inline input. Tappable to expand or navigate.
class CollapsedModeCardBody extends StatelessWidget {
  final ThreadFeedItem thread;
  final SessionReply? sessionReply;
  final VoidCallback? onTapExpand;
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
    this.onTapExpand,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + preview are tappable to expand/navigate
        GestureDetector(
          onTap: onTapExpand,
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              _buildPreviewContent(),
            ],
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
    if (sessionReply != null) {
      return _buildSinglePreviewLine(
        label: 'You',
        labelColor: FeedColors.accentTeal.withValues(alpha: 0.70),
        displayText: sessionReply!.text,
        isMediaOnly: false,
        media: const [],
      );
    }

    final previewMessages = thread.collapsedPreviewMessages;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final msg in previewMessages)
            _buildMessagePreviewRow(msg),
        ],
      ),
    );
  }

  Widget _buildMessagePreviewRow(ThreadMessage msg) {
    final isSent = !msg.isIncoming;
    final label = isSent ? 'You' : thread.contactUsername;
    final labelColor = isSent
        ? FeedColors.accentTeal.withValues(alpha: 0.70)
        : const Color.fromRGBO(255, 255, 255, 0.70);
    final displayText = _previewText(msg);
    final isMediaOnly = msg.text.isEmpty && msg.media.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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
                mediaPreviewIcon(msg.media),
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

  Widget _buildSinglePreviewLine({
    required String label,
    required Color labelColor,
    required String? displayText,
    required bool isMediaOnly,
    required List<MediaAttachment> media,
  }) {
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
                mediaPreviewIcon(media),
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
