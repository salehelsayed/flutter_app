import 'package:flutter/material.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/has_significant_time_gap.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/more_messages_hint.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/time_gap_divider.dart';
import 'package:flutter_app/features/feed/presentation/widgets/view_earlier_link.dart';

/// Scrollable preview of unread messages within an open-mode feed card.
///
/// Shows up to [maxVisible] messages in a static Column.
/// When more messages exist, wraps in a constrained ListView with
/// ShaderMask gradient fade and [MoreMessagesHint].
class ScrollableMessagePreview extends StatefulWidget {
  final List<ThreadMessage> messages;
  final String contactPeerId;
  final String contactUsername;
  final bool hasEarlierHistory;
  final VoidCallback? onViewEarlier;
  final ValueChanged<String>? onQuoteReply;
  final int maxVisible;

  const ScrollableMessagePreview({
    super.key,
    required this.messages,
    required this.contactPeerId,
    required this.contactUsername,
    this.hasEarlierHistory = false,
    this.onViewEarlier,
    this.onQuoteReply,
    this.maxVisible = 3,
  });

  @override
  State<ScrollableMessagePreview> createState() =>
      _ScrollableMessagePreviewState();
}

class _ScrollableMessagePreviewState extends State<ScrollableMessagePreview> {
  final ScrollController _scrollController = ScrollController();
  int _remainingCount = 0;

  @override
  void initState() {
    super.initState();
    _remainingCount = _computeInitialRemaining();
    if (_isScrollable) {
      _scrollController.addListener(_onScroll);
    }
  }

  @override
  void didUpdateWidget(ScrollableMessagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length) {
      setState(() {
        _remainingCount = _computeInitialRemaining();
      });
    }
  }

  bool get _isScrollable => widget.messages.length > widget.maxVisible;

  int _computeInitialRemaining() {
    final total = widget.messages.length;
    if (total <= widget.maxVisible) return 0;
    return total - widget.maxVisible;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    if (maxExtent <= 0) return;

    final scrollFraction = (current / maxExtent).clamp(0.0, 1.0);
    final total = widget.messages.length;
    final extra = total - widget.maxVisible;
    final newRemaining = (extra * (1 - scrollFraction)).round();

    if (newRemaining != _remainingCount) {
      setState(() => _remainingCount = newRemaining);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.hasEarlierHistory)
          ViewEarlierLink(onTap: widget.onViewEarlier),
        if (_isScrollable) _buildScrollable() else _buildStatic(),
        if (_isScrollable && _remainingCount > 0)
          MoreMessagesHint(count: _remainingCount),
      ],
    );
  }

  Widget _buildStatic() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _buildMessageWidgets(widget.messages),
    );
  }

  Widget _buildScrollable() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 180),
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.05, 0.85, 1.0],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: ScrollConfiguration(
          behavior: _NoScrollbarBehavior(),
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.zero,
            children: _buildMessageWidgets(widget.messages),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMessageWidgets(List<ThreadMessage> messages) {
    final widgets = <Widget>[];
    for (var i = 0; i < messages.length; i++) {
      if (i > 0 &&
          hasSignificantTimeGap(
            messages[i - 1].timestamp,
            messages[i].timestamp,
          )) {
        widgets.add(TimeGapDivider(timeLabel: messages[i].time));
      } else if (i > 0) {
        widgets.add(const SizedBox(height: 6));
      }

      Widget bubble = MessageBubble(
        text: messages[i].text,
        time: messages[i].time,
        isUnread: messages[i].isUnread,
        isIncoming: messages[i].isIncoming,
        status: messages[i].status,
        senderPeerId:
            messages[i].isIncoming ? widget.contactPeerId : null,
        senderLabel:
            messages[i].isIncoming ? widget.contactUsername : 'You',
      );

      if (messages[i].isIncoming && widget.onQuoteReply != null) {
        bubble = SwipeToQuoteBubble(
          onQuoteTriggered: () => widget.onQuoteReply!(messages[i].id),
          child: bubble,
        );
      }

      widgets.add(bubble);
    }
    return widgets;
  }
}

class _NoScrollbarBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
