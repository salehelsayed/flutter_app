import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/inline_reply_input.dart';
import 'package:flutter_app/features/feed/presentation/widgets/quote_preview_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/replied_indicator.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

/// Body of a feed card in collapsed mode (replied / read / session-reply).
///
/// Shows friend header, single message preview line, optional reply indicator,
/// and "Continue..." inline input. Tappable to expand or navigate.
class CollapsedModeCardBody extends StatelessWidget {
  final CardThreadFeedItem thread;
  final SessionReply? sessionReply;
  final bool isExpanded;
  final VoidCallback? onTapExpand;
  final VoidCallback? onCollapse;
  final VoidCallback? onViewFullConversation;
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

  bool get _isReplied =>
      sessionReply != null ||
      thread.conversationState == ConversationState.replied;

  /// True when expanded state should show ScrollableMessagePreview
  /// (not during session reply collapse).
  bool get _showExpandedMessages => isExpanded && sessionReply == null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header is always tappable to toggle expand/collapse
        GestureDetector(
          onTap: onTapExpand,
          behavior: HitTestBehavior.opaque,
          child: _buildHeader(context),
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
                      _buildPreviewContent(context),
                      _buildExpandHint(context),
                    ],
                  ),
                ),
        ),
        // Footer with input — not wrapped in the tap target
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
          GestureDetector(
            onTap: onViewFullConversation,
            child: thread.isGroup
                ? GroupAvatar(
                    groupId: groupThread!.groupId,
                    name: groupThread.groupName,
                    avatarPath: groupThread.avatarPath,
                    cacheBustKey: groupThread.avatarCacheBustKey,
                    size: 42,
                    borderRadius: BorderRadius.circular(21),
                  )
                : UserAvatar(peerId: thread.displayId, size: 42),
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
                Row(
                  children: [
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
          if (_isReplied) _buildRepliedCheckmark(context),
        ],
      ),
    );
  }

  Widget _buildRepliedCheckmark(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final accentColor = readableColors.isLightSurface
        ? const Color(0xFF0F8F87)
        : FeedColors.accentTeal;

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accentColor.withValues(alpha: 0.15),
      ),
      child: Icon(
        Icons.check_rounded,
        size: 14,
        color: accentColor.withValues(
          alpha: readableColors.isLightSurface ? 1 : 0.70,
        ),
      ),
    );
  }

  Widget _buildPreviewContent(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final isLightSurface = readableColors.isLightSurface;
    final accentColor = isLightSurface
        ? const Color(0xFF0F8F87)
        : FeedColors.accentTeal;
    final ThreadMessage previewMsg;
    final String? displayText;

    if (sessionReply != null) {
      // Show the session reply text
      displayText = sessionReply!.text;
      previewMsg = thread.latestMessage; // for label logic
    } else {
      previewMsg = thread.collapsedPreviewMessage;
      displayText = _previewText(context, previewMsg);
    }

    final isSent = sessionReply != null || !previewMsg.isIncoming;
    final String label;
    if (isSent) {
      label = AppLocalizations.of(context)!.feed_you;
    } else if (thread.isGroup) {
      label = previewMsg.senderUsername ?? thread.displayName;
    } else {
      label = thread.displayName;
    }
    final labelColor = isSent
        ? accentColor
        : (isLightSurface ? readableColors.textPrimary : Colors.white);
    final previewTextDirection = detectTextDirection(displayText ?? '');
    final showEditedIndicator =
        sessionReply == null && previewMsg.isEdited && !previewMsg.isDeleted;
    final l10n = AppLocalizations.of(context)!;

    // Find a downloadable thumbnail from media attachments
    final hasMedia =
        sessionReply == null &&
        !previewMsg.isDeleted &&
        previewMsg.media.isNotEmpty;
    final thumbAttachment = hasMedia
        ? _firstThumbnailAttachment(previewMsg.media)
        : null;
    final showThumb =
        thumbAttachment != null &&
        thumbAttachment.downloadStatus == 'done' &&
        thumbAttachment.localPath != null &&
        (!thread.isGroup ||
            GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(
              thumbAttachment,
            ));
    final thumbPath = thumbAttachment?.localPath;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
          if (showThumb) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: MediaThumbnailImage(
                mediaPath: thumbPath!,
                mediaType: thumbAttachment.mediaType,
                fit: BoxFit.cover,
                cacheWidth: 40,
                placeholder: Container(
                  width: 20,
                  height: 20,
                  color: isLightSurface
                      ? readableColors.surfaceSubtle
                      : const Color.fromRGBO(255, 255, 255, 0.08),
                ),
                error: Container(
                  width: 20,
                  height: 20,
                  color: isLightSurface
                      ? readableColors.surfaceSubtle
                      : const Color.fromRGBO(255, 255, 255, 0.08),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ] else if (hasMedia) ...[
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                mediaPreviewIcon(previewMsg.media),
                size: 14,
                color: isLightSurface
                    ? readableColors.iconMuted
                    : const Color.fromRGBO(255, 255, 255, 0.55),
              ),
            ),
          ],
          Expanded(
            child: Text(
              displayText ?? '',
              textDirection: previewTextDirection,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isLightSurface
                    ? readableColors.textSecondary
                    : Colors.white,
              ),
            ),
          ),
          if (showEditedIndicator) ...[
            const SizedBox(width: 6),
            Text(
              l10n.conversation_edited_indicator,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: isLightSurface
                    ? readableColors.textMuted
                    : const Color.fromRGBO(255, 255, 255, 0.45),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedContent() {
    return ScrollableMessagePreview(
      messages: thread.recentInteractionMessages,
      quoteLookupMessages: thread.messages,
      contactPeerId: thread.displayId,
      contactUsername: thread.displayName,
      hasEarlierHistory: thread.hasEarlierInteractionHistory,
      onViewEarlier: onViewFullConversation,
      onCollapse: onCollapse,
      onQuoteReply: canWrite ? onQuoteReply : null,
      reactions: reactions,
      reactionListenableForMessage: reactionListenableForMessage,
      ownPeerId: ownPeerId,
      onMessageLongPress: onMessageLongPress,
      onReactionTap: onReactionTap,
      requireVerifiedContentHash: thread.isGroup,
    );
  }

  Widget _buildExpandHint(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final hintColor = readableColors.isLightSurface
        ? readableColors.textMuted
        : FeedColors.viewEarlierText;

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: hintColor),
            const SizedBox(width: 2),
            Text(
              AppLocalizations.of(context)!.feed_tap_expand,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns the first image/video attachment suitable for a thumbnail, or null.
  MediaAttachment? _firstThumbnailAttachment(List<MediaAttachment> media) {
    for (final a in media) {
      if (a.mediaType == 'image' || a.mediaType == 'video') return a;
    }
    return null;
  }

  String? _previewText(BuildContext context, ThreadMessage msg) {
    if (msg.isDeleted) {
      return AppLocalizations.of(context)!.conversation_message_deleted;
    }
    if (msg.text.isNotEmpty) return msg.text;
    if (msg.media.isNotEmpty) return mediaPreviewText(msg.media);
    return null;
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
            hintText: AppLocalizations.of(context)!.conversation_continue,
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
    final accentColor = isLightSurface
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
                color: accentColor,
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
