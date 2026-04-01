import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
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
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/full_emoji_picker.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_banner.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_system_message.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

@immutable
class ConversationComposerViewState {
  final List<File> pendingAttachments;
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
}

/// Pure UI conversation screen.
///
/// Displays header, conversation body (empty state or letter cards),
/// and compose area. No business logic — all data passed via props.
class ConversationScreen extends StatefulWidget {
  static const editModeBannerKey = ValueKey('conversation-edit-mode-banner');
  static const cancelEditKey = ValueKey('conversation-cancel-edit-action');

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
  final bool isLoadingMore;
  final bool hasMoreOlderMessages;
  final bool initialLoadDone;
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
  final VoidCallback? onMakeIntroductions;
  final VoidCallback? onMaybeLater;
  final String? initialText;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<String>? onQuoteReply;
  final ValueChanged<String>? onRetryFailedMedia;
  final ValueChanged<String>? onDeleteFailedMedia;
  final ValueChanged<String>? onDeleteMessage;
  final String? activeQuoteText;
  final bool isActiveQuoteUnavailable;
  final VoidCallback? onClearQuote;
  final ValueChanged<String>? onEditMessage;
  final bool isEditingMessage;
  final VoidCallback? onCancelEdit;
  final bool allowEditAction;

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
    this.isLoadingMore = false,
    this.hasMoreOlderMessages = true,
    this.initialLoadDone = false,
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
    this.onMakeIntroductions,
    this.onMaybeLater,
    this.initialText,
    this.onDraftChanged,
    this.onQuoteReply,
    this.onRetryFailedMedia,
    this.onDeleteFailedMedia,
    this.onDeleteMessage,
    this.activeQuoteText,
    this.isActiveQuoteUnavailable = false,
    this.onClearQuote,
    this.onEditMessage,
    this.isEditingMessage = false,
    this.onCancelEdit,
    this.allowEditAction = true,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  bool _wasEmpty = true;
  bool _shouldRequestComposerFocus = false;

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
      child: Column(
        children: [
          // Header
          ConversationHeader(
            contactPeerId: widget.contactPeerId,
            contactUsername: widget.contactUsername,
            connectionDate: widget.connectionDate,
            onBack: widget.onBack,
            onOverflow: widget.onOverflow,
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
          isProcessing: composerState.isProcessing,
          isSending: widget.isSending,
          recordingState: composerState.recordingState,
          onRecordStart: widget.onRecordStart,
          onRecordStop: widget.onRecordStop,
          onRecordCancel: widget.onRecordCancel,
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
              final quoted = widget.messages
                  .where((m) => m.id == message.quotedMessageId)
                  .firstOrNull;
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
            final showFailedMediaActions =
                !message.isDeleted &&
                !message.isIncoming &&
                message.status == 'failed' &&
                message.media.isNotEmpty;
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
                final allPaths = visual
                    .where(
                      (a) => a.localPath != null && a.downloadStatus == 'done',
                    )
                    .map((a) => a.localPath!)
                    .toList();
                final tappedPath = visual[index].localPath!;
                final startIndex = allPaths
                    .indexOf(tappedPath)
                    .clamp(0, allPaths.length - 1);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FullScreenImageViewer(
                      localPath: tappedPath,
                      allPaths: allPaths,
                      initialIndex: startIndex,
                    ),
                  ),
                );
              }
            };

            LetterCard buildLetterCard({VoidCallback? onLongPress}) {
              return LetterCard(
                senderPeerId: message.senderPeerId,
                senderName: message.isIncoming ? widget.contactUsername : 'You',
                text: displayText,
                time: _formatTime(message.timestamp),
                isIncoming: message.isIncoming,
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
                onRetryFailedMedia:
                    showFailedMediaActions && widget.onRetryFailedMedia != null
                    ? () => widget.onRetryFailedMedia!(message.id)
                    : null,
                onDeleteFailedMedia:
                    showFailedMediaActions && widget.onDeleteFailedMedia != null
                    ? () => widget.onDeleteFailedMedia!(message.id)
                    : null,
                failedMediaActionKeySuffix: message.id,
                onMediaTap: mediaTapHandler,
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
              ),
            );

            final shouldAnimate = !widget.initialLoadDone || isNew;
            Widget bubble = shouldAnimate
                ? _AnimatedLetterCard(
                    key: ValueKey(message.id),
                    delayMs: 0,
                    isNewMessage: isNew,
                    child: letterCard,
                  )
                : letterCard;

            if (message.isIncoming &&
                !message.isDeleted &&
                widget.onQuoteReply != null) {
              bubble = SwipeToQuoteBubble(
                onQuoteTriggered: () => widget.onQuoteReply!(message.id),
                child: bubble,
              );
            }

            return Padding(
              key: ValueKey('msg-${message.id}'),
              padding: const EdgeInsets.only(bottom: 16),
              child: bubble,
            );
        }
      },
    );
  }

  /// Builds display items in forward chronological order, then reverses
  /// for the reversed ListView (index 0 = bottom = newest).
  List<_DisplayItem> _buildDisplayItems() {
    final items = <_DisplayItem>[];

    // Top of conversation markers (will appear at scroll-top)
    if (!widget.hasMoreOlderMessages) {
      items.add(_DisplayItem.originMarker());
    }
    if (widget.isLoadingMore) {
      items.add(_DisplayItem.loadingIndicator());
    }

    // Messages with date separators
    String? lastDateLabel;
    for (var i = 0; i < widget.messages.length; i++) {
      final message = widget.messages[i];
      final dateLabel = _formatDateLabel(message.timestamp);

      if (dateLabel != lastDateLabel) {
        items.add(_DisplayItem.dateSeparator(dateLabel));
        lastDateLabel = dateLabel;
      }

      final isNew = i == widget.messages.length - 1 && _wasEmpty;
      items.add(_DisplayItem.message(message, isLastAndWasEmpty: isNew));
    }

    // Reset transition state after build
    if (_wasEmpty && widget.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _wasEmpty = false;
      });
    }

    return items.reversed.toList();
  }

  void _showMessageContextOverlay(
    ConversationMessage message, {
    required BuildContext cardContext,
    required Widget selectedMessage,
  }) {
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
        showDeleteAction: hasDeleteAction,
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
        onDeleteTap: hasDeleteAction
            ? () {
                Navigator.of(dialogContext).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  widget.onDeleteMessage?.call(message.id);
                });
              }
            : null,
      ),
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
    if (widget.ownPeerId == null || message.isIncoming) return false;
    if (message.senderPeerId != widget.ownPeerId) return false;
    if (message.text.trim().isEmpty) return false;
    return _lastSentMessageId() == message.id;
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
    if (!mounted) return;
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

  void _showFullPicker(String messageId) async {
    final emoji = await showFullEmojiPicker(context);
    if (emoji != null) {
      widget.onReactionSelected?.call(messageId, emoji);
    }
  }

  String _formatDateLabel(String isoTimestamp) {
    try {
      final date = DateTime.parse(isoTimestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final messageDate = DateTime(date.year, date.month, date.day);
      final l10n = AppLocalizations.of(context)!;
      final locale = Localizations.localeOf(context).toString();

      if (messageDate == today) return l10n.date_today;
      if (messageDate == today.subtract(const Duration(days: 1))) {
        return l10n.date_yesterday;
      }
      return intl.DateFormat.MMMd(locale).format(date);
    } catch (_) {
      return AppLocalizations.of(context)?.date_today ?? 'Today';
    }
  }

  String _formatTime(String isoTimestamp) {
    try {
      final date = DateTime.parse(isoTimestamp).toLocal();
      final locale = Localizations.localeOf(context).toString();
      return intl.DateFormat.jm(locale).format(date);
    } catch (_) {
      return '';
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

  const _DisplayItem._({
    required this.type,
    this.message,
    this.dateLabel,
    this.isLastAndWasEmpty = false,
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
  }) => _DisplayItem._(
    type: _ItemType.message,
    message: msg,
    isLastAndWasEmpty: isLastAndWasEmpty,
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
