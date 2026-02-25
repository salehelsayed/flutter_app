import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/blocked_banner.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compact_origin_marker.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/empty_conversation_state.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

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
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  bool _wasEmpty = true;

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
          // Body with animated transition
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: widget.messages.isEmpty
                  ? EmptyConversationState(
                      key: const ValueKey('empty'),
                      contactPeerId: widget.contactPeerId,
                      connectionDate: widget.connectionDate,
                    )
                  : _buildMessageList(),
            ),
          ),
          // Attachment preview strip
          if (!widget.isBlocked &&
              (widget.pendingAttachments.isNotEmpty || widget.isProcessing))
            AttachmentPreviewStrip(
              attachments: widget.pendingAttachments,
              isUploading: widget.isUploading,
              isProcessing: widget.isProcessing,
              processingProgress: widget.processingProgress,
              onRemove: widget.onRemoveAttachment,
            ),
          // Compose area or blocked banner
          if (widget.isBlocked)
            BlockedBanner(onUnblock: widget.onUnblock)
          else
            ComposeArea(
              onSend: widget.onSend,
              onAttach: widget.onAttach,
              hasAttachments: widget.pendingAttachments.isNotEmpty,
              isProcessing: widget.isProcessing,
            ),
        ],
      ),
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

            final letterCard = LetterCard(
              senderPeerId: message.senderPeerId,
              senderName: message.isIncoming
                  ? widget.contactUsername
                  : 'You',
              text: message.text,
              time: _formatTime(message.timestamp),
              isIncoming: message.isIncoming,
              status: message.isIncoming ? null : message.status,
              transport: message.transport,
              quotedText: quotedText,
              isQuoteUnavailable: isQuoteUnavailable,
              media: message.media,
              onMediaTap: (index) {
                final visual = message.media
                    .where((a) => a.mediaType == 'image' || a.mediaType == 'video')
                    .toList();
                if (index < visual.length && visual[index].localPath != null) {
                  final allPaths = visual
                      .where((a) => a.localPath != null && a.downloadStatus == 'done')
                      .map((a) => a.localPath!)
                      .toList();
                  final tappedPath = visual[index].localPath!;
                  final startIndex = allPaths.indexOf(tappedPath).clamp(0, allPaths.length - 1);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FullScreenImageViewer(
                      localPath: tappedPath,
                      allPaths: allPaths,
                      initialIndex: startIndex,
                    ),
                  ));
                }
              },
            );

            final shouldAnimate = !widget.initialLoadDone || isNew;

            return Padding(
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

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
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
      curve: widget.isNewMessage
          ? const Cubic(0.16, 1, 0.3, 1)
          : Curves.ease,
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
  }) =>
      _DisplayItem._(
        type: _ItemType.message,
        message: msg,
        isLastAndWasEmpty: isLastAndWasEmpty,
      );
}
