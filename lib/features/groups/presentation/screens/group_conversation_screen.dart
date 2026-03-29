import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/full_emoji_picker.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_bar.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

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
  final bool isSending;
  final UploadProgressViewState? uploadProgress;
  final VoidCallback? onCancelUpload;
  final bool initialLoadDone;
  final ScrollController? scrollController;
  final Map<String, List<MediaAttachment>> mediaMap;
  final List<File> pendingAttachments;
  final bool isUploading;
  final bool isProcessing;
  final double processingProgress;
  final int processingCurrent;
  final int processingTotal;
  final ValueChanged<int>? onRemoveAttachment;
  final VoidCallback? onAttach;
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;
  final VoidCallback? onRecordCancel;
  final bool isRecording;
  final VoiceRecordingState recordingState;
  final Duration recordingDuration;
  final List<double> amplitudeValues;
  final ValueListenable<ConversationComposerViewState>? composerStateListenable;
  final void Function(String messageId, int index)? onMediaTap;
  final Map<String, List<MessageReaction>> reactions;
  final void Function(String messageId, String emoji)? onReactionSelected;
  final String? initialText;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<String>? onQuoteReply;
  final ValueChanged<String>? onRetryFailedMedia;
  final ValueChanged<String>? onDeleteFailedMedia;
  final String? activeQuoteText;
  final bool isActiveQuoteUnavailable;
  final VoidCallback? onClearQuote;

  const GroupConversationScreen({
    super.key,
    required this.group,
    required this.messages,
    this.ownPeerId,
    required this.onSend,
    required this.onBack,
    this.onInfo,
    this.canWrite = true,
    this.isSending = false,
    this.uploadProgress,
    this.onCancelUpload,
    this.initialLoadDone = false,
    this.scrollController,
    this.mediaMap = const {},
    this.pendingAttachments = const [],
    this.isUploading = false,
    this.isProcessing = false,
    this.processingProgress = 0.0,
    this.processingCurrent = 0,
    this.processingTotal = 0,
    this.onRemoveAttachment,
    this.onAttach,
    this.onRecordStart,
    this.onRecordStop,
    this.onRecordCancel,
    this.isRecording = false,
    this.recordingState = VoiceRecordingState.idle,
    this.recordingDuration = Duration.zero,
    this.amplitudeValues = const [],
    this.composerStateListenable,
    this.onMediaTap,
    this.reactions = const {},
    this.onReactionSelected,
    this.initialText,
    this.onDraftChanged,
    this.onQuoteReply,
    this.onRetryFailedMedia,
    this.onDeleteFailedMedia,
    this.activeQuoteText,
    this.isActiveQuoteUnavailable = false,
    this.onClearQuote,
  });

  ConversationComposerViewState get _legacyComposerState =>
      ConversationComposerViewState(
        pendingAttachments: pendingAttachments,
        isUploading: isUploading,
        isProcessing: isProcessing,
        processingProgress: processingProgress,
        processingCurrent: processingCurrent,
        processingTotal: processingTotal,
        recordingState: recordingState != VoiceRecordingState.idle
            ? recordingState
            : (isRecording
                  ? VoiceRecordingState.recording
                  : VoiceRecordingState.idle),
        recordingDuration: recordingDuration,
        amplitudeValues: amplitudeValues,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: Column(
          children: [
            _buildHeader(context),
            if (uploadProgress != null)
              UploadProgressBanner(
                state: uploadProgress!,
                onCancel: onCancelUpload,
              ),
            Expanded(
              child: messages.isEmpty
                  ? _buildEmptyOrLoadingState()
                  : _buildMessageList(),
            ),
            if (composerStateListenable == null)
              _buildComposerSection(_legacyComposerState)
            else
              ValueListenableBuilder<ConversationComposerViewState>(
                valueListenable: composerStateListenable!,
                builder: (context, composerState, child) =>
                    _buildComposerSection(composerState),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposerSection(ConversationComposerViewState composerState) {
    return Column(
      children: [
        if (composerState.pendingAttachments.isNotEmpty ||
            composerState.isProcessing)
          AttachmentPreviewStrip(
            attachments: composerState.pendingAttachments,
            isUploading: composerState.isUploading,
            isProcessing: composerState.isProcessing,
            processingProgress: composerState.processingProgress,
            processingCurrent: composerState.processingCurrent,
            processingTotal: composerState.processingTotal,
            onRemove: onRemoveAttachment,
          ),
        if (!canWrite)
          _buildReadOnlyBanner()
        else
          ComposeArea(
            onSend: onSend,
            onAttach: onAttach,
            hasAttachments: composerState.pendingAttachments.isNotEmpty,
            isProcessing: composerState.isProcessing,
            isSending: isSending,
            recordingState: composerState.recordingState,
            onRecordStart: onRecordStart,
            onRecordStop: onRecordStop,
            onRecordCancel: onRecordCancel,
            recordingDuration: composerState.recordingDuration,
            amplitudeValues: composerState.amplitudeValues,
            initialText: initialText,
            onDraftChanged: onDraftChanged,
            quotedText: activeQuoteText,
            isQuoteUnavailable: isActiveQuoteUnavailable,
            onClearQuote: onClearQuote,
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        key: const ValueKey('group-header'),
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.06),
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
                  color: Colors.white.withValues(alpha: 0.6),
                  size: 22,
                ),
                onPressed: onInfo,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyOrLoadingState() {
    if (!initialLoadDone) {
      return const _GroupConversationLoadingShell();
    }
    return _buildEmptyState();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Colors.white.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 12),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            canWrite
                ? 'Send a message to start the conversation'
                : 'Waiting for messages',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      key: const ValueKey('group-messages'),
      controller: scrollController,
      reverse: true,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        // Reversed list: index 0 = newest
        final message = messages[messages.length - 1 - index];
        final isSent = message.senderPeerId == ownPeerId;
        final (quotedText, isQuoteUnavailable) = _resolveQuotedText(message);
        final messageMedia = mediaMap[message.id] ?? message.media;
        final showFailedMediaActions =
            canWrite &&
            isSent &&
            message.status == 'failed' &&
            messageMedia.isNotEmpty;

        Widget bubble = Padding(
          key: ValueKey('grp-msg-${message.id}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: Builder(
            builder: (cardContext) => LetterCard(
              senderPeerId: message.senderPeerId,
              senderName: isSent
                  ? 'You'
                  : (message.senderUsername ?? 'Unknown'),
              text: message.text,
              time: _formatTime(message.timestamp),
              isIncoming: !isSent,
              status: isSent ? message.status : null,
              quotedText: quotedText,
              isQuoteUnavailable: isQuoteUnavailable,
              media: messageMedia,
              onMediaTap: onMediaTap != null
                  ? (index) => onMediaTap!(message.id, index)
                  : null,
              reactions: reactions[message.id] ?? const [],
              ownPeerId: ownPeerId,
              onReactionTap: onReactionSelected != null
                  ? (emoji) => onReactionSelected!(message.id, emoji)
                  : null,
              onLongPress: onReactionSelected != null
                  ? () => _showReactionBar(cardContext, message.id)
                  : null,
              onRetryFailedMedia:
                  showFailedMediaActions && onRetryFailedMedia != null
                  ? () => onRetryFailedMedia!(message.id)
                  : null,
              onDeleteFailedMedia:
                  showFailedMediaActions && onDeleteFailedMedia != null
                  ? () => onDeleteFailedMedia!(message.id)
                  : null,
              failedMediaActionKeySuffix: message.id,
            ),
          ),
        );

        if (!isSent && canWrite && onQuoteReply != null) {
          bubble = SwipeToQuoteBubble(
            onQuoteTriggered: () => onQuoteReply!(message.id),
            child: bubble,
          );
        }

        return bubble;
      },
    );
  }

  (String?, bool) _resolveQuotedText(GroupMessage message) {
    final quotedMessageId = message.quotedMessageId;
    if (quotedMessageId == null || quotedMessageId.isEmpty) {
      return (null, false);
    }

    final quoted = messages.cast<GroupMessage?>().firstWhere(
      (candidate) => candidate?.id == quotedMessageId,
      orElse: () => null,
    );
    if (quoted == null) {
      return (null, true);
    }

    if (quoted.text.isNotEmpty) {
      return (quoted.text, false);
    }

    final quotedMedia = mediaMap[quoted.id] ?? quoted.media;
    if (quotedMedia.isNotEmpty) {
      return (mediaPreviewText(quotedMedia), false);
    }

    return (null, true);
  }

  Widget _buildReadOnlyBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Text(
        'Only admins can send messages in this group',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  void _showReactionBar(BuildContext cardContext, String messageId) {
    // Calculate card position for anchored reaction bar
    double? anchorY;
    final renderObject = cardContext.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      anchorY = renderObject.localToGlobal(Offset.zero).dy;
    }

    final messageReactions = reactions[messageId] ?? [];
    final ownReaction = ownPeerId != null
        ? messageReactions.where((r) => r.senderPeerId == ownPeerId).firstOrNull
        : null;

    showDialog(
      context: cardContext,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => ReactionBar(
        currentEmoji: ownReaction?.emoji,
        anchorY: anchorY,
        onReactionSelected: (emoji) {
          Navigator.of(dialogContext).pop();
          onReactionSelected?.call(messageId, emoji);
        },
        onPlusTap: () {
          Navigator.of(dialogContext).pop();
          _showFullPicker(cardContext, messageId);
        },
        onDismiss: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  void _showFullPicker(BuildContext context, String messageId) async {
    final emoji = await showFullEmojiPicker(context);
    if (emoji != null) {
      onReactionSelected?.call(messageId, emoji);
    }
  }

  static String _formatTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    final hour = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}

class _GroupConversationLoadingShell extends StatelessWidget {
  const _GroupConversationLoadingShell();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('group-loading-shell'),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: const [
        _GroupConversationLoadingBubble(
          index: 0,
          alignment: Alignment.centerLeft,
        ),
        SizedBox(height: 14),
        _GroupConversationLoadingBubble(
          index: 1,
          alignment: Alignment.centerRight,
        ),
        SizedBox(height: 14),
        _GroupConversationLoadingBubble(
          index: 2,
          alignment: Alignment.centerLeft,
        ),
      ],
    );
  }
}

class _GroupConversationLoadingBubble extends StatelessWidget {
  final int index;
  final Alignment alignment;

  const _GroupConversationLoadingBubble({
    required this.index,
    required this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        key: ValueKey('group-loading-bubble-$index'),
        width: index == 1 ? 210 : 240,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: const Color.fromRGBO(255, 255, 255, 0.08),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.1)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GroupConversationLoadingBar(widthFactor: 0.78),
            SizedBox(height: 10),
            _GroupConversationLoadingBar(widthFactor: 0.52),
          ],
        ),
      ),
    );
  }
}

class _GroupConversationLoadingBar extends StatelessWidget {
  final double widthFactor;

  const _GroupConversationLoadingBar({required this.widthFactor});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: const Color.fromRGBO(255, 255, 255, 0.12),
        ),
      ),
    );
  }
}
