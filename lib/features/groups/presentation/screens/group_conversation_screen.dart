import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/full_emoji_picker.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/groups/application/group_sender_display_name.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/group_backlog_retention_notice.dart';
import 'package:flutter_app/features/groups/presentation/group_security_status_view_state.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_dissolved_badge.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

/// Pure UI screen for group conversation.
///
/// Displays header with group name/type, message list using letter cards,
/// and compose area. No business logic -- all data passed via props.
class GroupConversationScreen extends StatelessWidget {
  final GroupModel group;
  final List<GroupMessage> messages;
  final Map<String, GroupMember> membersByPeerId;
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
  final String? highlightedMessageId;
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
  final void Function(String messageId, String emoji)? onReactionTap;
  final void Function(String messageId, String emoji)? onReactionSelected;
  final String? initialText;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<String>? onQuoteReply;
  final ValueChanged<String>? onRetryFailedMedia;
  final ValueChanged<String>? onDeleteFailedMedia;
  final void Function(String messageId, String attachmentId)?
  onRetryUnavailableMedia;
  final String? activeQuoteText;
  final bool isActiveQuoteUnavailable;
  final VoidCallback? onClearQuote;
  final GroupBacklogRetentionNotice? backlogRetentionNotice;
  final GroupHistoryGapRepairNotice? historyGapRepairNotice;
  final BackgroundPreference backgroundPreference;
  final GroupSecurityStatusViewState? securityStatus;
  final bool isRecovering;
  final String? readOnlyBannerText;
  final String? messageLoadErrorText;
  final VoidCallback? onRetryMessageLoad;

  const GroupConversationScreen({
    super.key,
    required this.group,
    required this.messages,
    this.membersByPeerId = const {},
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
    this.highlightedMessageId,
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
    this.onReactionTap,
    this.onReactionSelected,
    this.initialText,
    this.onDraftChanged,
    this.onQuoteReply,
    this.onRetryFailedMedia,
    this.onDeleteFailedMedia,
    this.onRetryUnavailableMedia,
    this.activeQuoteText,
    this.isActiveQuoteUnavailable = false,
    this.onClearQuote,
    this.backlogRetentionNotice,
    this.historyGapRepairNotice,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
    this.securityStatus,
    this.isRecovering = false,
    this.readOnlyBannerText,
    this.messageLoadErrorText,
    this.onRetryMessageLoad,
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
        preference: backgroundPreference,
        child: Builder(
          builder: (context) {
            return Column(
              children: [
                _buildHeader(context),
                if (securityStatus != null)
                  _buildSecurityStrip(context, securityStatus!),
                if (backlogRetentionNotice != null)
                  _buildBacklogRetentionBanner(
                    context,
                    backlogRetentionNotice!,
                  ),
                if (historyGapRepairNotice != null)
                  _buildHistoryGapRepairBanner(
                    context,
                    historyGapRepairNotice!,
                  ),
                if (isRecovering) _buildRecoveryBanner(context),
                if (uploadProgress != null)
                  UploadProgressBanner(
                    state: uploadProgress!,
                    onCancel: onCancelUpload,
                  ),
                Expanded(
                  child: messages.isEmpty
                      ? _buildEmptyOrLoadingState(context)
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
            );
          },
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
    final readableColors = context.backgroundReadableColors;

    return SafeArea(
      bottom: false,
      child: Container(
        key: const ValueKey('group-header'),
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: readableColors.divider, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              color: readableColors.iconPrimary,
              onPressed: onBack,
            ),
            const SizedBox(width: 4),
            GroupAvatar(
              groupId: group.id,
              name: group.name,
              avatarPath: group.avatarPath,
              size: 40,
              cacheBustKey: group.lastMetadataEventAt?.toIso8601String(),
            ),
            const SizedBox(width: 12),
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
                          ).copyWith(color: readableColors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GroupTypeBadge(type: group.type),
                      if (group.isDissolved) ...[
                        const SizedBox(width: 6),
                        const GroupDissolvedBadge(dense: true),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (onInfo != null)
              IconButton(
                icon: Icon(
                  Icons.info_outline,
                  color: readableColors.iconSecondary,
                  size: 22,
                ),
                onPressed: onInfo,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyOrLoadingState(BuildContext context) {
    if (!initialLoadDone || isRecovering) {
      return const _GroupConversationLoadingShell();
    }
    if (messageLoadErrorText != null) {
      return _buildMessageLoadErrorState(context, messageLoadErrorText!);
    }
    return _buildEmptyState(context);
  }

  Widget _buildMessageLoadErrorState(BuildContext context, String errorText) {
    final readableColors = context.backgroundReadableColors;
    final accent = readableColors.isLightSurface
        ? const Color(0xFFB91C1C)
        : const Color(0xFFFCA5A5);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: accent),
            const SizedBox(height: 12),
            Text(
              errorText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: readableColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: readableColors.disabledForeground,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              key: const ValueKey('group-conversation-load-retry'),
              onPressed: onRetryMessageLoad,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: TextButton.styleFrom(foregroundColor: accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecoveryBanner(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final accent = readableColors.isLightSurface
        ? const Color(0xFF0F766E)
        : const Color(0xFF5EEAD4);

    return Container(
      key: const ValueKey('group-recovery-banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(
          alpha: readableColors.isLightSurface ? 0.08 : 0.12,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(
            alpha: readableColors.isLightSurface ? 0.24 : 0.20,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sync_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Catching up missed messages. New messages will still appear here.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: readableColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final notice = backlogRetentionNotice;
    final repairNotice = historyGapRepairNotice;
    final emptyTitle = group.isDissolved
        ? 'No messages yet'
        : (repairNotice?.emptyTitle ?? notice?.emptyTitle ?? 'No messages yet');
    final emptySubtitle = group.isDissolved
        ? 'This group has been dissolved. New messages are disabled.'
        : (repairNotice?.emptySubtitle ??
              notice?.emptySubtitle ??
              (canWrite
                  ? 'Send a message to start the conversation'
                  : 'Waiting for messages'));

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: readableColors.iconMuted,
          ),
          const SizedBox(height: 12),
          Text(
            emptyTitle,
            style: TextStyle(fontSize: 14, color: readableColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            emptySubtitle,
            style: TextStyle(
              fontSize: 12,
              color: readableColors.disabledForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBacklogRetentionBanner(
    BuildContext context,
    GroupBacklogRetentionNotice notice,
  ) {
    final readableColors = context.backgroundReadableColors;
    final retentionAccent = readableColors.isLightSurface
        ? const Color(0xFF8A4A00)
        : const Color(0xFFE6C36A);
    final icon = notice.kind == GroupBacklogRetentionNoticeKind.mixedWindow
        ? Icons.history_rounded
        : Icons.history_toggle_off_rounded;

    return Container(
      key: const ValueKey('group-backlog-retention-banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: retentionAccent.withOpacity(
          readableColors.isLightSurface ? 0.08 : 0.12,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: retentionAccent.withOpacity(
            readableColors.isLightSurface ? 0.24 : 0.20,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: retentionAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notice.bannerText,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: readableColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryGapRepairBanner(
    BuildContext context,
    GroupHistoryGapRepairNotice notice,
  ) {
    final readableColors = context.backgroundReadableColors;
    final activeAccent = readableColors.isLightSurface
        ? const Color(0xFF155E75)
        : const Color(0xFF67E8F9);
    final failedAccent = readableColors.isLightSurface
        ? const Color(0xFF9F1239)
        : const Color(0xFFFDA4AF);
    final repairedAccent = readableColors.isLightSurface
        ? const Color(0xFF116A3A)
        : const Color(0xFF7BD88F);
    final accent = switch (notice.kind) {
      GroupHistoryGapRepairNoticeKind.active => activeAccent,
      GroupHistoryGapRepairNoticeKind.failed => failedAccent,
      GroupHistoryGapRepairNoticeKind.repaired => repairedAccent,
    };
    final icon = switch (notice.kind) {
      GroupHistoryGapRepairNoticeKind.active => Icons.sync_rounded,
      GroupHistoryGapRepairNoticeKind.failed => Icons.error_outline_rounded,
      GroupHistoryGapRepairNoticeKind.repaired => Icons.verified_rounded,
    };

    return Container(
      key: const ValueKey('group-history-gap-repair-banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withOpacity(readableColors.isLightSurface ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withOpacity(
            readableColors.isLightSurface ? 0.24 : 0.20,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notice.bannerText,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: readableColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityStrip(
    BuildContext context,
    GroupSecurityStatusViewState status,
  ) {
    final readableColors = context.backgroundReadableColors;
    final secureAccent = readableColors.isLightSurface
        ? const Color(0xFF116A3A)
        : const Color(0xFF7BD88F);
    final warningAccent = readableColors.isLightSurface
        ? const Color(0xFF8A4A00)
        : const Color(0xFFFFC857);
    final accent = status.hasIdentityWarnings || !status.hasCurrentKey
        ? warningAccent
        : secureAccent;

    return Container(
      key: const ValueKey('group-conversation-security-strip'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withOpacity(readableColors.isLightSurface ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withOpacity(
            readableColors.isLightSurface ? 0.24 : 0.20,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            status.hasIdentityWarnings
                ? Icons.warning_amber_rounded
                : Icons.lock_outline,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.compactEncryptionLabel,
                  key: const ValueKey('group-conversation-security-encryption'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: readableColors.textPrimary,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status.compactReviewLabel,
                  key: const ValueKey('group-conversation-security-review'),
                  style: TextStyle(
                    fontSize: 12,
                    color: readableColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
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
        final isHighlighted = highlightedMessageId == message.id;
        final canReplyFromContext = canWrite && onQuoteReply != null;
        final canCopyFromContext = message.text.trim().isNotEmpty;
        final canShowReactionContext = onReactionSelected != null;
        final canOpenContextOverlay =
            canReplyFromContext || canCopyFromContext || canShowReactionContext;

        LetterCard buildLetterCard({VoidCallback? onLongPress}) => LetterCard(
          senderPeerId: message.senderPeerId,
          senderName: isSent
              ? 'You'
              : resolveGroupSenderDisplayName(
                  senderPeerId: message.senderPeerId,
                  wireSenderUsername: message.senderUsername,
                  member: membersByPeerId[message.senderPeerId],
                  preferMemberName: true,
                ),
          text: message.text,
          time: _formatTime(message.timestamp),
          isIncoming: !isSent,
          status: isSent ? message.status : null,
          quotedText: quotedText,
          isQuoteUnavailable: isQuoteUnavailable,
          media: messageMedia,
          requireVerifiedContentHash: true,
          onMediaTap: onMediaTap != null
              ? (index) => onMediaTap!(message.id, index)
              : null,
          reactions: reactions[message.id] ?? const [],
          ownPeerId: ownPeerId,
          onReactionTap: onReactionTap != null
              ? (emoji) => onReactionTap!(message.id, emoji)
              : null,
          onLongPress: onLongPress,
          onRetryFailedMedia:
              showFailedMediaActions && onRetryFailedMedia != null
              ? () => onRetryFailedMedia!(message.id)
              : null,
          onDeleteFailedMedia:
              showFailedMediaActions && onDeleteFailedMedia != null
              ? () => onDeleteFailedMedia!(message.id)
              : null,
          onRetryUnavailableMedia: onRetryUnavailableMedia != null
              ? (attachmentId) =>
                    onRetryUnavailableMedia!(message.id, attachmentId)
              : null,
          failedMediaActionKeySuffix: message.id,
        );

        Widget bubble = Padding(
          key: ValueKey('grp-msg-${message.id}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: Builder(
            builder: (cardContext) => buildLetterCard(
              onLongPress: canOpenContextOverlay
                  ? () => _showMessageContextOverlay(
                      message,
                      cardContext: cardContext,
                      selectedMessage: buildLetterCard(),
                    )
                  : null,
            ),
          ),
        );

        if (!isSent && canWrite && onQuoteReply != null) {
          bubble = SwipeToQuoteBubble(
            onQuoteTriggered: () => onQuoteReply!(message.id),
            child: bubble,
          );
        }

        if (isHighlighted) {
          final readableColors = context.backgroundReadableColors;
          bubble = AnimatedContainer(
            key: ValueKey('grp-highlight-${message.id}'),
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: readableColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: readableColors.border),
            ),
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
    // This is only called from the `AmbientBackground` subtree.
    return Builder(builder: _buildReadOnlyBannerInner);
  }

  Widget _buildReadOnlyBannerInner(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Container(
      key: const ValueKey('group-read-only-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: readableColors.divider, width: 0.5),
        ),
      ),
      child: Text(
        readOnlyBannerText ??
            (group.isDissolved
                ? 'This group has been dissolved. History stays available, but new messages are disabled.'
                : 'Only admins can send messages in this group'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: readableColors.textMuted),
      ),
    );
  }

  void _showMessageContextOverlay(
    GroupMessage message, {
    required BuildContext cardContext,
    required Widget selectedMessage,
  }) {
    final route = ModalRoute.of(cardContext);
    if (route != null && !route.isCurrent) return;

    final renderObject = cardContext.findRenderObject();
    Rect anchorRect = Rect.fromCenter(
      center: MediaQuery.of(cardContext).size.center(Offset.zero),
      width: 0,
      height: 0,
    );
    if (renderObject is RenderBox && renderObject.hasSize) {
      final topLeft = renderObject.localToGlobal(Offset.zero);
      anchorRect = topLeft & renderObject.size;
    }

    final messageReactions = reactions[message.id] ?? [];
    final ownReaction = ownPeerId != null
        ? messageReactions.where((r) => r.senderPeerId == ownPeerId).firstOrNull
        : null;
    final showReplyAction = canWrite && onQuoteReply != null;
    final showCopyAction = message.text.trim().isNotEmpty;
    final showReactionBar = onReactionSelected != null;

    showDialog(
      context: cardContext,
      useSafeArea: false,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => MessageContextOverlay(
        anchorRect: anchorRect,
        selectedMessage: selectedMessage,
        currentEmoji: ownReaction?.emoji,
        showReactionBar: showReactionBar,
        showReplyAction: showReplyAction,
        showCopyAction: showCopyAction,
        onDismiss: () => Navigator.of(dialogContext).pop(),
        onReactionSelected: showReactionBar
            ? (emoji) {
                Navigator.of(dialogContext).pop();
                onReactionSelected?.call(message.id, emoji);
              }
            : null,
        onPlusTap: showReactionBar
            ? () {
                Navigator.of(dialogContext).pop();
                _showFullPicker(cardContext, message.id);
              }
            : null,
        onReplyTap: showReplyAction
            ? () {
                Navigator.of(dialogContext).pop();
                onQuoteReply?.call(message.id);
              }
            : null,
        onCopyTap: showCopyAction
            ? () async {
                Navigator.of(dialogContext).pop();
                await _copyMessageText(cardContext, message.text);
              }
            : null,
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

  Future<void> _copyMessageText(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.conversation_context_copied,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
    final readableColors = context.backgroundReadableColors;

    return Align(
      alignment: alignment,
      child: Container(
        key: ValueKey('group-loading-bubble-$index'),
        width: index == 1 ? 210 : 240,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: readableColors.surfaceRaised,
          border: Border.all(color: readableColors.divider),
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
    final readableColors = context.backgroundReadableColors;

    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: readableColors.disabledSurface,
        ),
      ),
    );
  }
}
