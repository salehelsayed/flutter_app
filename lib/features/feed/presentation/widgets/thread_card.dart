import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';
import 'package:flutter_app/features/feed/domain/utils/has_significant_time_gap.dart';
import 'package:flutter_app/features/feed/presentation/widgets/expanded_compose_input.dart';
import 'package:flutter_app/features/feed/presentation/widgets/inline_reply_input.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/quote_preview_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/time_gap_divider.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';

/// A thread card that groups messages from the same contact.
///
/// Collapsed: exchange preview (last 2 messages), state indicators,
/// inline reply input.
/// Expanded: bidirectional message bubbles (recent 6), "View N earlier"
/// link, compose area.
class ThreadCard extends StatefulWidget {
  final ThreadFeedItem thread;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onReply;
  final ValueChanged<String>? onInlineSend;
  final VoidCallback? onViewFullConversation;
  final String initialText;
  final bool shouldRequestFocus;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<bool>? onInputFocusChanged;
  final String? activeQuoteMessageId;
  final ValueChanged<String>? onQuoteReply;
  final VoidCallback? onClearQuote;

  const ThreadCard({
    super.key,
    required this.thread,
    this.isExpanded = false,
    this.onToggleExpand,
    this.onReply,
    this.onInlineSend,
    this.onViewFullConversation,
    this.initialText = '',
    this.shouldRequestFocus = false,
    this.onDraftChanged,
    this.onInputFocusChanged,
    this.activeQuoteMessageId,
    this.onQuoteReply,
    this.onClearQuote,
  });

  @override
  State<ThreadCard> createState() => _ThreadCardState();
}

class _ThreadCardState extends State<ThreadCard>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _entryOpacity;
  late final Animation<double> _entryTranslateY;
  late final Animation<double> _entryScale;

  AnimationController? _bubbleController;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    final curve = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );

    _entryOpacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _entryTranslateY = Tween<double>(begin: 30, end: 0).animate(curve);
    _entryScale = Tween<double>(begin: 0.95, end: 1).animate(curve);

    _entryController.forward();

    if (widget.isExpanded) {
      _startBubbleAnimation();
    }
  }

  @override
  void didUpdateWidget(ThreadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded && !oldWidget.isExpanded) {
      _startBubbleAnimation();
    }
  }

  void _startBubbleAnimation() {
    _bubbleController?.dispose();
    final messageCount = _expandedMessages.length;
    final totalDuration = 300 + (messageCount - 1) * 40;
    _bubbleController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalDuration.clamp(300, 2000)),
    );
    _bubbleController!.forward();
  }

  Animation<double> _bubbleAnimation(int index) {
    if (_bubbleController == null) {
      return const AlwaysStoppedAnimation(1.0);
    }
    final messageCount = _expandedMessages.length;
    final totalDuration = 300 + (messageCount - 1) * 40;
    final startFraction = (index * 40) / totalDuration;
    final endFraction =
        ((index * 40) + 300).clamp(0, totalDuration) / totalDuration;

    return CurvedAnimation(
      parent: _bubbleController!,
      curve: Interval(
        startFraction.clamp(0.0, 1.0),
        endFraction.clamp(0.0, 1.0),
        curve: Curves.ease,
      ),
    );
  }

  /// Messages shown in expanded view: at most recent 6.
  List<ThreadMessage> get _expandedMessages {
    final all = widget.thread.messages;
    if (all.length <= 6) return all;
    return all.sublist(all.length - 6);
  }

  /// Number of earlier messages not shown in expanded view.
  int get _earlierCount => widget.thread.messages.length - _expandedMessages.length;

  @override
  void dispose() {
    _entryController.dispose();
    _bubbleController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entryController,
      builder: (context, child) {
        return Opacity(
          opacity: _entryOpacity.value,
          child: Transform.translate(
            offset: Offset(0, _entryTranslateY.value),
            child: Transform.scale(scale: _entryScale.value, child: child),
          ),
        );
      },
      child: _buildStackedCard(),
    );
  }

  Widget _buildStackedCard() {
    final isMulti = widget.thread.isMultiMessage;
    final showStacks = isMulti && !widget.isExpanded;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (showStacks) ...[
          // Second stack layer (furthest back)
          Positioned(
            left: 12,
            right: 12,
            bottom: -8,
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color.fromRGBO(255, 255, 255, 0.04),
                ),
              ),
            ),
          ),
          // First stack layer
          Positioned(
            left: 6,
            right: 6,
            bottom: -4,
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color.fromRGBO(255, 255, 255, 0.06),
                ),
              ),
            ),
          ),
        ],
        // Main card
        GestureDetector(
          onTap: isMulti ? widget.onToggleExpand : null,
          child: _buildMainCard(),
        ),
        // Unread badge
        if (widget.thread.unreadCount > 0)
          Positioned(
            top: 8,
            right: 12,
            child: UnreadCountBadge(count: widget.thread.unreadCount),
          ),
      ],
    );
  }

  Widget _buildMainCard() {
    final state = widget.thread.conversationState;
    final isBlocked = widget.thread.isBlocked;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.transparent,
                border: Border.all(color: _cardBorderColor(state)),
                boxShadow: _cardBoxShadow(state),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFriendIndicator(),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.ease,
                    alignment: Alignment.topCenter,
                    child: widget.isExpanded
                        ? _buildExpandedBody()
                        : _buildCollapsedBody(),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
            if (isBlocked)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: const Color.fromRGBO(0, 0, 0, 0.45),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.block,
                          size: 28,
                          color: Color.fromRGBO(255, 255, 255, 0.60),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Blocked',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color.fromRGBO(255, 255, 255, 0.60),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _cardBorderColor(ConversationState state) {
    switch (state) {
      case ConversationState.unread:
      case ConversationState.active:
        return AppColors.warmBorderTint;
      case ConversationState.replied:
        return AppColors.tealBorderTint;
      case ConversationState.read:
        return const Color.fromRGBO(255, 255, 255, 0.10);
    }
  }

  List<BoxShadow>? _cardBoxShadow(ConversationState state) {
    if (state == ConversationState.unread ||
        state == ConversationState.active) {
      return [
        BoxShadow(
          color: AppColors.warmOrangeGlow,
          blurRadius: 12,
          spreadRadius: 0,
        ),
      ];
    }
    return null;
  }

  Widget _buildFriendIndicator() {
    final thread = widget.thread;
    final state = thread.conversationState;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          RingAvatar(
            peerId: thread.contactPeerId,
            size: 42,
          ),
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
                    color: Color.fromRGBO(255, 255, 255, 0.9),
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
                        color: Color.fromRGBO(255, 255, 255, 0.4),
                      ),
                    ),
                    if (thread.lastRepliedAt != null) ...[
                      const SizedBox(width: 8),
                      _buildReplyIndicator(),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // State indicator: teal checkmark for replied
          if (state == ConversationState.replied) _buildRepliedCheckmark(),
        ],
      ),
    );
  }

  Widget _buildReplyIndicator() {
    final relativeTime =
        formatRelativeTime(widget.thread.lastRepliedAt!.toIso8601String());
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.reply_rounded,
          size: 12,
          color: AppColors.tealAccent.withValues(alpha: 0.40),
        ),
        const SizedBox(width: 3),
        Text(
          'You replied $relativeTime',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: AppColors.tealAccent.withValues(alpha: 0.40),
          ),
        ),
      ],
    );
  }

  Widget _buildRepliedCheckmark() {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.tealAccent.withValues(alpha: 0.15),
      ),
      child: Icon(
        Icons.check_rounded,
        size: 14,
        color: AppColors.tealAccent.withValues(alpha: 0.70),
      ),
    );
  }

  Widget _buildCollapsedBody() {
    final thread = widget.thread;
    final preview = thread.exchangePreview;
    final earlierCount = thread.messages.length - preview.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Exchange preview: last 2 messages
          for (final msg in preview) _buildPreviewLine(msg, thread),
          if (earlierCount > 0) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                '+$earlierCount earlier \u02C5',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.tealAccent.withValues(alpha: 0.60),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewLine(ThreadMessage msg, ThreadFeedItem thread) {
    final isSent = !msg.isIncoming;
    final hasQuote = isSent && msg.quotedMessageId != null;
    final label = hasQuote
        ? '\u21A9 You'
        : (isSent ? 'You' : thread.contactUsername);
    final labelColor = isSent
        ? AppColors.tealAccent.withValues(alpha: 0.50)
        : const Color.fromRGBO(255, 255, 255, 0.50);
    final textOpacity = isSent ? 0.65 : 0.90;

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
          Expanded(
            child: Text(
              msg.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color.fromRGBO(255, 255, 255, textOpacity),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedBody() {
    final messages = _expandedMessages;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          // "View N earlier messages" link
          if (_earlierCount > 0) ...[
            GestureDetector(
              onTap: widget.onViewFullConversation,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Center(
                  child: Text(
                    'View $_earlierCount earlier messages',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.tealAccent.withValues(alpha: 0.60),
                    ),
                  ),
                ),
              ),
            ),
          ],
          for (var i = 0; i < messages.length; i++) ...[
            if (i > 0 &&
                hasSignificantTimeGap(
                  messages[i - 1].timestamp,
                  messages[i].timestamp,
                ))
              TimeGapDivider(timeLabel: messages[i].time),
            if (i > 0 &&
                !hasSignificantTimeGap(
                  messages[i - 1].timestamp,
                  messages[i].timestamp,
                ))
              const SizedBox(height: 6),
            _buildAnimatedBubble(i, messages[i]),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: widget.onToggleExpand,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Text(
                '\u02C4 Collapse',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.tealAccent.withValues(alpha: 0.60),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Resolves quoted text from sibling messages in the thread.
  String? _resolveQuotedText(String? quotedMessageId) {
    if (quotedMessageId == null) return null;
    final match = widget.thread.messages
        .where((m) => m.id == quotedMessageId)
        .firstOrNull;
    return match?.text;
  }

  Widget _buildAnimatedBubble(int index, ThreadMessage message) {
    final anim = _bubbleAnimation(index);

    final quotedText = _resolveQuotedText(message.quotedMessageId);
    final isQuoteUnavailable =
        message.quotedMessageId != null && quotedText == null;

    Widget bubble = MessageBubble(
      text: message.text,
      time: message.time,
      isUnread: message.isUnread,
      isIncoming: message.isIncoming,
      status: message.status,
      quotedText: quotedText,
      isQuoteUnavailable: isQuoteUnavailable,
    );

    // Wrap incoming bubbles in swipe-to-quote when expanded
    if (widget.isExpanded &&
        message.isIncoming &&
        widget.onQuoteReply != null) {
      bubble = SwipeToQuoteBubble(
        onQuoteTriggered: () => widget.onQuoteReply!(message.id),
        child: bubble,
      );
    }

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        return Opacity(
          opacity: anim.value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - anim.value)),
            child: Transform.scale(
              scale: 0.97 + 0.03 * anim.value,
              child: child,
            ),
          ),
        );
      },
      child: bubble,
    );
  }

  Widget _buildFooter() {
    final state = widget.thread.conversationState;
    final enabled = widget.onInlineSend != null && !widget.thread.isBlocked;

    // Resolve quote preview text
    final quoteId = widget.activeQuoteMessageId;
    final quoteText = _resolveQuotedText(quoteId);

    final Widget input;
    if (widget.isExpanded) {
      input = ExpandedComposeInput(
        hintText: 'Write something...',
        onSend: (text) => widget.onInlineSend?.call(text),
        enabled: enabled,
        initialText: widget.initialText,
        shouldRequestFocus: widget.shouldRequestFocus,
        onDraftChanged: widget.onDraftChanged,
        onFocusChanged: widget.onInputFocusChanged,
      );
    } else {
      final hintText = (state == ConversationState.replied ||
              state == ConversationState.active)
          ? 'Continue...'
          : 'Reply...';
      input = InlineReplyInput(
        hintText: hintText,
        onSend: (text) => widget.onInlineSend?.call(text),
        enabled: enabled,
        initialText: widget.initialText,
        shouldRequestFocus: widget.shouldRequestFocus,
        onDraftChanged: widget.onDraftChanged,
        onFocusChanged: widget.onInputFocusChanged,
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Color.fromRGBO(255, 255, 255, 0.08),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isExpanded && quoteId != null && quoteText != null)
            QuotePreviewBar(
              text: quoteText,
              onDismiss: widget.onClearQuote,
            ),
          input,
        ],
      ),
    );
  }
}
