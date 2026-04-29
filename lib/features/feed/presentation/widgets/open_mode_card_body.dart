import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/widgets/inline_reply_input.dart';
import 'package:flutter_app/features/feed/presentation/widgets/quote_preview_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
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
  final bool canWrite;
  final String initialText;
  final bool shouldRequestFocus;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<bool>? onInputFocusChanged;
  final bool isEditingMessage;
  final VoidCallback? onCancelEdit;
  final String? activeQuoteText;
  final VoidCallback? onClearQuote;
  final VoidCallback? onAttach;
  final Map<String, List<MessageReaction>> reactions;
  final ValueListenable<List<MessageReaction>>? Function(String messageId)?
  reactionListenableForMessage;
  final String? ownPeerId;
  final void Function(ThreadMessage message, BuildContext bubbleContext)?
  onMessageLongPress;
  final void Function(String messageId, String emoji)? onReactionTap;

  const OpenModeCardBody({
    super.key,
    required this.thread,
    this.onViewEarlier,
    this.onCollapse,
    this.onQuoteReply,
    this.onSend,
    this.sendEnabled = true,
    this.canWrite = true,
    this.initialText = '',
    this.shouldRequestFocus = false,
    this.onDraftChanged,
    this.onInputFocusChanged,
    this.isEditingMessage = false,
    this.onCancelEdit,
    this.activeQuoteText,
    this.onClearQuote,
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
        // Header matches collapsed-card behavior: avatar opens the full
        // conversation, while the name/timestamp area collapses the unread card.
        GestureDetector(
          onTap: onCollapse,
          behavior: HitTestBehavior.opaque,
          child: _buildHeader(context),
        ),
        // Scrollable unread messages
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ScrollableMessagePreview(
            messages: thread.unreadMessages,
            quoteLookupMessages: thread.messages,
            contactPeerId: thread.displayId,
            contactUsername: thread.displayName,
            hasEarlierHistory: true,
            onViewEarlier: onViewEarlier,
            onCollapse: onCollapse,
            onQuoteReply: canWrite ? onQuoteReply : null,
            reactions: reactions,
            reactionListenableForMessage: reactionListenableForMessage,
            ownPeerId: ownPeerId,
            onMessageLongPress: onMessageLongPress,
            onReactionTap: onReactionTap,
          ),
        ),
        // Footer with reply input
        _buildFooter(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final displayNameDirection = detectTextDirection(thread.displayName);
    final groupThread = thread.isGroup ? thread as GroupThreadFeedItem : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          if (thread.isGroup)
            GestureDetector(
              onTap: onViewEarlier,
              child: GroupAvatar(
                groupId: groupThread!.groupId,
                name: groupThread.groupName,
                avatarPath: groupThread.avatarPath,
                cacheBustKey: groupThread.avatarCacheBustKey,
                size: 42,
                borderRadius: BorderRadius.circular(21),
              ),
            )
          else
            GestureDetector(
              onTap: onViewEarlier,
              child: UserAvatar(peerId: thread.displayId, size: 42),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread.displayName,
                  textDirection: displayNameDirection,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: readableColors.isLightSurface
                        ? readableColors.textPrimary
                        : const Color.fromRGBO(255, 255, 255, 1.0),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  thread.latestMessage.time,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: readableColors.isLightSurface
                        ? readableColors.textMuted
                        : const Color.fromRGBO(255, 255, 255, 0.55),
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

  Widget _buildFooter(BuildContext context) {
    if (!canWrite) {
      return _buildReadOnlyBanner(context);
    }
    final readableColors = context.backgroundReadableColors;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: readableColors.isLightSurface
                ? readableColors.divider
                : const Color.fromRGBO(255, 255, 255, 0.08),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEditingMessage && onCancelEdit != null)
            _FeedEditModeBanner(onCancel: onCancelEdit!),
          if (activeQuoteText != null)
            QuotePreviewBar(text: activeQuoteText!, onDismiss: onClearQuote),
          InlineReplyInput(
            hintText: AppLocalizations.of(context)!.conversation_reply,
            onSend: (text) => onSend?.call(text),
            enabled: sendEnabled,
            initialText: initialText,
            shouldRequestFocus: shouldRequestFocus,
            onDraftChanged: onDraftChanged,
            onFocusChanged: onInputFocusChanged,
            onAttach: onAttach,
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyBanner(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final groupThread = thread is GroupThreadFeedItem
        ? thread as GroupThreadFeedItem
        : null;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: readableColors.isLightSurface
                ? readableColors.divider
                : const Color.fromRGBO(255, 255, 255, 0.08),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Text(
        groupThread?.readOnlyBannerText ??
            'Only admins can send messages in this group',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: readableColors.isLightSurface
              ? readableColors.textMuted
              : const Color.fromRGBO(255, 255, 255, 0.45),
        ),
      ),
    );
  }
}

class _FeedEditModeBanner extends StatelessWidget {
  final VoidCallback onCancel;

  const _FeedEditModeBanner({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;
    final isLightSurface = readableColors.isLightSurface;
    final textColor = isLightSurface
        ? const Color(0xFF157A39)
        : const Color.fromRGBO(255, 255, 255, 0.86);

    return Container(
      key: const ValueKey('feed-edit-mode-banner'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(29, 185, 84, 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color.fromRGBO(29, 185, 84, 0.22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.conversation_editing_message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('feed-cancel-edit-action'),
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: isLightSurface
                  ? readableColors.textSecondary
                  : const Color.fromRGBO(255, 255, 255, 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l10n.conversation_cancel_edit),
          ),
        ],
      ),
    );
  }
}
