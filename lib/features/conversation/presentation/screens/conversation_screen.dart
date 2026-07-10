import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/utils/format_day_separator_label.dart';
import 'package:flutter_app/core/widgets/quiet_confirm.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/utils/message_run_grouping.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/blocked_banner.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compact_origin_marker.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/empty_conversation_state.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/undelivered_messages_banner.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/full_emoji_picker.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_banner.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_system_message.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/direct_received_media_action_sheet.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

typedef ConversationMediaViewerBuilder =
    Widget Function({
      required String localPath,
      required List<String> allPaths,
      required int initialIndex,
    });

/// 231: Save/Share for one direct received attachment. The wired layer routes
/// this to the [ReceivedMediaActionController], which reloads and qualifies
/// the CURRENT row before any irreversible egress — the screen only carries
/// the stable identity.
typedef DirectReceivedMediaEgressHandler =
    Future<DirectReceivedMediaEgressOutcome> Function(
      DirectReceivedMediaActionIdentity identity,
      MediaEgressDestination destination,
    );

/// 231: current persisted Info metadata for one direct received attachment.
typedef DirectReceivedMediaInfoLoader =
    Future<DirectReceivedMediaInfo?> Function(
      DirectReceivedMediaActionIdentity identity,
    );

@immutable
class ConversationComposerViewState {
  final List<File> pendingAttachments;

  /// Indices of pending attachments that failed a size/GIF SEND policy (149).
  /// Drives the inline composer reject-chip and the Send-disable.
  final Set<int> invalidAttachmentIndices;

  /// Per-index normalized rejection reason (`too_large` | `gif_too_large`).
  final Map<int, String> invalidAttachmentReasons;

  /// True when the picked attachments are EACH individually valid but their
  /// combined size exceeds the whole-message cap (149 — group only; owns no
  /// single index). Surfaces as a strip-level note + Send-disabled.
  final bool hasTotalSizeOverflow;
  final bool isUploading;
  final bool isProcessing;
  final double processingProgress;
  final int processingCurrent;
  final int processingTotal;
  final VoiceRecordingState recordingState;
  final Duration recordingDuration;
  final List<double> amplitudeValues;

  const ConversationComposerViewState({
    this.pendingAttachments = const [],
    this.invalidAttachmentIndices = const {},
    this.invalidAttachmentReasons = const {},
    this.hasTotalSizeOverflow = false,
    this.isUploading = false,
    this.isProcessing = false,
    this.processingProgress = 0.0,
    this.processingCurrent = 0,
    this.processingTotal = 0,
    this.recordingState = VoiceRecordingState.idle,
    this.recordingDuration = Duration.zero,
    this.amplitudeValues = const [],
  });

  ConversationComposerViewState copyWith({
    List<File>? pendingAttachments,
    Set<int>? invalidAttachmentIndices,
    Map<int, String>? invalidAttachmentReasons,
    bool? hasTotalSizeOverflow,
    bool? isUploading,
    bool? isProcessing,
    double? processingProgress,
    int? processingCurrent,
    int? processingTotal,
    VoiceRecordingState? recordingState,
    Duration? recordingDuration,
    List<double>? amplitudeValues,
  }) {
    return ConversationComposerViewState(
      pendingAttachments: pendingAttachments ?? this.pendingAttachments,
      invalidAttachmentIndices:
          invalidAttachmentIndices ?? this.invalidAttachmentIndices,
      invalidAttachmentReasons:
          invalidAttachmentReasons ?? this.invalidAttachmentReasons,
      hasTotalSizeOverflow: hasTotalSizeOverflow ?? this.hasTotalSizeOverflow,
      isUploading: isUploading ?? this.isUploading,
      isProcessing: isProcessing ?? this.isProcessing,
      processingProgress: processingProgress ?? this.processingProgress,
      processingCurrent: processingCurrent ?? this.processingCurrent,
      processingTotal: processingTotal ?? this.processingTotal,
      recordingState: recordingState ?? this.recordingState,
      recordingDuration: recordingDuration ?? this.recordingDuration,
      amplitudeValues: amplitudeValues ?? this.amplitudeValues,
    );
  }

  bool get isRecording => recordingState.isActive;

  /// True when any pending attachment is rejected (per-attachment too-large/GIF)
  /// OR the whole-message total overflows — used to disable Send while an
  /// un-sendable attachment set sits in the strip.
  bool get hasInvalidAttachment =>
      invalidAttachmentIndices.isNotEmpty || hasTotalSizeOverflow;
}

/// Pure UI conversation screen.
///
/// Displays header, conversation body (empty state or letter cards),
/// and compose area. No business logic — all data passed via props.
class ConversationScreen extends StatefulWidget {
  static const editModeBannerKey = ValueKey('conversation-edit-mode-banner');
  static const cancelEditKey = ValueKey('conversation-cancel-edit-action');

  /// 159 (TC-159-03/04/03b/03c): a test-only counter incremented once per actual
  /// `_buildDisplayItems` recompute (NOT per build — the memo serves the cached
  /// list on an identical-input rebuild). Tests reset it to 0.
  @visibleForTesting
  static int debugDisplayItemsBuildCount = 0;

  final String contactPeerId;
  final String contactUsername;
  final String connectionDate;
  final String? ownPeerId;
  final List<ConversationMessage> messages;
  final ValueChanged<String> onSend;
  final VoidCallback onBack;
  final ScrollController? scrollController;
  final bool isBlocked;
  final VoidCallback? onUnblock;
  final VoidCallback? onOverflow;
  final VoidCallback? onAvatarTap;
  final bool isLoadingMore;
  final bool hasMoreOlderMessages;
  final bool initialLoadDone;
  // 145: true while the screen's notification/resume relay drain is in flight,
  // so a non-intrusive "catching up…" affordance can be shown. Distinct from
  // [isLoadingMore], which is the older-pagination (scroll-up) spinner.
  final bool isSyncingNewMessages;
  final VoidCallback? onAttach;
  final List<File> pendingAttachments;
  final bool isUploading;
  final ValueChanged<int>? onRemoveAttachment;
  final bool isProcessing;
  final bool isSending;
  final double processingProgress;
  final int processingCurrent;
  final int processingTotal;
  final bool isRecording;
  final VoiceRecordingState recordingState;
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;
  final VoidCallback? onRecordCancel;
  final VoidCallback? onReviewSend;
  final VoidCallback? onReviewDiscard;
  final Duration recordingDuration;
  final List<double> amplitudeValues;
  final ValueListenable<ConversationComposerViewState>? composerStateListenable;
  final Map<String, List<MessageReaction>> reactions;
  final void Function(String messageId, String emoji)? onReactionSelected;
  final void Function(String messageId)? onReactionPlusTap;
  final bool showIntroBanner;
  final String? bannerContactUsername;
  final UploadProgressViewState? uploadProgress;
  final VoidCallback? onCancelUpload;

  /// 172 (INV-2): count of kept-but-undisplayed staged inbox entries; > 0
  /// renders the "couldn't display N messages" affordance above the list.
  final int undeliveredCount;

  /// 172: re-drives the staged drain so a since-healed cause gets displayed.
  final VoidCallback? onRetryUndelivered;
  final VoidCallback? onMakeIntroductions;
  final VoidCallback? onMaybeLater;
  final String? initialText;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<String>? onQuoteReply;
  final ValueChanged<String>? onRetryFailedMessage;
  final ValueChanged<String>? onRetryFailedMedia;
  final ValueChanged<String>? onDeleteFailedMedia;
  final Future<void> Function(String messageId, String attachmentId)?
  onRetryUnavailableMedia;
  final ValueChanged<String>? onDeleteMessage;
  final String? activeQuoteText;
  final bool isActiveQuoteUnavailable;
  final VoidCallback? onClearQuote;
  final ValueChanged<String>? onEditMessage;
  final bool isEditingMessage;
  final VoidCallback? onCancelEdit;
  final bool allowEditAction;
  final ConversationMediaViewerBuilder? mediaViewerBuilder;
  final BackgroundPreference backgroundPreference;

  /// 231: direct received-media core actions. All three are optional; when
  /// none is provided the media tiles keep their pre-231 behavior (tap-to-view
  /// only, row-level long press).
  final DirectReceivedMediaEgressHandler? onMediaEgress;
  final DirectReceivedMediaInfoLoader? onLoadMediaInfo;

  /// Whole-message Delete for Me initiated from a media surface — the wired
  /// layer labels the confirmation as message+attachments removal.
  final ValueChanged<String>? onDeleteMediaMessage;

  const ConversationScreen({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    required this.connectionDate,
    this.ownPeerId,
    required this.messages,
    required this.onSend,
    required this.onBack,
    this.scrollController,
    this.isBlocked = false,
    this.onUnblock,
    this.onOverflow,
    this.onAvatarTap,
    this.isLoadingMore = false,
    this.hasMoreOlderMessages = true,
    this.initialLoadDone = false,
    this.isSyncingNewMessages = false,
    this.onAttach,
    this.pendingAttachments = const [],
    this.isUploading = false,
    this.onRemoveAttachment,
    this.isProcessing = false,
    this.isSending = false,
    this.processingProgress = 0.0,
    this.processingCurrent = 0,
    this.processingTotal = 0,
    this.isRecording = false,
    this.recordingState = VoiceRecordingState.idle,
    this.onRecordStart,
    this.onRecordStop,
    this.onRecordCancel,
    this.onReviewSend,
    this.onReviewDiscard,
    this.recordingDuration = Duration.zero,
    this.amplitudeValues = const [],
    this.composerStateListenable,
    this.reactions = const {},
    this.onReactionSelected,
    this.onReactionPlusTap,
    this.showIntroBanner = false,
    this.bannerContactUsername,
    this.uploadProgress,
    this.onCancelUpload,
    this.undeliveredCount = 0,
    this.onRetryUndelivered,
    this.onMakeIntroductions,
    this.onMaybeLater,
    this.initialText,
    this.onDraftChanged,
    this.onQuoteReply,
    this.onRetryFailedMessage,
    this.onRetryFailedMedia,
    this.onDeleteFailedMedia,
    this.onRetryUnavailableMedia,
    this.onDeleteMessage,
    this.activeQuoteText,
    this.isActiveQuoteUnavailable = false,
    this.onClearQuote,
    this.onEditMessage,
    this.isEditingMessage = false,
    this.onCancelEdit,
    this.allowEditAction = true,
    this.mediaViewerBuilder,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
    this.onMediaEgress,
    this.onLoadMediaInfo,
    this.onDeleteMediaMessage,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  bool _wasEmpty = true;
  bool _shouldRequestComposerFocus = false;

  // 159 (main-isolate-blocking-1): memoize the O(N) two-pass run-grouping so an
  // identical-input rebuild (a status flip elsewhere, a banner toggle, an
  // unrelated setState) reuses the cached list instead of re-running the whole
  // pass. The key is list-reference identity (the wired layer reallocates
  // `widget.messages` on ANY content change — an edit/status flip/insert yields
  // a new ref, invalidating for free) PLUS the scalars the ref does NOT capture:
  // `_wasEmpty` (entrance flag), pagination flags, and the locale + today-token
  // that drive the day-separator labels (`_formatDateLabel` reads both).
  List<_DisplayItem>? _cachedDisplayItems;
  List<ConversationMessage>? _cachedMessagesRef;
  bool? _cachedWasEmpty;
  bool? _cachedHasMoreOlderMessages;
  bool? _cachedIsLoadingMore;
  String? _cachedLocale;
  String? _cachedTodayToken;

  ConversationComposerViewState get _legacyComposerState =>
      ConversationComposerViewState(
        pendingAttachments: widget.pendingAttachments,
        isUploading: widget.isUploading,
        isProcessing: widget.isProcessing,
        processingProgress: widget.processingProgress,
        processingCurrent: widget.processingCurrent,
        processingTotal: widget.processingTotal,
        recordingState: widget.recordingState != VoiceRecordingState.idle
            ? widget.recordingState
            : (widget.isRecording
                  ? VoiceRecordingState.recording
                  : VoiceRecordingState.idle),
        recordingDuration: widget.recordingDuration,
        amplitudeValues: widget.amplitudeValues,
      );

  @override
  void didUpdateWidget(ConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.isEmpty && widget.messages.isNotEmpty) {
      _wasEmpty = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      preference: widget.backgroundPreference,
      isChatSurface: true,
      child: Column(
        children: [
          // Header
          ConversationHeader(
            contactPeerId: widget.contactPeerId,
            contactUsername: widget.contactUsername,
            connectionDate: widget.connectionDate,
            onBack: widget.onBack,
            onOverflow: widget.onOverflow,
            onAvatarTap: widget.onAvatarTap,
          ),
          // Intro banner above messages (when messages exist)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child:
                widget.showIntroBanner &&
                    widget.messages.isNotEmpty &&
                    widget.onMakeIntroductions != null
                ? Padding(
                    key: const ValueKey('intro-banner'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: IntroBanner(
                      contactUsername:
                          widget.bannerContactUsername ??
                          widget.contactUsername,
                      onMakeIntroductions: widget.onMakeIntroductions!,
                      onMaybeLater: widget.onMaybeLater ?? () {},
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('no-banner')),
          ),
          if (widget.uploadProgress != null)
            UploadProgressBanner(
              state: widget.uploadProgress!,
              onCancel: widget.onCancelUpload,
            ),
          // 172 (INV-2): kept-but-undisplayed staged entries are surfaced, not
          // silently invisible. Outside the ListView so it never shifts scroll.
          if (widget.undeliveredCount > 0)
            UndeliveredMessagesBanner(
              count: widget.undeliveredCount,
              onRetry: widget.onRetryUndelivered,
            ),
          // 145: "catching up…" affordance shown while the relay drain is in
          // flight. Outside the message ListView so it never shifts the scroll
          // position; distinct from the older-pagination spinner.
          if (widget.isSyncingNewMessages) const _ConversationSyncingBanner(),
          // Body with animated transition
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: widget.messages.isEmpty
                  ? _buildEmptyOrLoadingState()
                  : _buildMessageList(),
            ),
          ),
          if (widget.composerStateListenable == null)
            _buildComposerSection(_legacyComposerState)
          else
            ValueListenableBuilder<ConversationComposerViewState>(
              valueListenable: widget.composerStateListenable!,
              builder: (context, composerState, child) =>
                  _buildComposerSection(composerState),
            ),
        ],
      ),
    );
  }

  Widget _buildComposerSection(ConversationComposerViewState composerState) {
    if (widget.isBlocked) {
      return BlockedBanner(onUnblock: widget.onUnblock);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
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
            onRemove: widget.onRemoveAttachment,
          ),
        if (widget.isEditingMessage && widget.onCancelEdit != null)
          _EditModeBanner(
            key: ConversationScreen.editModeBannerKey,
            onCancel: widget.onCancelEdit!,
          ),
        ComposeArea(
          onSend: widget.onSend,
          onAttach: widget.onAttach,
          hasAttachments: composerState.pendingAttachments.isNotEmpty,
          hasInvalidAttachment: composerState.hasInvalidAttachment,
          isProcessing: composerState.isProcessing,
          isSending: widget.isSending,
          recordingState: composerState.recordingState,
          onRecordStart: widget.onRecordStart,
          onRecordStop: widget.onRecordStop,
          onRecordCancel: widget.onRecordCancel,
          onReviewSend: widget.onReviewSend,
          onReviewDiscard: widget.onReviewDiscard,
          recordingDuration: composerState.recordingDuration,
          amplitudeValues: composerState.amplitudeValues,
          initialText: widget.initialText,
          onDraftChanged: widget.onDraftChanged,
          quotedText: widget.activeQuoteText,
          isQuoteUnavailable: widget.isActiveQuoteUnavailable,
          onClearQuote: widget.onClearQuote,
          shouldRequestFocus: _shouldRequestComposerFocus,
        ),
      ],
    );
  }

  Widget _buildEmptyOrLoadingState() {
    if (!widget.initialLoadDone) {
      return const _ConversationLoadingShell();
    }
    if (widget.showIntroBanner && widget.onMakeIntroductions != null) {
      return Column(
        key: const ValueKey('empty-with-banner'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: IntroBanner(
              contactUsername:
                  widget.bannerContactUsername ?? widget.contactUsername,
              onMakeIntroductions: widget.onMakeIntroductions!,
              onMaybeLater: widget.onMaybeLater ?? () {},
            ),
          ),
          Expanded(
            child: EmptyConversationState(
              contactPeerId: widget.contactPeerId,
              connectionDate: widget.connectionDate,
            ),
          ),
        ],
      );
    }
    return EmptyConversationState(
      key: const ValueKey('empty'),
      contactPeerId: widget.contactPeerId,
      connectionDate: widget.connectionDate,
    );
  }

  Widget _buildMessageList() {
    final displayItems = _buildDisplayItems();

    // 156 QW-10 (lists-scrolling-1): build the quoted-parent lookup ONCE per
    // frame instead of an O(N) `widget.messages.where(...)` scan per visible row.
    final messagesById = <String, ConversationMessage>{
      for (final m in widget.messages) m.id: m,
    };

    // 156 QW-12 (lists-scrolling-3): construct the localized time formatter ONCE
    // per frame instead of `intl.DateFormat.jm(locale)` + `Localizations.localeOf`
    // per visible row.
    final timeFormat = intl.DateFormat.jm(
      Localizations.localeOf(context).toString(),
    );
    String formatTime(String isoTimestamp) {
      try {
        return timeFormat.format(DateTime.parse(isoTimestamp).toLocal());
      } catch (_) {
        return '';
      }
    }

    return ListView.builder(
      key: const ValueKey('messages'),
      controller: widget.scrollController,
      reverse: true,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: displayItems.length,
      itemBuilder: (context, index) {
        final item = displayItems[index];
        switch (item.type) {
          case _ItemType.originMarker:
            return CompactOriginMarker(
              contactPeerId: widget.contactPeerId,
              connectionDate: widget.connectionDate,
            );
          case _ItemType.dateSeparator:
            return DateSeparator(label: item.dateLabel!);
          case _ItemType.loadingIndicator:
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color.fromRGBO(255, 255, 255, 0.3),
                  ),
                ),
              ),
            );
          case _ItemType.message:
            final message = item.message!;
            final isNew = item.isLastAndWasEmpty;

            // System messages render as centered muted bubbles
            if (message.transport == 'system') {
              return Padding(
                key: ValueKey('msg-${message.id}'),
                padding: const EdgeInsets.only(bottom: 16),
                child: IntroSystemMessage(text: message.text),
              );
            }

            final l10n = AppLocalizations.of(context)!;
            // Resolve quoted message text
            String? quotedText;
            bool isQuoteUnavailable = false;
            if (!message.isDeleted && message.quotedMessageId != null) {
              final quoted = messagesById[message.quotedMessageId];
              if (quoted != null) {
                if (quoted.isDeleted ||
                    (quoted.text.isEmpty && quoted.media.isEmpty)) {
                  isQuoteUnavailable = true;
                } else if (quoted.text.isNotEmpty) {
                  quotedText = quoted.text;
                } else if (quoted.media.isNotEmpty) {
                  quotedText = mediaPreviewText(quoted.media);
                }
              } else {
                isQuoteUnavailable = true;
              }
            }

            final messageReactions = widget.reactions[message.id] ?? const [];
            final hasRetryableFailedMedia =
                message.media.isNotEmpty &&
                message.media.any(
                  (attachment) =>
                      attachment.downloadStatus != 'upload_cancelled',
                );
            final showFailedMediaActions =
                !message.isDeleted &&
                !message.isIncoming &&
                message.status == 'failed' &&
                hasRetryableFailedMedia;
            final showFailedTextRetry =
                !message.isDeleted &&
                !message.isIncoming &&
                message.status == 'failed' &&
                message.media.isEmpty &&
                message.text.trim().isNotEmpty &&
                widget.onRetryFailedMessage != null;
            final canOpenContextOverlay = !message.isDeleted;
            final displayText = message.isDeleted
                ? l10n.conversation_message_deleted
                : message.text;
            final mediaTapHandler = (int index) {
              final visual = message.media
                  .where(
                    (a) => a.mediaType == 'image' || a.mediaType == 'video',
                  )
                  .toList();
              if (index < visual.length && visual[index].localPath != null) {
                final mediaViewerBuilder = widget.mediaViewerBuilder;
                if (mediaViewerBuilder != null) {
                  // Injected builder (test seam / legacy path-based viewer).
                  final allPaths = visual
                      .where(
                        (a) =>
                            a.localPath != null && a.downloadStatus == 'done',
                      )
                      .map((a) => a.localPath!)
                      .toList();
                  final tappedPath = visual[index].localPath!;
                  final startIndex = allPaths
                      .indexOf(tappedPath)
                      .clamp(0, allPaths.length - 1);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => mediaViewerBuilder(
                        localPath: tappedPath,
                        allPaths: allPaths,
                        initialIndex: startIndex,
                      ),
                    ),
                  );
                  return;
                }
                // 231: message-bounded typed viewer carrying stable
                // attachment/message identity and the direct-lane action
                // capabilities (plan 230 surface).
                _openDirectMediaViewer(message, visual, index);
              }
            };

            LetterCard buildLetterCard({
              VoidCallback? onLongPress,
              void Function(int index)? onMediaLongPress,
            }) {
              return LetterCard(
                onMediaLongPress: onMediaLongPress,
                senderPeerId: message.senderPeerId,
                senderName: message.isIncoming ? widget.contactUsername : 'You',
                text: displayText,
                time: formatTime(message.timestamp),
                isIncoming: message.isIncoming,
                // 136 Phase 3: render as a side-aligned chat balloon and group
                // consecutive same-sender messages into one run. 1:1 NEVER
                // shows an avatar or a sender name (showAvatar/showSenderName
                // false in both directions).
                bubbleLayout: true,
                isFirstInGroup: item.isFirstInGroup,
                isLastInGroup: item.isLastInGroup,
                showAvatar: false,
                showSenderName: false,
                // 155: on 1:1 the inline glyph reflects the TRANSPORT the
                // message travelled (own outgoing AND received). Group keeps v1.
                transportStatusGlyph: true,
                status: message.isIncoming ? null : message.status,
                transport: message.transport,
                quotedText: quotedText,
                isQuoteUnavailable: isQuoteUnavailable,
                isEdited: message.editedAt != null && !message.isDeleted,
                isDeleted: message.isDeleted,
                media: message.media,
                reactions: message.isDeleted ? const [] : messageReactions,
                ownPeerId: widget.ownPeerId,
                onLongPress: onLongPress,
                onReactionTap:
                    !message.isDeleted && widget.onReactionSelected != null
                    ? (emoji) => widget.onReactionSelected!(message.id, emoji)
                    : null,
                onRetryFailedMessage: showFailedTextRetry
                    ? () => widget.onRetryFailedMessage!(message.id)
                    : null,
                onRetryFailedMedia:
                    showFailedMediaActions && widget.onRetryFailedMedia != null
                    ? () => widget.onRetryFailedMedia!(message.id)
                    : null,
                failedMessageActionKeySuffix: message.id,
                onDeleteFailedMedia:
                    showFailedMediaActions && widget.onDeleteFailedMedia != null
                    ? () => widget.onDeleteFailedMedia!(message.id)
                    : null,
                failedMediaActionKeySuffix: message.id,
                onRetryUnavailableMedia: widget.onRetryUnavailableMedia != null
                    ? (attachmentId) => widget.onRetryUnavailableMedia!(
                        message.id,
                        attachmentId,
                      )
                    : null,
                onMediaTap: mediaTapHandler,
                // 128 (round 5): the durable owned media copy is keyed under the
                // conversation contact peerId — lets the render gate fall back to
                // it when the in-memory display path is stale/transient.
                ownedMediaPeerId: widget.contactPeerId,
              );
            }

            final letterCard = Builder(
              builder: (cardContext) => buildLetterCard(
                onLongPress: canOpenContextOverlay
                    ? () => _showMessageContextOverlay(
                        message,
                        cardContext: cardContext,
                        selectedMessage: buildLetterCard(),
                      )
                    : null,
                // 231: tile long-press carries the exact attachment. An
                // ineligible tile (outgoing/unresolved/not-done) falls back
                // to the plain whole-message context inside the handler.
                onMediaLongPress:
                    canOpenContextOverlay && _hasDirectMediaActionSurface
                    ? (visualIndex) => _onMediaCellLongPress(
                        message,
                        visualIndex,
                        cardContext: cardContext,
                        selectedMessage: buildLetterCard(),
                      )
                    : null,
              ),
            );

            // 156 QW-11 (lists-scrolling-4): entrance-animate ONLY a genuinely
            // new (appended) message, not every row on the initial paint.
            final shouldAnimate = isNew;
            Widget bubble = shouldAnimate
                ? _AnimatedLetterCard(
                    key: ValueKey(message.id),
                    delayMs: 0,
                    isNewMessage: isNew,
                    child: letterCard,
                  )
                : letterCard;

            // 136 Phase 3: swipe-to-reply is enabled on EVERY balloon in BOTH
            // directions (outgoing balloons now get the gesture too).
            if (!message.isDeleted && widget.onQuoteReply != null) {
              bubble = SwipeToQuoteBubble(
                onQuoteTriggered: () => widget.onQuoteReply!(message.id),
                child: bubble,
              );
            }

            return Padding(
              key: ValueKey('msg-${message.id}'),
              // 137 follow-up: tight gap within a run (so the stacked corner
              // radii read as one connected group), larger gap between runs.
              padding: EdgeInsets.only(
                bottom: messageRunBottomSpacing(
                  isLastInGroup: item.isLastInGroup,
                  runSeparation: 16,
                ),
              ),
              child: bubble,
            );
        }
      },
    );
  }

  /// Builds display items in forward chronological order, then reverses
  /// for the reversed ListView (index 0 = bottom = newest).
  ///
  /// 159: memoized on [_ConversationScreenState]. Recomputes ONLY when a
  /// run-affecting input changes (the `widget.messages` reference, `_wasEmpty`,
  /// the pagination flags, the locale, or the day token); otherwise returns the
  /// cached list instance unchanged.
  List<_DisplayItem> _buildDisplayItems() {
    final locale = Localizations.localeOf(context).toString();
    final todayToken = _todayToken();
    final cached = _cachedDisplayItems;
    if (cached != null &&
        identical(widget.messages, _cachedMessagesRef) &&
        _cachedWasEmpty == _wasEmpty &&
        _cachedHasMoreOlderMessages == widget.hasMoreOlderMessages &&
        _cachedIsLoadingMore == widget.isLoadingMore &&
        _cachedLocale == locale &&
        _cachedTodayToken == todayToken) {
      return cached;
    }
    ConversationScreen.debugDisplayItemsBuildCount++;

    final items = <_DisplayItem>[];

    // Top of conversation markers (will appear at scroll-top)
    if (!widget.hasMoreOlderMessages) {
      items.add(_DisplayItem.originMarker());
    }
    if (widget.isLoadingMore) {
      items.add(_DisplayItem.loadingIndicator());
    }

    // Messages with date separators.
    //
    // 136 Phase 3: compute run-grouping flags on the FORWARD (chronological)
    // list, before the final `.reversed`. `prevBreaks` is set whenever a date
    // separator OR a system row was emitted since the previous message row, so
    // the next message starts a fresh run regardless of sender/gap.
    String? lastDateLabel;
    String? prevSenderPeerId;
    DateTime? prevTimestamp;
    var prevBreaks = true; // first message always starts a run
    for (var i = 0; i < widget.messages.length; i++) {
      final message = widget.messages[i];
      final dateLabel = _formatDateLabel(message.timestamp);

      if (dateLabel != lastDateLabel) {
        items.add(_DisplayItem.dateSeparator(dateLabel));
        lastDateLabel = dateLabel;
        // A date separator splits any in-progress run.
        prevBreaks = true;
      }

      final isSystemRow = message.transport == 'system';
      // 159: consume the model-cached parsed DateTime instead of re-parsing the
      // ISO string on every grouping pass (parse now runs once per memo
      // recompute, not once per rebuild).
      final parsedTs = message.parsedTimestamp;
      final isFirstInGroup = messageRunStartsNewRun(
        senderPeerId: message.senderPeerId,
        // Parse failure → null timestamp → helper fails safe to a run break.
        timestamp: parsedTs ?? DateTime.fromMillisecondsSinceEpoch(0),
        isSystemRow: isSystemRow,
        prevSenderPeerId: prevSenderPeerId,
        prevTimestamp: prevTimestamp,
        prevBreaks: prevBreaks,
      );

      final isNew = i == widget.messages.length - 1 && _wasEmpty;
      items.add(
        _DisplayItem.message(
          message,
          isLastAndWasEmpty: isNew,
          isFirstInGroup: isFirstInGroup,
          // Finalized by the second pass below.
          isLastInGroup: true,
        ),
      );

      // A system row carries no run chrome (it renders via IntroSystemMessage)
      // and forces the NEXT message to start a fresh run.
      if (isSystemRow) {
        prevBreaks = true;
        prevSenderPeerId = null;
        prevTimestamp = null;
      } else {
        prevBreaks = false;
        prevSenderPeerId = message.senderPeerId;
        prevTimestamp = parsedTs;
      }
    }

    // Second pass (forward): a message is last-in-run when the NEXT message row
    // starts a new run, or when there is no following message row.
    int? lastMessageIndex;
    for (var i = 0; i < items.length; i++) {
      if (items[i].type != _ItemType.message) continue;
      if (lastMessageIndex != null) {
        // The previously seen message is last-in-run iff the current message
        // starts a new run.
        items[lastMessageIndex] = items[lastMessageIndex].copyWithLastInGroup(
          items[i].isFirstInGroup,
        );
      }
      lastMessageIndex = i;
    }
    if (lastMessageIndex != null) {
      // The final message row is always last-in-run.
      items[lastMessageIndex] = items[lastMessageIndex].copyWithLastInGroup(
        true,
      );
    }

    // Reset transition state after build
    if (_wasEmpty && widget.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _wasEmpty = false;
      });
    }

    final result = items.reversed.toList();
    _cachedDisplayItems = result;
    _cachedMessagesRef = widget.messages;
    _cachedWasEmpty = _wasEmpty;
    _cachedHasMoreOlderMessages = widget.hasMoreOlderMessages;
    _cachedIsLoadingMore = widget.isLoadingMore;
    _cachedLocale = locale;
    _cachedTodayToken = todayToken;
    return result;
  }

  /// 159: a per-day token (`YYYY-M-D`) folded into the grouping memo key so the
  /// day-separator labels ("Today"/"Yesterday", `_formatDateLabel` reads
  /// `DateTime.now()`) re-localize correctly on the next rebuild after a midnight
  /// rollover instead of serving a stale cached label.
  String _todayToken() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  void _showMessageContextOverlay(
    ConversationMessage message, {
    required BuildContext cardContext,
    required Widget selectedMessage,
    MediaAttachment? mediaTarget,
  }) {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final renderObject = cardContext.findRenderObject();
    Rect anchorRect = Rect.fromCenter(
      center: MediaQuery.of(context).size.center(Offset.zero),
      width: 0,
      height: 0,
    );
    if (renderObject is RenderBox && renderObject.hasSize) {
      final topLeft = renderObject.localToGlobal(Offset.zero);
      anchorRect = topLeft & renderObject.size;
    }

    final reactions = widget.reactions[message.id] ?? [];
    final ownReaction = widget.ownPeerId != null
        ? reactions.where((r) => r.senderPeerId == widget.ownPeerId).firstOrNull
        : null;
    final hasEditAction = _canEditMessage(message);
    final hasCopyAction = !message.isDeleted && message.text.trim().isNotEmpty;
    final hasDeleteAction = _canDeleteMessage(message);
    // 231: received-media entries for the exact long-pressed eligible
    // attachment. On a media-targeted overlay, Delete routes to the
    // media-labeled whole-message confirmation.
    final mediaIdentity = mediaTarget == null
        ? null
        : DirectReceivedMediaActionIdentity(
            messageId: message.id,
            attachmentId: mediaTarget.id,
          );
    final showSaveAction = mediaIdentity != null && widget.onMediaEgress != null;
    final showShareAction = showSaveAction;
    final showInfoAction =
        mediaIdentity != null && widget.onLoadMediaInfo != null;
    final showMediaDeleteAction =
        mediaIdentity != null && widget.onDeleteMediaMessage != null;

    showDialog(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => MessageContextOverlay(
        anchorRect: anchorRect,
        selectedMessage: selectedMessage,
        currentEmoji: ownReaction?.emoji,
        showEditAction: hasEditAction,
        showCopyAction: hasCopyAction,
        showSaveAction: showSaveAction,
        showShareAction: showShareAction,
        showInfoAction: showInfoAction,
        showDeleteAction: mediaIdentity != null
            ? showMediaDeleteAction
            : hasDeleteAction,
        onDismiss: () => Navigator.of(dialogContext).pop(),
        onReactionSelected: (emoji) {
          Navigator.of(dialogContext).pop();
          widget.onReactionSelected?.call(message.id, emoji);
        },
        onPlusTap: () {
          Navigator.of(dialogContext).pop();
          _showFullPicker(message.id);
        },
        onReplyTap: () {
          Navigator.of(dialogContext).pop();
          _handleReplyAction(message.id);
        },
        onEditTap: hasEditAction
            ? () {
                Navigator.of(dialogContext).pop();
                _handleEditAction(message.id);
              }
            : null,
        onCopyTap: hasCopyAction
            ? () async {
                Navigator.of(dialogContext).pop();
                await _copyMessageText(message.text);
              }
            : null,
        onSaveTap: showSaveAction
            ? () {
                Navigator.of(dialogContext).pop();
                unawaited(_promptSaveDestinationAndPerform(mediaIdentity));
              }
            : null,
        onShareTap: showShareAction
            ? () {
                Navigator.of(dialogContext).pop();
                unawaited(
                  _performMediaEgressWithFeedback(
                    mediaIdentity,
                    MediaEgressDestination.share,
                  ),
                );
              }
            : null,
        onInfoTap: showInfoAction
            ? () {
                Navigator.of(dialogContext).pop();
                unawaited(_showDirectMediaInfo(mediaIdentity));
              }
            : null,
        onDeleteTap: mediaIdentity != null
            ? (showMediaDeleteAction
                  ? () {
                      Navigator.of(dialogContext).pop();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        widget.onDeleteMediaMessage?.call(message.id);
                      });
                    }
                  : null)
            : (hasDeleteAction
                  ? () {
                      Navigator.of(dialogContext).pop();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        widget.onDeleteMessage?.call(message.id);
                      });
                    }
                  : null),
      ),
    );
  }

  /// 231: whether any direct received-media action surface is wired.
  bool get _hasDirectMediaActionSurface =>
      widget.onMediaEgress != null ||
      widget.onLoadMediaInfo != null ||
      widget.onDeleteMediaMessage != null;

  /// 231: an attachment may surface media actions only when its CURRENT
  /// display state is an incoming, live, direct-owned, completed visual with
  /// bytes on disk. Missing or unresolved ownership yields no action-bearing
  /// surface (fail closed) — and the controller re-verifies durable state
  /// again immediately before any egress.
  bool _isDirectMediaActionEligible(
    ConversationMessage message,
    MediaAttachment attachment,
  ) {
    if (message.isDeleted || !message.isIncoming) return false;
    if (message.transport == 'system') return false;
    if (attachment.ownerLane != MediaOwnerLane.direct) return false;
    if (attachment.mediaType != 'image' && attachment.mediaType != 'video') {
      return false;
    }
    if (attachment.downloadStatus != kMediaDownloadStatusDone) return false;
    final localPath = attachment.localPath;
    if (localPath == null || localPath.isEmpty) return false;
    return File(MediaFileManager.resolveStoredPathSync(localPath)).existsSync();
  }

  void _onMediaCellLongPress(
    ConversationMessage message,
    int visualIndex, {
    required BuildContext cardContext,
    required Widget selectedMessage,
  }) {
    final visual = message.media
        .where((a) => a.mediaType == 'image' || a.mediaType == 'video')
        .toList();
    if (visualIndex < 0 || visualIndex >= visual.length) return;
    final attachment = visual[visualIndex];
    _showMessageContextOverlay(
      message,
      cardContext: cardContext,
      selectedMessage: selectedMessage,
      mediaTarget: _isDirectMediaActionEligible(message, attachment)
          ? attachment
          : null,
    );
  }

  /// 231: message-bounded typed viewer over the tapped message's completed
  /// visual attachments. Never concatenates other messages' media —
  /// conversation-wide navigation is plan 233.
  void _openDirectMediaViewer(
    ConversationMessage message,
    List<MediaAttachment> visual,
    int tappedIndex,
  ) {
    final viewable = visual
        .where(
          (a) =>
              a.localPath != null &&
              a.downloadStatus == kMediaDownloadStatusDone,
        )
        .toList();
    if (viewable.isEmpty) return;
    final tappedId = visual[tappedIndex].id;
    var initialIndex = viewable.indexWhere((a) => a.id == tappedId);
    if (initialIndex < 0) initialIndex = 0;
    final items = [
      for (final attachment in viewable)
        _buildDirectViewerItem(message, attachment),
    ];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenTypedMediaViewer(
          items: items,
          initialIndex: initialIndex,
          onAction: (item, action) => _handleViewerAction(item, action),
        ),
      ),
    );
  }

  MediaViewerItem _buildDirectViewerItem(
    ConversationMessage message,
    MediaAttachment attachment,
  ) {
    final localPath = attachment.localPath;
    final resolvedPath = localPath == null || localPath.isEmpty
        ? null
        : MediaFileManager.resolveStoredPathSync(localPath);
    final hasBytes = resolvedPath != null && File(resolvedPath).existsSync();
    final kind = attachment.mediaType == 'video'
        ? MediaViewerKind.video
        : attachment.isAnimated
        ? MediaViewerKind.gif
        : MediaViewerKind.image;
    final allowed = <MediaViewerAction>{};
    if (_isDirectMediaActionEligible(message, attachment)) {
      if (widget.onMediaEgress != null) {
        allowed.add(MediaViewerAction.save);
        allowed.add(MediaViewerAction.share);
      }
      if (widget.onQuoteReply != null) allowed.add(MediaViewerAction.reply);
      if (widget.onLoadMediaInfo != null) allowed.add(MediaViewerAction.info);
      if (widget.onDeleteMediaMessage != null) {
        allowed.add(MediaViewerAction.delete);
      }
    }
    return MediaViewerItem(
      attachmentId: attachment.id,
      messageId: message.id,
      kind: kind,
      mime: attachment.mime,
      // Only a trusted direct owner is forwarded; anything else (unresolved
      // legacy rows, foreign lanes) stays ownerless and action-ineligible.
      owner: attachment.ownerLane == MediaOwnerLane.direct
          ? MediaOwnerLane.direct
          : null,
      localPath: resolvedPath,
      sizeBytes: attachment.size,
      width: attachment.width,
      height: attachment.height,
      durationMs: attachment.durationMs,
      caption: message.isDeleted || message.text.trim().isEmpty
          ? null
          : message.text,
      senderLabel: message.isIncoming ? widget.contactUsername : null,
      timestamp: message.parsedTimestamp,
      protection: MediaViewerProtection(
        isDownloaded:
            attachment.downloadStatus == kMediaDownloadStatusDone && hasBytes,
        isIntegrityVerified:
            attachment.downloadStatus != kMediaDownloadStatusIntegrityFailed,
      ),
      capabilities: MediaViewerActionCapabilities(allowed: allowed),
    );
  }

  Future<MediaViewerActionResult> _handleViewerAction(
    MediaViewerItem item,
    MediaViewerAction action,
  ) async {
    final identity = DirectReceivedMediaActionIdentity(
      messageId: item.messageId,
      attachmentId: item.attachmentId,
    );
    switch (action) {
      case MediaViewerAction.save:
        final destination = await DirectMediaSaveDestinationSheet.show(
          context,
        );
        if (!mounted || destination == null) {
          return MediaViewerActionResult.cancelled;
        }
        return _viewerEgressResult(
          await _performMediaEgress(identity, destination),
        );
      case MediaViewerAction.share:
        return _viewerEgressResult(
          await _performMediaEgress(identity, MediaEgressDestination.share),
        );
      case MediaViewerAction.reply:
        if (!mounted) return MediaViewerActionResult.failure;
        // Close the viewer route, then quote the OWNING message.
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _handleReplyAction(item.messageId);
        });
        return MediaViewerActionResult.success;
      case MediaViewerAction.info:
        await _showDirectMediaInfo(identity);
        return MediaViewerActionResult.success;
      case MediaViewerAction.delete:
        if (!mounted || widget.onDeleteMediaMessage == null) {
          return MediaViewerActionResult.failure;
        }
        // Close the viewer first; the wired layer owns the one
        // Delete-for-Me confirmation and the existing whole-message cleanup.
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.onDeleteMediaMessage?.call(item.messageId);
        });
        return MediaViewerActionResult.success;
      case MediaViewerAction.forward:
      case MediaViewerAction.bookmark:
        // Plans 232/233 own these; the direct lane never authorizes them.
        return MediaViewerActionResult.failure;
    }
  }

  Future<DirectReceivedMediaEgressOutcome?> _performMediaEgress(
    DirectReceivedMediaActionIdentity identity,
    MediaEgressDestination destination,
  ) async {
    final handler = widget.onMediaEgress;
    if (handler == null) return null;
    return handler(identity, destination);
  }

  Future<void> _promptSaveDestinationAndPerform(
    DirectReceivedMediaActionIdentity identity,
  ) async {
    final destination = await DirectMediaSaveDestinationSheet.show(context);
    if (!mounted || destination == null) return;
    await _performMediaEgressWithFeedback(identity, destination);
  }

  Future<void> _performMediaEgressWithFeedback(
    DirectReceivedMediaActionIdentity identity,
    MediaEgressDestination destination,
  ) async {
    final outcome = await _performMediaEgress(identity, destination);
    if (!mounted || outcome == null) return;
    _showMediaFeedback(_egressOutcomeCopy(outcome));
  }

  void _showMediaFeedback(String copy) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(copy), behavior: SnackBarBehavior.floating),
      );
  }

  /// Typed outcome → user copy. Denials and structural rejects surface as
  /// truthful unavailability; nothing here retries or mutates the source.
  String _egressOutcomeCopy(DirectReceivedMediaEgressOutcome outcome) {
    final l10n = AppLocalizations.of(context)!;
    if (outcome.wasDenied) return l10n.media_egress_result_unavailable;
    final result = outcome.result!;
    switch (result.outcome) {
      case MediaEgressOutcome.saved:
      case MediaEgressOutcome.partial:
        return l10n.media_egress_result_saved;
      case MediaEgressOutcome.presented:
        return l10n.media_egress_result_shared;
      case MediaEgressOutcome.cancelled:
        return l10n.media_egress_result_cancelled;
      case MediaEgressOutcome.permissionDenied:
        return l10n.media_egress_result_permission_denied;
      case MediaEgressOutcome.rejected:
        final allMissing =
            result.items.isNotEmpty &&
            result.items.every(
              (item) => item.outcome == MediaEgressItemOutcome.missingFile,
            );
        return allMissing
            ? l10n.media_egress_result_missing
            : l10n.media_egress_result_unavailable;
      case MediaEgressOutcome.busy:
      case MediaEgressOutcome.platformFailure:
        return l10n.media_egress_result_failed;
    }
  }

  MediaViewerActionResult _viewerEgressResult(
    DirectReceivedMediaEgressOutcome? outcome,
  ) {
    if (outcome == null || outcome.wasDenied) {
      return MediaViewerActionResult.failure;
    }
    switch (outcome.result!.outcome) {
      case MediaEgressOutcome.saved:
      case MediaEgressOutcome.partial:
      case MediaEgressOutcome.presented:
        return MediaViewerActionResult.success;
      case MediaEgressOutcome.cancelled:
        return MediaViewerActionResult.cancelled;
      case MediaEgressOutcome.busy:
      case MediaEgressOutcome.permissionDenied:
      case MediaEgressOutcome.rejected:
      case MediaEgressOutcome.platformFailure:
        return MediaViewerActionResult.failure;
    }
  }

  /// 231: local Info from persisted metadata — no transport reads. A stale
  /// identity (row/parent gone) surfaces truthful unavailability.
  Future<void> _showDirectMediaInfo(
    DirectReceivedMediaActionIdentity identity,
  ) async {
    final loader = widget.onLoadMediaInfo;
    if (loader == null) return;
    final info = await loader(identity);
    if (!mounted) return;
    if (info == null) {
      _showMediaFeedback(
        AppLocalizations.of(context)!.media_egress_result_unavailable,
      );
      return;
    }
    await DirectReceivedMediaInfoSheet.show(
      context,
      info: info,
      senderLabel: info.isIncoming ? widget.contactUsername : 'You',
    );
  }

  void _handleReplyAction(String messageId) {
    widget.onQuoteReply?.call(messageId);
    _requestComposerFocus();
  }

  void _handleEditAction(String messageId) {
    widget.onEditMessage?.call(messageId);
    _requestComposerFocus();
  }

  void _requestComposerFocus() {
    if (!mounted) return;
    setState(() => _shouldRequestComposerFocus = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_shouldRequestComposerFocus) return;
      setState(() => _shouldRequestComposerFocus = false);
    });
  }

  bool _canEditMessage(ConversationMessage message) {
    if (!widget.allowEditAction || widget.onEditMessage == null) return false;
    if (message.isDeleted) return false;
    if (message.status == 'failed') return false;
    if (widget.ownPeerId == null || message.isIncoming) return false;
    if (message.senderPeerId != widget.ownPeerId) return false;
    if (message.text.trim().isEmpty) return false;
    if (_isComposerBusy()) return false;
    return _lastSentMessageId() == message.id;
  }

  bool _isComposerBusy() {
    final composerState =
        widget.composerStateListenable?.value ?? _legacyComposerState;
    return widget.isSending ||
        composerState.pendingAttachments.isNotEmpty ||
        composerState.isUploading ||
        composerState.isProcessing ||
        composerState.isRecording;
  }

  bool _canDeleteMessage(ConversationMessage message) {
    if (widget.onDeleteMessage == null) return false;
    if (message.isDeleted) return false;
    return message.transport != 'system';
  }

  String? _lastSentMessageId() {
    for (var i = widget.messages.length - 1; i >= 0; i--) {
      final message = widget.messages[i];
      if (message.isDeleted) continue;
      if (!message.isIncoming && message.senderPeerId == widget.ownPeerId) {
        return message.id;
      }
    }
    return null;
  }

  Future<void> _copyMessageText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    // 154: keep the post-await !mounted guard (this State.context) — copy has
    // no persistent control, so confirm with a distinct, keyed quiet-confirm +
    // haptic instead of the reserved error-style snackbar.
    if (!mounted) return;
    showQuietConfirm(
      context,
      AppLocalizations.of(context)!.conversation_context_copied,
    );
  }

  void _showFullPicker(String messageId) async {
    final emoji = await showFullEmojiPicker(context);
    if (emoji != null) {
      widget.onReactionSelected?.call(messageId, emoji);
    }
  }

  String _formatDateLabel(String isoTimestamp) {
    try {
      final date = DateTime.parse(isoTimestamp);
      final l10n = AppLocalizations.of(context)!;
      final locale = Localizations.localeOf(context).toString();
      return formatDaySeparatorLabel(
        date,
        now: DateTime.now(),
        todayLabel: l10n.date_today,
        yesterdayLabel: l10n.date_yesterday,
        locale: locale,
      );
    } catch (_) {
      return AppLocalizations.of(context)?.date_today ?? 'Today';
    }
  }

}

class _EditModeBanner extends StatelessWidget {
  final VoidCallback onCancel;

  const _EditModeBanner({super.key, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(18, 20, 28, 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color.fromRGBO(255, 255, 255, 0.10),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ECDC4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.conversation_editing_message,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color.fromRGBO(255, 255, 255, 0.88),
                    ),
                  ),
                ),
                TextButton(
                  key: ConversationScreen.cancelEditKey,
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF4ECDC4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(l10n.conversation_cancel_edit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 145: thin "catching up…" status row shown while the relay offline-inbox
/// drain is in flight (notification-tap / app-resume recovery). Matches the
/// glass-row house style of [_EditModeBanner]. Keyed so tests can assert its
/// presence/placement independent of copy.
class _ConversationSyncingBanner extends StatelessWidget {
  const _ConversationSyncingBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      key: const ValueKey('conversation-syncing-banner'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(18, 20, 28, 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color.fromRGBO(255, 255, 255, 0.10),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF4ECDC4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.conversation_catching_up,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color.fromRGBO(255, 255, 255, 0.88),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated wrapper for letter cards.
///
/// Applies staggered entry animation (translateY + opacity)
/// matching spec section 6b (400ms ease, 50ms stagger).
class _AnimatedLetterCard extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final bool isNewMessage;

  const _AnimatedLetterCard({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.isNewMessage = false,
  });

  @override
  State<_AnimatedLetterCard> createState() => _AnimatedLetterCardState();
}

class _AnimatedLetterCardState extends State<_AnimatedLetterCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _translateY;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    final duration = widget.isNewMessage ? 400 : 400;
    final translateStart = widget.isNewMessage ? 20.0 : 12.0;
    final scaleStart = widget.isNewMessage ? 0.97 : 1.0;

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: duration),
    );

    final curve = CurvedAnimation(
      parent: _controller,
      curve: widget.isNewMessage ? const Cubic(0.16, 1, 0.3, 1) : Curves.ease,
    );

    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _translateY = Tween<double>(begin: translateStart, end: 0).animate(curve);
    _scale = Tween<double>(begin: scaleStart, end: 1).animate(curve);

    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(0, _translateY.value),
            child: Transform.scale(scale: _scale.value, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

enum _ItemType { originMarker, dateSeparator, message, loadingIndicator }

class _DisplayItem {
  final _ItemType type;
  final ConversationMessage? message;
  final String? dateLabel;
  final bool isLastAndWasEmpty;

  /// 136 Phase 3: whether this message row is the FIRST balloon of its run
  /// (consecutive same-sender messages within [kMessageRunGapThreshold] that
  /// are not split by a date separator or a system row). Defaults true so a
  /// standalone balloon renders with full corner radii.
  final bool isFirstInGroup;

  /// 136 Phase 3: whether this message row is the LAST balloon of its run.
  final bool isLastInGroup;

  const _DisplayItem._({
    required this.type,
    this.message,
    this.dateLabel,
    this.isLastAndWasEmpty = false,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
  });

  factory _DisplayItem.originMarker() =>
      const _DisplayItem._(type: _ItemType.originMarker);

  factory _DisplayItem.dateSeparator(String label) =>
      _DisplayItem._(type: _ItemType.dateSeparator, dateLabel: label);

  factory _DisplayItem.loadingIndicator() =>
      const _DisplayItem._(type: _ItemType.loadingIndicator);

  factory _DisplayItem.message(
    ConversationMessage msg, {
    bool isLastAndWasEmpty = false,
    bool isFirstInGroup = true,
    bool isLastInGroup = true,
  }) => _DisplayItem._(
    type: _ItemType.message,
    message: msg,
    isLastAndWasEmpty: isLastAndWasEmpty,
    isFirstInGroup: isFirstInGroup,
    isLastInGroup: isLastInGroup,
  );

  /// Returns a copy of a message item with [isLastInGroup] overridden (used by
  /// the second-pass lookahead that finalizes run-end flags).
  _DisplayItem copyWithLastInGroup(bool value) => _DisplayItem._(
    type: type,
    message: message,
    dateLabel: dateLabel,
    isLastAndWasEmpty: isLastAndWasEmpty,
    isFirstInGroup: isFirstInGroup,
    isLastInGroup: value,
  );
}

class _ConversationLoadingShell extends StatelessWidget {
  const _ConversationLoadingShell();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('conversation-loading-shell'),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: const [
        _ConversationLoadingBubble(index: 0, alignment: Alignment.centerLeft),
        SizedBox(height: 14),
        _ConversationLoadingBubble(index: 1, alignment: Alignment.centerRight),
        SizedBox(height: 14),
        _ConversationLoadingBubble(index: 2, alignment: Alignment.centerLeft),
      ],
    );
  }
}

class _ConversationLoadingBubble extends StatelessWidget {
  final int index;
  final Alignment alignment;

  const _ConversationLoadingBubble({
    required this.index,
    required this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        key: ValueKey('conversation-loading-bubble-$index'),
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
            _ConversationLoadingBar(widthFactor: 0.78),
            SizedBox(height: 10),
            _ConversationLoadingBar(widthFactor: 0.52),
          ],
        ),
      ),
    );
  }
}

class _ConversationLoadingBar extends StatelessWidget {
  final double widthFactor;

  const _ConversationLoadingBar({required this.widthFactor});

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
