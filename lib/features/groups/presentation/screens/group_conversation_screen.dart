import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/format_day_separator_label.dart';
import 'package:flutter_app/core/widgets/quiet_confirm.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/utils/message_run_grouping.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_private_media_viewer.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/full_emoji_picker.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/offline_message_banner.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/groups/application/group_received_media_action_policy.dart';
import 'package:flutter_app/features/groups/application/group_sender_display_name.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/presentation/group_backlog_retention_notice.dart';
import 'package:flutter_app/features/groups/presentation/group_security_status_view_state.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_dissolved_badge.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_media_info_sheet.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

/// Privacy-safe quoted-parent projection shared by persisted reply bubbles and
/// the wired/restored composer quote preview. A private or unsupported parent
/// never contributes its stored body or media subtype to an ordinary surface.
(String?, bool) resolveGroupQuotedPreview({
  required GroupMessage quoted,
  required List<MediaAttachment> quotedMedia,
  required String privatePlaceholder,
}) {
  if (quoted.privateMediaPolicy.requiresRedaction) {
    return (privatePlaceholder, false);
  }
  if (quoted.text.isNotEmpty) return (quoted.text, false);
  if (quotedMedia.isNotEmpty) return (mediaPreviewText(quotedMedia), false);
  return (null, true);
}

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
  final Map<String, MessageUploadProgressViewState> messageUploadProgress;
  final VoidCallback? onCancelUpload;
  final P2PService? p2pService;
  final bool initialLoadDone;
  final ScrollController? scrollController;
  final String? highlightedMessageId;

  /// When set, attached to the currently-highlighted row so the wired layer can
  /// resolve a [BuildContext] for [Scrollable.ensureVisible] — i.e. scroll a
  /// notification-tapped message into view, not merely highlight it.
  final GlobalKey? highlightAnchorKey;
  final Map<String, List<MediaAttachment>> mediaMap;
  final Map<String, String> mediaRenderedSemanticsLabels;
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
  final ValueChanged<String>? onOpenPrivateMedia;
  final bool privateMediaEnabled;

  /// 235: received-media actions for INCOMING discussion image/video rows.
  /// Availability is decided per attachment by
  /// [GroupReceivedMediaActionPolicy]; these callbacks carry the exact
  /// attachment identity. Delete for me is whole-message (current group
  /// persistence/tombstones are message-scoped).
  final void Function(String messageId, String attachmentId)? onMediaSave;
  final void Function(String messageId, String attachmentId)? onMediaShare;
  final Future<void> Function(String messageId, String attachmentId)?
  onMediaInfo;
  final ValueChanged<String>? onMediaDeleteForMe;
  final Future<bool> Function(String messageId, String senderPeerId)?
  isMessageSenderEligible;
  final Future<void> Function(String messageId, String senderPeerId)?
  onMessageSenderTap;
  final Map<String, List<MessageReaction>> reactions;
  final void Function(String messageId, String emoji)? onReactionTap;
  final void Function(String messageId, String emoji)? onReactionSelected;
  final String? initialText;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<String>? onQuoteReply;
  final ValueChanged<String>? onRetryFailedMessage;
  final ValueChanged<String>? onRetryFailedMedia;
  final ValueChanged<String>? onDeleteFailedMedia;

  /// 144: when non-null, a terminal send failure (group dissolved / removed /
  /// unavailable) is latched. Drives the per-message "Couldn't send — …" reason
  /// on terminal `send_failed` rows and makes them non-retryable.
  final String? failedTerminalReasonText;

  /// 144: deletes a terminal `send_failed` bubble. Wired even while the composer
  /// is read-only so a stuck bubble can always be cleared.
  final ValueChanged<String>? onDeleteFailedTerminalMessage;
  final void Function(String messageId, String attachmentId)?
  onRetryUnavailableMedia;
  final Set<String> retryingFailedMessageIds;
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

  /// 159: the wired layer's memoized run-grouped display list. When non-null the
  /// screen renders it directly (the StatelessWidget cannot cache across
  /// rebuilds); when null the screen computes a fallback locally (direct-
  /// construction widget tests).
  final List<GroupDisplayItem>? precomputedDisplayItems;

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
    this.messageUploadProgress = const {},
    this.onCancelUpload,
    this.p2pService,
    this.initialLoadDone = false,
    this.scrollController,
    this.highlightedMessageId,
    this.highlightAnchorKey,
    this.mediaMap = const {},
    this.mediaRenderedSemanticsLabels = const <String, String>{},
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
    this.onOpenPrivateMedia,
    this.privateMediaEnabled = false,
    this.onMediaSave,
    this.onMediaShare,
    this.onMediaInfo,
    this.onMediaDeleteForMe,
    this.isMessageSenderEligible,
    this.onMessageSenderTap,
    this.reactions = const {},
    this.onReactionTap,
    this.onReactionSelected,
    this.initialText,
    this.onDraftChanged,
    this.onQuoteReply,
    this.onRetryFailedMessage,
    this.onRetryFailedMedia,
    this.onDeleteFailedMedia,
    this.failedTerminalReasonText,
    this.onDeleteFailedTerminalMessage,
    this.onRetryUnavailableMedia,
    this.retryingFailedMessageIds = const {},
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
    this.precomputedDisplayItems,
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
        isChatSurface: true,
        child: Builder(
          builder: (context) {
            return Column(
              children: [
                _buildHeader(context),
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
                if (p2pService != null)
                  OfflineMessageBanner(p2pService: p2pService!),
                if (uploadProgress != null)
                  UploadProgressBanner(
                    state: uploadProgress!,
                    onCancel: onCancelUpload,
                  ),
                Expanded(
                  child: messages.isEmpty
                      ? _buildEmptyOrLoadingState(context)
                      : _buildMessageList(context),
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
            invalidIndices: composerState.invalidAttachmentIndices,
            invalidReasons: composerState.invalidAttachmentReasons,
            hasTotalSizeOverflow: composerState.hasTotalSizeOverflow,
            onRemove: onRemoveAttachment,
          ),
        if (!canWrite)
          _buildReadOnlyBanner()
        else
          Column(
            children: [
              ComposeArea(
                onSend: onSend,
                onAttach: onAttach,
                hasAttachments: composerState.pendingAttachments.isNotEmpty,
                hasInvalidAttachment: composerState.hasInvalidAttachment,
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
    final l10n = AppLocalizations.of(context)!;

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
              l10n.load_retry_hint,
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
              label: Text(l10n.btn_retry),
              style: TextButton.styleFrom(foregroundColor: accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final notice = backlogRetentionNotice;
    final repairNotice = historyGapRepairNotice;
    final emptyTitle = group.isDissolved
        ? l10n.group_no_messages
        : (repairNotice?.emptyTitle ??
              notice?.emptyTitle ??
              l10n.group_no_messages);
    final emptySubtitle = group.isDissolved
        ? l10n.group_empty_dissolved_desc
        : (repairNotice?.emptySubtitle ??
              notice?.emptySubtitle ??
              (canWrite ? l10n.group_empty_start : l10n.group_empty_waiting));

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
        color: retentionAccent.withValues(
          alpha: readableColors.isLightSurface ? 0.08 : 0.12,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: retentionAccent.withValues(
            alpha: readableColors.isLightSurface ? 0.24 : 0.20,
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

  Widget _buildMessageList(BuildContext context) {
    // 159: prefer the wired layer's memoized list (the screen is a
    // StatelessWidget and cannot cache across rebuilds); fall back to a local
    // compute only for direct-construction widget tests.
    final displayItems =
        precomputedDisplayItems ?? _buildGroupDisplayItems(context);
    final childIndexByKey = <Key, int>{
      for (var index = 0; index < displayItems.length; index++)
        if (displayItems[index].type == GroupDisplayItemType.message)
          ValueKey<String>('grp-row-${displayItems[index].message!.id}'): index,
    };
    // 156 QW-10 (lists-scrolling-1): build the quoted-parent lookup ONCE per
    // frame instead of an O(N) `messages.firstWhere(...)` scan per visible row.
    final messagesById = <String, GroupMessage>{
      for (final m in messages) m.id: m,
    };
    // 156 QW-12 (lists-scrolling-3): construct the localized time formatter ONCE
    // per frame instead of `intl.DateFormat.jm(locale)` per visible row.
    final timeFormat = intl.DateFormat.jm(
      Localizations.localeOf(context).toString(),
    );
    return ListView.builder(
      key: const ValueKey('group-messages'),
      controller: scrollController,
      reverse: true,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: displayItems.length,
      findChildIndexCallback: (key) => childIndexByKey[key],
      itemBuilder: (context, index) {
        // Reversed display list: index 0 = newest.
        final item = displayItems[index];
        if (item.type == GroupDisplayItemType.dateSeparator) {
          return DateSeparator(label: item.dateLabel!);
        }
        final message = item.message!;
        final isSent = message.senderPeerId == ownPeerId;
        final redactsPrivateMedia =
            message.privateMediaPolicy.requiresRedaction;
        final canOpenPrivateMedia =
            privateMediaEnabled &&
            message.isIncoming &&
            message.privateMediaPolicy.isPrivate &&
            message.mediaConsumedAt == null &&
            message.mediaExpiredAt == null &&
            !message.mediaCleanupPending &&
            onOpenPrivateMedia != null;
        final (
          resolvedQuotedText,
          resolvedQuoteUnavailable,
        ) = _resolveQuotedText(
          message,
          messagesById,
          privatePlaceholder: AppLocalizations.of(context)!.media_unavailable,
        );
        final quotedText = redactsPrivateMedia ? null : resolvedQuotedText;
        final isQuoteUnavailable =
            !redactsPrivateMedia && resolvedQuoteUnavailable;
        final loadedMessageMedia = mediaMap[message.id] ?? message.media;
        final messageMedia = redactsPrivateMedia
            ? const <MediaAttachment>[]
            : loadedMessageMedia;
        final displayText = redactsPrivateMedia ? '' : message.text;
        final messageReactions = redactsPrivateMedia
            ? const <MessageReaction>[]
            : (reactions[message.id] ?? const <MessageReaction>[]);
        // Finding 05 Phase 4: a terminal send_failed row offers the same manual
        // retry affordance as a failed row — the retry re-arms it with a fresh
        // attempt budget; the background retrier no longer auto-retries it.
        final isFailedSend =
            message.status == 'failed' ||
            message.status == GroupMessage.statusSendFailed;
        // 144 finding: a terminal send_failed row persisted by the keep-bubble
        // path before any retry payload existed can NEVER be retried (the retry
        // use case skips it with missing_retry_payload). Only offer Retry for a
        // send_failed row that actually carries a payload — a retry-exhausted
        // row (Finding 05 Phase 4) does; a terminal-failure row does not. Plain
        // 'failed' rows keep their existing behavior (they always have a
        // payload). This matters after the F1 self-heal re-opens the composer.
        final isRetryExhaustedSend =
            message.status == GroupMessage.statusSendFailed;
        final hasRetryPayload =
            (message.wireEnvelope?.isNotEmpty ?? false) ||
            (message.inboxRetryPayload?.isNotEmpty ?? false);
        final showFailedMediaActions =
            canWrite && isSent && isFailedSend && loadedMessageMedia.isNotEmpty;
        final hasUnfinishedFailedMedia = loadedMessageMedia.any(
          (attachment) => attachment.downloadStatus != 'done',
        );
        final showFailedMediaRetry =
            showFailedMediaActions &&
            (hasUnfinishedFailedMedia
                ? message.status == 'failed'
                : (!isRetryExhaustedSend || hasRetryPayload)) &&
            isManualUploadRetryAttachmentSetEligible(
              loadedMessageMedia,
              sourceExists: (storedPath) => File(
                MediaFileManager.resolveStoredPathSync(storedPath),
              ).existsSync(),
            );
        final showFailedTextRetry =
            !redactsPrivateMedia &&
            canWrite &&
            isSent &&
            isFailedSend &&
            loadedMessageMedia.isEmpty &&
            message.text.trim().isNotEmpty &&
            onRetryFailedMessage != null &&
            (!isRetryExhaustedSend || hasRetryPayload);
        // 144: a TERMINAL send_failed bubble (group dissolved / removed from the
        // group / group gone). It carries the "Couldn't send — …" reason and a
        // Delete-only affordance (no Retry — retry can never succeed). The
        // reason is latched at the screen level, so a retry-exhausted
        // send_failed row in a still-writable group (failedTerminalReasonText
        // == null) keeps its existing treatment and shows no terminal reason.
        final isTerminalSendFailed =
            isSent && message.status == GroupMessage.statusSendFailed;
        final showTerminalSendFailed =
            isTerminalSendFailed && failedTerminalReasonText != null;
        // 144 finding: a text send_failed row that cannot be retried (no payload)
        // must always keep Delete reachable so a stuck bubble can be cleared —
        // even after the read-only latch self-heals (failedTerminalReasonText
        // goes null) and even while no terminal reason is latched.
        final showTerminalDelete =
            showTerminalSendFailed ||
            (isTerminalSendFailed &&
                loadedMessageMedia.isEmpty &&
                !hasRetryPayload);
        final isRetryingFailedText = retryingFailedMessageIds.contains(
          message.id,
        );
        final isFailedTextRetryEnabled =
            showFailedTextRetry && !isRecovering && !isRetryingFailedText;
        final isHighlighted = highlightedMessageId == message.id;
        final canReplyFromContext =
            !redactsPrivateMedia && canWrite && onQuoteReply != null;
        final canCopyFromContext =
            !redactsPrivateMedia && message.text.trim().isNotEmpty;
        final canShowReactionContext =
            !redactsPrivateMedia && onReactionSelected != null;
        final canOpenContextOverlay =
            canReplyFromContext || canCopyFromContext || canShowReactionContext;

        // 136 Phase 4: render as side-aligned chat balloons and group
        // consecutive same-sender messages into one run. Groups show ONE
        // avatar + sender name per INCOMING run (first balloon only);
        // outgoing balloons never show an avatar. System/membership rows
        // (sys- id prefix) are their own run and carry NO run chrome even
        // though they are incoming + first-in-run. Both the live card and the
        // long-press lifted snapshot are built from the SAME flags so the
        // snapshot never visually jumps (TC-29).
        final isSystemRow = message.id.startsWith('sys-');
        final runChrome = messageRunChrome(
          surface: MessageRunSurface.group,
          isOutgoing: isSent,
          isFirstInGroup: item.isFirstInGroup,
        );
        final showRunAvatar = runChrome.showAvatar && !isSystemRow;
        final showRunSenderName = runChrome.showSenderName && !isSystemRow;

        // 235: exact-attachment identity for received-media actions. The
        // filter matches LetterCard._imageVideoMedia so the long-press index
        // addresses the same tile the user pressed.
        final visualMedia = messageMedia
            .where((a) => a.mediaType == 'image' || a.mediaType == 'video')
            .toList();
        Widget Function()? privateContentSlotFactory;
        if (redactsPrivateMedia) {
          final privateVisual = loadedMessageMedia
              .where(
                (attachment) =>
                    attachment.mediaType == 'image' ||
                    attachment.mediaType == 'gif' ||
                    attachment.mediaType == 'video',
              )
              .toList(growable: false);
          final isVideo =
              privateVisual.length == 1 &&
              (privateVisual.single.mediaType == 'video' ||
                  privateVisual.single.mime.startsWith('video/'));
          privateContentSlotFactory = () => Container(
            key: ValueKey('group-private-media-slot-${message.id}'),
            child: _buildGroupPrivateMediaCard(
              context,
              message: message,
              isVideo: isVideo,
              canOpen: canOpenPrivateMedia,
            ),
          );
        }

        LetterCard buildLetterCard({
          VoidCallback? onLongPress,
          void Function(int index)? onMediaLongPress,
        }) => LetterCard(
          senderPeerId: message.senderPeerId,
          senderName: isSent
              ? AppLocalizations.of(context)!.feed_you
              : resolveGroupSenderDisplayName(
                  senderPeerId: message.senderPeerId,
                  wireSenderUsername: message.senderUsername,
                  member: membersByPeerId[message.senderPeerId],
                  preferMemberName: true,
                ),
          text: displayText,
          time: timeFormat.format(message.timestamp.toLocal()),
          isIncoming: !isSent,
          // 236: origin-minimizing durable marker — the label says only
          // "Forwarded"; no source sender/group/message identity exists on
          // the row at all.
          isForwarded: message.isForwarded,
          bubbleLayout: true,
          isFirstInGroup: item.isFirstInGroup,
          isLastInGroup: item.isLastInGroup,
          showAvatar: showRunAvatar,
          showSenderName: showRunSenderName,
          // 137 follow-up: render the run avatar in a left gutter OUTSIDE the
          // bubble. The gutter is reserved on every incoming non-system balloon
          // so the run shares one left edge; the avatar paints on the first
          // balloon only (showRunAvatar).
          avatarOutsideBubble: !isSent && !isSystemRow,
          status: isSent ? message.status : null,
          quotedText: quotedText,
          isQuoteUnavailable: isQuoteUnavailable,
          media: loadedMessageMedia,
          decoratedBodyKey: redactsPrivateMedia
              ? ValueKey('group-private-media-decorated-body-${message.id}')
              : null,
          privateContentSlot: privateContentSlotFactory?.call(),
          requireVerifiedContentHash: true,
          // 128 (round 5): render-boundary fallback to the durable owned copy.
          // Group durable media is keyed under media/<groupId>/<blob> (see
          // group_conversation_wired relativePathForAttachment(contactPeerId:
          // widget.group.id)), so the owned-copy dir id is the group id. The
          // verified-content-hash gate above still applies — the fallback only
          // supplies the path; it never bypasses verification.
          ownedMediaPeerId: group.id,
          mediaRenderedSemanticsLabels: mediaRenderedSemanticsLabels,
          onMediaTap:
              onMediaTap != null &&
                  !message.privateMediaPolicy.requiresRedaction
              ? (index) => onMediaTap!(message.id, index)
              : null,
          onMediaLongPress: onMediaLongPress,
          reactions: messageReactions,
          ownPeerId: ownPeerId,
          onReactionTap: !redactsPrivateMedia && onReactionTap != null
              ? (emoji) => onReactionTap!(message.id, emoji)
              : null,
          onLongPress: onLongPress,
          onRetryFailedMessage: showFailedTextRetry
              ? () => onRetryFailedMessage!(message.id)
              : null,
          isRetryFailedMessageEnabled: isFailedTextRetryEnabled,
          failedMessageActionKeySuffix: message.id,
          onRetryFailedMedia: showFailedMediaRetry && onRetryFailedMedia != null
              ? () => onRetryFailedMedia!(message.id)
              : null,
          onDeleteFailedMedia:
              showFailedMediaActions && onDeleteFailedMedia != null
              ? () => onDeleteFailedMedia!(message.id)
              : null,
          failedReasonText: showTerminalSendFailed
              ? failedTerminalReasonText
              : null,
          onDeleteFailedMessage:
              showTerminalDelete && onDeleteFailedTerminalMessage != null
              ? () => onDeleteFailedTerminalMessage!(message.id)
              : null,
          onRetryUnavailableMedia: onRetryUnavailableMedia != null
              ? (attachmentId) =>
                    onRetryUnavailableMedia!(message.id, attachmentId)
              : null,
          failedMediaActionKeySuffix: message.id,
          messageUploadProgress: messageUploadProgress[message.id],
        );

        final content = Padding(
          key: ValueKey('grp-msg-${message.id}'),
          // 137 follow-up: tight gap within a run, larger gap between runs.
          padding: EdgeInsets.only(
            bottom: messageRunBottomSpacing(
              isLastInGroup: item.isLastInGroup,
              runSeparation: 12,
            ),
          ),
          child: Builder(
            builder: (cardContext) => buildLetterCard(
              onLongPress: canOpenContextOverlay
                  ? () => unawaited(
                      _showMessageContextOverlay(
                        message,
                        cardContext: cardContext,
                        selectedMessage: buildLetterCard(),
                      ),
                    )
                  : null,
              onMediaLongPress: visualMedia.isNotEmpty
                  ? (index) {
                      if (index < 0 || index >= visualMedia.length) return;
                      final attachment = visualMedia[index];
                      final capabilities =
                          GroupReceivedMediaActionPolicy.capabilitiesFor(
                            groupType: group.type,
                            isIncoming: !isSent,
                            attachment: attachment,
                            canWrite: canWrite,
                            mediaPolicy: message.privateMediaPolicy,
                          );
                      final hasMediaMenuEntry =
                          (capabilities.contains(
                                GroupReceivedMediaAction.save,
                              ) &&
                              onMediaSave != null) ||
                          (capabilities.contains(
                                GroupReceivedMediaAction.share,
                              ) &&
                              onMediaShare != null) ||
                          capabilities.contains(
                            GroupReceivedMediaAction.info,
                          ) ||
                          (capabilities.contains(
                                GroupReceivedMediaAction.deleteForMe,
                              ) &&
                              onMediaDeleteForMe != null);
                      if (hasMediaMenuEntry) {
                        unawaited(
                          _showMessageContextOverlay(
                            message,
                            cardContext: cardContext,
                            selectedMessage: buildLetterCard(),
                            mediaTarget: attachment,
                            mediaCapabilities: capabilities,
                          ),
                        );
                      } else if (canOpenContextOverlay) {
                        // No media action applies (outgoing, QA, ...): keep
                        // the pre-235 behavior where a tile long-press opened
                        // the plain message overlay.
                        unawaited(
                          _showMessageContextOverlay(
                            message,
                            cardContext: cardContext,
                            selectedMessage: buildLetterCard(),
                          ),
                        );
                      }
                    }
                  : null,
            ),
          ),
        );

        return _GroupMessageRow(
          key: ValueKey('grp-row-${message.id}'),
          content: content,
          decorate: (bubble) {
            if (canOpenPrivateMedia) {
              bubble = Semantics(
                button: true,
                label: AppLocalizations.of(context)!.private_media_open,
                child: GestureDetector(
                  key: ValueKey('group-private-open-${message.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onOpenPrivateMedia!(message.id),
                  child: bubble,
                ),
              );
            }

            // 136 Phase 4: swipe-to-reply is enabled on EVERY balloon in BOTH
            // directions (outgoing balloons now get the gesture too), still gated
            // by write permission. System/membership rows (sys- ids) are excluded:
            // they are not quote-reply targets, matching the 1:1 surface where
            // transport=='system' rows render as IntroSystemMessage before the
            // swipe wrap.
            if (!redactsPrivateMedia &&
                !isSystemRow &&
                canWrite &&
                onQuoteReply != null) {
              bubble = SwipeToQuoteBubble(
                onQuoteTriggered: () => onQuoteReply!(message.id),
                child: bubble,
              );
            }

            if (isHighlighted) {
              bubble = _buildHighlightedMessageCue(
                context,
                messageId: message.id,
                isSent: isSent,
                child: bubble,
              );
            }

            return bubble;
          },
        );
      },
    );
  }

  String _groupPrivateMediaPlaceholderText(
    BuildContext context,
    GroupMessage message,
  ) {
    final l10n = AppLocalizations.of(context)!;
    if (!privateMediaEnabled) return l10n.media_unavailable;
    if (message.privateMediaPolicy.isUnsupported) {
      return l10n.private_media_unsupported;
    }
    if (message.mediaConsumedAt != null) return l10n.private_media_consumed;
    if (message.mediaExpiredAt != null) return l10n.private_media_expired;
    return l10n.group_private_media_notification_body;
  }

  Widget _buildGroupPrivateMediaCard(
    BuildContext context, {
    required GroupMessage message,
    required bool isVideo,
    required bool canOpen,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final policy = message.privateMediaPolicy;
    final title = switch (policy.lifecycle) {
      GroupMediaLifecycle.viewOnce =>
        isVideo
            ? l10n.private_media_card_title_view_once_video
            : l10n.private_media_card_title_view_once_photo,
      GroupMediaLifecycle.disappearing =>
        isVideo
            ? l10n.private_media_card_title_expiry_video(
                privateMediaDurationLabel(l10n, policy.durationSeconds),
              )
            : l10n.private_media_card_title_expiry_photo(
                privateMediaDurationLabel(l10n, policy.durationSeconds),
              ),
      _ =>
        isVideo
            ? l10n.private_media_card_title_protected_video
            : l10n.private_media_card_title_protected_photo,
    };
    final body = _groupPrivateMediaPlaceholderText(context, message);
    final icon = switch (policy.lifecycle) {
      GroupMediaLifecycle.viewOnce => Icons.looks_one_outlined,
      GroupMediaLifecycle.disappearing => Icons.timer_outlined,
      GroupMediaLifecycle.unsupported => Icons.system_update_alt_rounded,
      _
          when message.mediaConsumedAt != null ||
              message.mediaExpiredAt != null =>
        Icons.visibility_off_outlined,
      _ => Icons.lock_outline_rounded,
    };
    final actionLabel = policy.lifecycle == GroupMediaLifecycle.viewOnce
        ? (isVideo
              ? l10n.private_media_view_video
              : l10n.private_media_view_photo)
        : (isVideo
              ? l10n.private_media_open_video
              : l10n.private_media_open_photo);
    final showAction =
        canOpen &&
        privateMediaEnabled &&
        !policy.isUnsupported &&
        message.mediaConsumedAt == null &&
        message.mediaExpiredAt == null;

    return Semantics(
      label: body,
      child: PrivateMediaVisualCard(
        title: title,
        body: body,
        icon: icon,
        action: showAction
            ? FilledButton.tonalIcon(
                key: ValueKey('group-private-card-action-${message.id}'),
                onPressed: () => onOpenPrivateMedia?.call(message.id),
                icon: const Icon(Icons.lock_open_outlined),
                label: Text(actionLabel),
              )
            : null,
      ),
    );
  }

  /// Flattens [messages] into display items, inserting a WhatsApp-style date
  /// separator before the first message of each calendar day. The result is
  /// reversed for the reversed ListView (index 0 = newest), so each separator
  /// renders above that day's first message.
  ///
  /// Dedup is keyed on a SET of already-emitted day labels rather than just the
  /// previous one: group messages are ordered by [orderGroupMessagesForTimeline]
  /// (replies are pulled after their quoted parent), so the day sequence is not
  /// guaranteed monotonic. A set guarantees each calendar day gets exactly one
  /// separator even when a reordered reply revisits an earlier day.
  /// 159: thin fallback wrapper around the now-public [buildGroupDisplayItems].
  /// Used only when the screen is constructed directly (widget tests) without a
  /// [precomputedDisplayItems] — the wired layer memoizes this on its State and
  /// passes the result down (the screen is Stateless and cannot cache).
  List<GroupDisplayItem> _buildGroupDisplayItems(BuildContext context) {
    return buildGroupDisplayItems(
      messages: messages,
      l10n: AppLocalizations.of(context)!,
      locale: Localizations.localeOf(context).toString(),
      now: DateTime.now(),
    );
  }

  Widget _buildHighlightedMessageCue(
    BuildContext context, {
    required String messageId,
    required bool isSent,
    required Widget child,
  }) {
    final readableColors = context.backgroundReadableColors;
    final focusAccent = readableColors.isLightSurface
        ? const Color(0xFF0F766E)
        : const Color(0xFF4ECDC4);

    final cue = Stack(
      key: ValueKey('grp-highlight-$messageId'),
      clipBehavior: Clip.none,
      children: [
        child,
        PositionedDirectional(
          start: isSent ? null : 2,
          end: isSent ? 2 : null,
          top: 10,
          bottom: 22,
          child: IgnorePointer(
            child: AnimatedContainer(
              key: ValueKey('grp-highlight-cue-$messageId'),
              duration: const Duration(milliseconds: 180),
              width: 3,
              decoration: BoxDecoration(
                color: focusAccent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: focusAccent.withValues(
                      alpha: readableColors.isLightSurface ? 0.24 : 0.36,
                    ),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    // Only the single highlighted row is built here, so the anchor key never
    // collides. The wired layer reads its currentContext for ensureVisible.
    final anchorKey = highlightAnchorKey;
    if (anchorKey != null) {
      return KeyedSubtree(key: anchorKey, child: cue);
    }
    return cue;
  }

  // 156 QW-10: resolve the quoted parent via a prebuilt id→message map (O(1))
  // instead of an O(N) linear scan per call.
  (String?, bool) _resolveQuotedText(
    GroupMessage message,
    Map<String, GroupMessage> messagesById, {
    required String privatePlaceholder,
  }) {
    final quotedMessageId = message.quotedMessageId;
    if (quotedMessageId == null || quotedMessageId.isEmpty) {
      return (null, false);
    }

    final quoted = messagesById[quotedMessageId];
    if (quoted == null) {
      return (null, true);
    }

    final quotedMedia = mediaMap[quoted.id] ?? quoted.media;
    return resolveGroupQuotedPreview(
      quoted: quoted,
      quotedMedia: quotedMedia,
      privatePlaceholder: privatePlaceholder,
    );
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
                ? AppLocalizations.of(context)!.group_read_only_dissolved
                : AppLocalizations.of(context)!.group_read_only_admin_only),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: readableColors.textMuted),
      ),
    );
  }

  Future<void> _showMessageContextOverlay(
    GroupMessage message, {
    required BuildContext cardContext,
    required Widget selectedMessage,
    MediaAttachment? mediaTarget,
    Set<GroupReceivedMediaAction> mediaCapabilities = const {},
  }) async {
    final route = ModalRoute.of(cardContext);
    if (route != null && !route.isCurrent) return;

    var showMessageSenderAction = false;
    final qualifyMessageSender = isMessageSenderEligible;
    if (mediaTarget != null &&
        qualifyMessageSender != null &&
        onMessageSenderTap != null) {
      try {
        showMessageSenderAction = await qualifyMessageSender(
          message.id,
          message.senderPeerId,
        );
      } catch (_) {
        showMessageSenderAction = false;
      }
    }
    if (!cardContext.mounted) return;
    final currentRoute = ModalRoute.of(cardContext);
    if (currentRoute != null && !currentRoute.isCurrent) return;

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
    // 239: a media-target overlay derives Reply from the policy capability
    // set, not raw canWrite — a writable announcement admin gets the same
    // four received-media actions as a member and never Reply. The plain
    // (non-media) message overlay keeps its pre-239 canWrite behavior.
    final showReplyAction =
        canWrite &&
        onQuoteReply != null &&
        (mediaTarget == null ||
            mediaCapabilities.contains(GroupReceivedMediaAction.reply));
    final showCopyAction = message.text.trim().isNotEmpty;
    final showReactionBar = onReactionSelected != null;
    // 235: received-media entries for the exact long-pressed attachment. The
    // policy already excluded outgoing, non-visual, non-group-lane, and QA
    // rows.
    final showSaveAction =
        mediaTarget != null &&
        mediaCapabilities.contains(GroupReceivedMediaAction.save) &&
        onMediaSave != null;
    final showShareAction =
        mediaTarget != null &&
        mediaCapabilities.contains(GroupReceivedMediaAction.share) &&
        onMediaShare != null;
    final showInfoAction =
        mediaTarget != null &&
        mediaCapabilities.contains(GroupReceivedMediaAction.info);
    final showMediaDeleteAction =
        mediaTarget != null &&
        mediaCapabilities.contains(GroupReceivedMediaAction.deleteForMe) &&
        onMediaDeleteForMe != null;

    await showDialog<void>(
      context: cardContext,
      useSafeArea: false,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => MessageContextOverlay(
        anchorRect: anchorRect,
        selectedMessage: selectedMessage,
        currentEmoji: ownReaction?.emoji,
        showReactionBar: showReactionBar,
        showReplyAction: showReplyAction,
        showMessageSenderAction: showMessageSenderAction,
        showCopyAction: showCopyAction,
        showSaveAction: showSaveAction,
        showShareAction: showShareAction,
        showInfoAction: showInfoAction,
        showDeleteAction: showMediaDeleteAction,
        onSaveTap: showSaveAction
            ? () {
                Navigator.of(dialogContext).pop();
                onMediaSave?.call(message.id, mediaTarget.id);
              }
            : null,
        onShareTap: showShareAction
            ? () {
                Navigator.of(dialogContext).pop();
                onMediaShare?.call(message.id, mediaTarget.id);
              }
            : null,
        onInfoTap: showInfoAction
            ? () {
                Navigator.of(dialogContext).pop();
                final dispatch = onMediaInfo;
                if (dispatch != null) {
                  unawaited(dispatch(message.id, mediaTarget.id));
                } else {
                  _showMediaInfoSheet(cardContext, message, mediaTarget);
                }
              }
            : null,
        onDeleteTap: showMediaDeleteAction
            ? () {
                Navigator.of(dialogContext).pop();
                onMediaDeleteForMe?.call(message.id);
              }
            : null,
        onMessageSenderTap: showMessageSenderAction
            ? () {
                // Dismiss synchronously. The wired owner then performs the
                // second fresh resolution before feedback or navigation.
                Navigator.of(dialogContext).pop();
                unawaited(
                  onMessageSenderTap!.call(message.id, message.senderPeerId),
                );
              }
            : null,
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

  void _showMediaInfoSheet(
    BuildContext context,
    GroupMessage message,
    MediaAttachment attachment,
  ) {
    if (!context.mounted) return;
    final senderDisplayName = message.senderPeerId == ownPeerId
        ? AppLocalizations.of(context)!.feed_you
        : resolveGroupSenderDisplayName(
            senderPeerId: message.senderPeerId,
            wireSenderUsername: message.senderUsername,
            member: membersByPeerId[message.senderPeerId],
            preferMemberName: true,
          );
    GroupMediaInfoSheet.show(
      context,
      attachment: attachment,
      senderDisplayName: senderDisplayName,
      sentAt: message.timestamp,
      caption: message.text,
    );
  }

  void _showFullPicker(BuildContext context, String messageId) async {
    final emoji = await showFullEmojiPicker(context);
    if (emoji != null) {
      onReactionSelected?.call(messageId, emoji);
    }
  }

  Future<void> _copyMessageText(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    // 154: copy has no persistent control (the overlay was popped before this
    // runs), so it keeps a visible cue — but a distinct, keyed quiet-confirm +
    // haptic, not the reserved error-style snackbar. Keep the live [context]
    // (the call site passes cardContext, never the popped dialogContext).
    if (!context.mounted) return;
    showQuietConfirm(
      context,
      AppLocalizations.of(context)!.conversation_context_copied,
    );
  }
}

/// The lazy list tracks this outer row across inserts and reordering. Its
/// content key also preserves media players when optional reply, private-open,
/// or highlight wrappers are added, removed, or replaced around the content.
class _GroupMessageRow extends StatefulWidget {
  final Widget content;
  final Widget Function(Widget content) decorate;

  const _GroupMessageRow({
    super.key,
    required this.content,
    required this.decorate,
  });

  @override
  State<_GroupMessageRow> createState() => _GroupMessageRowState();
}

class _GroupMessageRowState extends State<_GroupMessageRow> {
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) =>
      widget.decorate(KeyedSubtree(key: _contentKey, child: widget.content));
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

/// 159: the pure run-grouping pass for the group timeline, extracted from the
/// (Stateless) screen so the wired layer can memoize it on its State. Computes
/// run-grouping flags on the RENDERED adjacency of [messages] (already ordered
/// upstream by `orderGroupMessagesForTimeline` — never re-sorted here; replies
/// are pulled under their parent, so the order is intentionally non-monotonic).
/// `prevBreaks` is set whenever a date separator OR a system/membership row was
/// emitted since the previous message row, so the next message starts a fresh
/// run regardless of sender/gap. Returns items in reversed order (index 0 =
/// newest) for the reversed ListView.
List<GroupDisplayItem> buildGroupDisplayItems({
  required List<GroupMessage> messages,
  required AppLocalizations l10n,
  required String locale,
  required DateTime now,
}) {
  final items = <GroupDisplayItem>[];
  final emittedLabels = <String>{};

  String? prevSenderPeerId;
  DateTime? prevTimestamp;
  var prevBreaks = true; // first message always starts a run
  for (final message in messages) {
    final label = formatDaySeparatorLabel(
      message.timestamp,
      now: now,
      todayLabel: l10n.date_today,
      yesterdayLabel: l10n.date_yesterday,
      locale: locale,
    );
    if (emittedLabels.add(label)) {
      items.add(GroupDisplayItem.dateSeparator(label));
      // A date separator splits any in-progress run.
      prevBreaks = true;
    }

    // System/membership rows are ordinary GroupMessages with a `sys-` id
    // prefix; they share senderPeerId with the actor but must never be
    // absorbed into a run.
    final isSystemRow = message.id.startsWith('sys-');
    final isFirstInGroup = messageRunStartsNewRun(
      senderPeerId: message.senderPeerId,
      timestamp: message.timestamp,
      isSystemRow: isSystemRow,
      prevSenderPeerId: prevSenderPeerId,
      prevTimestamp: prevTimestamp,
      prevBreaks: prevBreaks,
    );

    items.add(
      GroupDisplayItem.message(
        message,
        isFirstInGroup: isFirstInGroup,
        // Finalized by the second pass below.
        isLastInGroup: true,
      ),
    );

    // A system row carries no run chrome and forces the NEXT message to
    // start a fresh run.
    if (isSystemRow) {
      prevBreaks = true;
      prevSenderPeerId = null;
      prevTimestamp = null;
    } else {
      prevBreaks = false;
      prevSenderPeerId = message.senderPeerId;
      prevTimestamp = message.timestamp;
    }
  }

  // Second pass (forward): a message is last-in-run when the NEXT message row
  // starts a new run, or when there is no following message row.
  int? lastMessageIndex;
  for (var i = 0; i < items.length; i++) {
    if (items[i].type != GroupDisplayItemType.message) continue;
    if (lastMessageIndex != null) {
      items[lastMessageIndex] = items[lastMessageIndex].copyWithLastInGroup(
        items[i].isFirstInGroup,
      );
    }
    lastMessageIndex = i;
  }
  if (lastMessageIndex != null) {
    items[lastMessageIndex] = items[lastMessageIndex].copyWithLastInGroup(true);
  }

  return items.reversed.toList();
}

enum GroupDisplayItemType { dateSeparator, message }

/// A single row in the group message list: either a day separator or a message.
class GroupDisplayItem {
  final GroupDisplayItemType type;
  final GroupMessage? message;
  final String? dateLabel;

  /// 136 Phase 4: whether this message row is the FIRST balloon of its run
  /// (consecutive same-sender messages within [kMessageRunGapThreshold] that
  /// are not split by a date separator or a system/membership row). Defaults
  /// true so a standalone balloon renders with full corner radii + chrome.
  final bool isFirstInGroup;

  /// 136 Phase 4: whether this message row is the LAST balloon of its run.
  final bool isLastInGroup;

  const GroupDisplayItem._({
    required this.type,
    this.message,
    this.dateLabel,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
  });

  factory GroupDisplayItem.dateSeparator(String label) => GroupDisplayItem._(
    type: GroupDisplayItemType.dateSeparator,
    dateLabel: label,
  );

  factory GroupDisplayItem.message(
    GroupMessage message, {
    bool isFirstInGroup = true,
    bool isLastInGroup = true,
  }) => GroupDisplayItem._(
    type: GroupDisplayItemType.message,
    message: message,
    isFirstInGroup: isFirstInGroup,
    isLastInGroup: isLastInGroup,
  );

  /// Returns a copy of a message item with [isLastInGroup] overridden (used by
  /// the second-pass lookahead that finalizes run-end flags).
  GroupDisplayItem copyWithLastInGroup(bool value) => GroupDisplayItem._(
    type: type,
    message: message,
    dateLabel: dateLabel,
    isFirstInGroup: isFirstInGroup,
    isLastInGroup: value,
  );
}
