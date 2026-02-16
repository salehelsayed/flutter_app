import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/has_significant_time_gap.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/time_gap_divider.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';

/// A thread card that groups multiple messages from the same contact.
///
/// Collapsed: shows the latest message with optional "+N more" peek hint
/// and stacked paper layers behind for multi-message threads.
/// Expanded: shows all messages as bubbles with time gap dividers.
class ThreadCard extends StatefulWidget {
  final ThreadFeedItem thread;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onReply;

  const ThreadCard({
    super.key,
    required this.thread,
    this.isExpanded = false,
    this.onToggleExpand,
    this.onReply,
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
    final messageCount = widget.thread.messages.length;
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
    final messageCount = widget.thread.messages.length;
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
            top: -8,
            right: 12,
            child: UnreadCountBadge(count: widget.thread.unreadCount),
          ),
      ],
    );
  }

  Widget _buildMainCard() {
    final hasUnread = widget.thread.unreadCount > 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.transparent,
            border: Border.all(
              color: hasUnread
                  ? const Color.fromRGBO(255, 255, 255, 0.25)
                  : const Color.fromRGBO(255, 255, 255, 0.10),
            ),
          ),
          child: Stack(
            children: [
              // Content
              Column(
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
                  _buildReplyFooter(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendIndicator() {
    final thread = widget.thread;
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
                Text(
                  thread.latestMessage.time,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Color.fromRGBO(255, 255, 255, 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedBody() {
    final thread = widget.thread;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            thread.latestMessage.text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: Color.fromRGBO(255, 255, 255, 0.90),
              height: 1.65,
              letterSpacing: 0.2,
            ),
          ),
          if (thread.isMultiMessage) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                '+${thread.additionalCount} more message${thread.additionalCount == 1 ? '' : 's'} \u02C5',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color.fromRGBO(78, 205, 196, 0.6),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedBody() {
    final messages = widget.thread.messages;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
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
            child: const Center(
              child: Text(
                '\u02C4 Collapse',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color.fromRGBO(78, 205, 196, 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBubble(int index, ThreadMessage message) {
    final anim = _bubbleAnimation(index);
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
      child: MessageBubble(
        text: message.text,
        time: message.time,
        isUnread: message.isUnread,
      ),
    );
  }

  Widget _buildReplyFooter() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Color.fromRGBO(255, 255, 255, 0.08),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: widget.onReply,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 18,
                    color: Color.fromRGBO(255, 255, 255, 0.6),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Reply',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color.fromRGBO(255, 255, 255, 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
