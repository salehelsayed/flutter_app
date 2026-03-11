import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/has_significant_time_gap.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/more_messages_hint.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/time_gap_divider.dart';
import 'package:flutter_app/features/feed/presentation/widgets/view_earlier_link.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

/// Scrollable preview of unread messages within an open-mode feed card.
///
/// Shows up to [maxVisible] messages in a static Column.
/// When more messages exist, wraps in a constrained ListView with
/// ShaderMask gradient fade and [MoreMessagesHint].
class ScrollableMessagePreview extends StatefulWidget {
  final List<ThreadMessage> messages;

  /// Optional broader thread context used to resolve quoted parents.
  final List<ThreadMessage>? quoteLookupMessages;
  final String contactPeerId;
  final String contactUsername;
  final bool hasEarlierHistory;
  final VoidCallback? onViewEarlier;
  final VoidCallback? onCollapse;
  final ValueChanged<String>? onQuoteReply;
  final int maxVisible;
  final Map<String, List<MessageReaction>> reactions;
  final ValueListenable<List<MessageReaction>>? Function(String messageId)?
  reactionListenableForMessage;
  final String? ownPeerId;
  final void Function(String messageId)? onMessageLongPress;
  final void Function(String messageId, String emoji)? onReactionTap;

  const ScrollableMessagePreview({
    super.key,
    required this.messages,
    this.quoteLookupMessages,
    required this.contactPeerId,
    required this.contactUsername,
    this.hasEarlierHistory = false,
    this.onViewEarlier,
    this.onCollapse,
    this.onQuoteReply,
    this.maxVisible = 3,
    this.reactions = const {},
    this.reactionListenableForMessage,
    this.ownPeerId,
    this.onMessageLongPress,
    this.onReactionTap,
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
        if (widget.onCollapse != null) _buildCollapseHint(),
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

  Widget _buildCollapseHint() {
    return GestureDetector(
      onTap: widget.onCollapse,
      behavior: HitTestBehavior.opaque,
      child: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 16,
                color: FeedColors.viewEarlierText,
              ),
              SizedBox(width: 2),
              Text(
                'Collapse',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: FeedColors.viewEarlierText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMediaViewer(
    BuildContext context,
    List<MediaAttachment> media,
    int tappedIndex,
  ) {
    final visual = media
        .where((a) => a.mediaType == 'image' || a.mediaType == 'video')
        .toList();
    if (tappedIndex >= visual.length) return;

    final tapped = visual[tappedIndex];
    if (tapped.localPath == null || tapped.downloadStatus != 'done') return;

    final allPaths = visual
        .where((a) => a.localPath != null && a.downloadStatus == 'done')
        .map((a) => a.localPath!)
        .toList();

    final startIndex = allPaths
        .indexOf(tapped.localPath!)
        .clamp(0, allPaths.length - 1);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullScreenImageViewer(
          localPath: tapped.localPath!,
          allPaths: allPaths,
          initialIndex: startIndex,
        ),
      ),
    );
  }

  /// Resolves quoted text for a message by looking up the quoted message
  /// among sibling thread messages.
  (String?, bool) _resolveQuotedText(
    ThreadMessage msg,
    Map<String, ThreadMessage> quoteLookupById,
  ) {
    if (msg.quotedMessageId == null) return (null, false);

    final quoted = quoteLookupById[msg.quotedMessageId];

    if (quoted == null) return (null, true); // unavailable

    if (quoted.text.isNotEmpty) return (quoted.text, false);
    if (quoted.media.isNotEmpty) return (mediaPreviewText(quoted.media), false);
    return (null, true);
  }

  List<Widget> _buildMessageWidgets(List<ThreadMessage> messages) {
    final widgets = <Widget>[];
    final quoteLookupById = {
      for (final message in widget.quoteLookupMessages ?? messages)
        message.id: message,
    };
    for (var i = 0; i < messages.length; i++) {
      if (i > 0 &&
          hasSignificantTimeGap(
            messages[i - 1].timestamp,
            messages[i].timestamp,
          )) {
        widgets.add(TimeGapDivider(timeLabel: messages[i].time));
      } else if (i > 0) {
        widgets.add(const SizedBox(height: 2));
      }

      final msg = messages[i];
      final (quotedText, isQuoteUnavailable) = _resolveQuotedText(
        msg,
        quoteLookupById,
      );
      final reactionsListenable = widget.reactionListenableForMessage?.call(
        msg.id,
      );

      Widget buildBubble(List<MessageReaction> reactions) {
        return MessageBubble(
          text: msg.text,
          time: msg.time,
          isUnread: msg.isUnread,
          isIncoming: msg.isIncoming,
          status: msg.status,
          senderPeerId: msg.isIncoming
              ? (msg.senderPeerId ?? widget.contactPeerId)
              : null,
          senderLabel: msg.isIncoming
              ? (msg.senderUsername ?? widget.contactUsername)
              : 'You',
          media: msg.media,
          onMediaTap: msg.media.isNotEmpty
              ? (index) => _openMediaViewer(context, msg.media, index)
              : null,
          quotedText: quotedText,
          isQuoteUnavailable: isQuoteUnavailable,
          reactions: reactions,
          ownPeerId: widget.ownPeerId,
          onLongPress: widget.onMessageLongPress != null
              ? () => widget.onMessageLongPress!(msg.id)
              : null,
          onReactionTap: widget.onReactionTap != null
              ? (emoji) => widget.onReactionTap!(msg.id, emoji)
              : null,
        );
      }

      Widget bubble = reactionsListenable != null
          ? ValueListenableBuilder<List<MessageReaction>>(
              valueListenable: reactionsListenable,
              builder: (context, reactions, child) => buildBubble(reactions),
            )
          : buildBubble(widget.reactions[msg.id] ?? const []);

      if (msg.isIncoming && widget.onQuoteReply != null) {
        bubble = SwipeToQuoteBubble(
          onQuoteTriggered: () => widget.onQuoteReply!(msg.id),
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
  ) => child;
}
