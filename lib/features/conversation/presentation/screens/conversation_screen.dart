import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_bar.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/full_emoji_picker.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_banner.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_system_message.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

@immutable
class ConversationComposerViewState {
  final List<File> pendingAttachments;
  final bool isUploading;
  final bool isProcessing;
  final double processingProgress;
  final bool isRecording;
  final Duration recordingDuration;
  final List<double> amplitudeValues;

  const ConversationComposerViewState({
    this.pendingAttachments = const [],
    this.isUploading = false,
    this.isProcessing = false,
    this.processingProgress = 0.0,
    this.isRecording = false,
    this.recordingDuration = Duration.zero,
    this.amplitudeValues = const [],
  });

  ConversationComposerViewState copyWith({
    List<File>? pendingAttachments,
    bool? isUploading,
    bool? isProcessing,
    double? processingProgress,
    bool? isRecording,
    Duration? recordingDuration,
    List<double>? amplitudeValues,
  }) {
    return ConversationComposerViewState(
      pendingAttachments: pendingAttachments ?? this.pendingAttachments,
      isUploading: isUploading ?? this.isUploading,
      isProcessing: isProcessing ?? this.isProcessing,
      processingProgress: processingProgress ?? this.processingProgress,
      isRecording: isRecording ?? this.isRecording,
      recordingDuration: recordingDuration ?? this.recordingDuration,
      amplitudeValues: amplitudeValues ?? this.amplitudeValues,
    );
  }
}

/// Pure UI conversation screen.
///
/// Displays header, conversation body (empty state or letter cards),
/// and compose area. No business logic — all data passed via props.
class ConversationScreen extends StatefulWidget {
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
  final double processingProgress;
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;
  final VoidCallback? onRecordCancel;
  final bool isRecording;
  final Duration recordingDuration;
  final List<double> amplitudeValues;
  final ValueListenable<ConversationComposerViewState>? composerStateListenable;
  final Map<String, List<MessageReaction>> reactions;
  final void Function(String messageId, String emoji)? onReactionSelected;
  final void Function(String messageId)? onReactionPlusTap;
  final bool showIntroBanner;
  final String? bannerContactUsername;
  final VoidCallback? onMakeIntroductions;
  final VoidCallback? onMaybeLater;

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
    this.processingProgress = 0.0,
    this.onRecordStart,
    this.onRecordStop,
    this.onRecordCancel,
    this.isRecording = false,
    this.recordingDuration = Duration.zero,
    this.amplitudeValues = const [],
    this.composerStateListenable,
    this.reactions = const {},
    this.onReactionSelected,
    this.onReactionPlusTap,
    this.showIntroBanner = false,
    this.bannerContactUsername,
    this.onMakeIntroductions,
    this.onMaybeLater,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  bool _wasEmpty = true;

  ConversationComposerViewState get _legacyComposerState =>
      ConversationComposerViewState(
        pendingAttachments: widget.pendingAttachments,
        isUploading: widget.isUploading,
        isProcessing: widget.isProcessing,
        processingProgress: widget.processingProgress,
        isRecording: widget.isRecording,
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
          // Body with animated transition
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: widget.messages.isEmpty
                  ? widget.showIntroBanner && widget.onMakeIntroductions != null
                        ? Column(
                            key: const ValueKey('empty-with-banner'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: IntroBanner(
                                  contactUsername:
                                      widget.bannerContactUsername ??
                                      widget.contactUsername,
                                  onMakeIntroductions:
                                      widget.onMakeIntroductions!,
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
                          )
                        : EmptyConversationState(
                            key: const ValueKey('empty'),
                            contactPeerId: widget.contactPeerId,
                            connectionDate: widget.connectionDate,
                          )
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
            onRemove: widget.onRemoveAttachment,
          ),
        ComposeArea(
          onSend: widget.onSend,
          onAttach: widget.onAttach,
          hasAttachments: composerState.pendingAttachments.isNotEmpty,
          isProcessing: composerState.isProcessing,
          onRecordStart: widget.onRecordStart,
          onRecordStop: widget.onRecordStop,
          onRecordCancel: widget.onRecordCancel,
          isRecording: composerState.isRecording,
          recordingDuration: composerState.recordingDuration,
          amplitudeValues: composerState.amplitudeValues,
        ),
      ],
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

            // Resolve quoted message text
            String? quotedText;
            bool isQuoteUnavailable = false;
            if (message.quotedMessageId != null) {
              final quoted = widget.messages
                  .where((m) => m.id == message.quotedMessageId)
                  .firstOrNull;
              if (quoted != null) {
                if (quoted.text.isNotEmpty) {
                  quotedText = quoted.text;
                } else if (quoted.media.isNotEmpty) {
                  quotedText = mediaPreviewText(quoted.media);
                }
              } else {
                isQuoteUnavailable = true;
              }
            }

            final messageReactions = widget.reactions[message.id] ?? const [];

            final letterCard = LetterCard(
              senderPeerId: message.senderPeerId,
              senderName: message.isIncoming ? widget.contactUsername : 'You',
              text: message.text,
              time: _formatTime(message.timestamp),
              isIncoming: message.isIncoming,
              status: message.isIncoming ? null : message.status,
              transport: message.transport,
              quotedText: quotedText,
              isQuoteUnavailable: isQuoteUnavailable,
              media: message.media,
              reactions: messageReactions,
              ownPeerId: widget.ownPeerId,
              onLongPress: () => _showReactionBar(message.id),
              onReactionTap: widget.onReactionSelected != null
                  ? (emoji) => widget.onReactionSelected!(message.id, emoji)
                  : null,
              onMediaTap: (index) {
                final visual = message.media
                    .where(
                      (a) => a.mediaType == 'image' || a.mediaType == 'video',
                    )
                    .toList();
                if (index < visual.length && visual[index].localPath != null) {
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
                      builder: (_) => FullScreenImageViewer(
                        localPath: tappedPath,
                        allPaths: allPaths,
                        initialIndex: startIndex,
                      ),
                    ),
                  );
                }
              },
            );

            final shouldAnimate = !widget.initialLoadDone || isNew;

            return Padding(
              key: ValueKey('msg-${message.id}'),
              padding: const EdgeInsets.only(bottom: 16),
              child: shouldAnimate
                  ? _AnimatedLetterCard(
                      key: ValueKey(message.id),
                      delayMs: 0,
                      isNewMessage: isNew,
                      child: letterCard,
                    )
                  : letterCard,
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

  void _showReactionBar(String messageId) {
    // Find current reaction for this message by own user
    final reactions = widget.reactions[messageId] ?? [];
    final ownReaction = widget.ownPeerId != null
        ? reactions.where((r) => r.senderPeerId == widget.ownPeerId).firstOrNull
        : null;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => ReactionBar(
        currentEmoji: ownReaction?.emoji,
        onReactionSelected: (emoji) {
          Navigator.of(dialogContext).pop();
          widget.onReactionSelected?.call(messageId, emoji);
        },
        onPlusTap: () {
          Navigator.of(dialogContext).pop();
          _showFullPicker(messageId);
        },
        onDismiss: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  void _showFullPicker(String messageId) async {
    final emoji = await showFullEmojiPicker(context);
    if (emoji != null) {
      widget.onReactionSelected?.call(messageId, emoji);
    }
  }

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _formatDateLabel(String isoTimestamp) {
    try {
      final date = DateTime.parse(isoTimestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final messageDate = DateTime(date.year, date.month, date.day);

      if (messageDate == today) return 'Today';
      if (messageDate == today.subtract(const Duration(days: 1))) {
        return 'Yesterday';
      }
      return '${_months[date.month - 1]} ${date.day}';
    } catch (_) {
      return 'Today';
    }
  }

  String _formatTime(String isoTimestamp) {
    try {
      final date = DateTime.parse(isoTimestamp).toLocal();
      final hour = date.hour == 0
          ? 12
          : (date.hour > 12 ? date.hour - 12 : date.hour);
      final minute = date.minute.toString().padLeft(2, '0');
      final period = date.hour < 12 ? 'AM' : 'PM';
      return '$hour:$minute $period';
    } catch (_) {
      return '';
    }
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
