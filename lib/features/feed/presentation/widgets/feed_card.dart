import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/collapsed_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/open_mode_card_body.dart';

/// Feed card that auto-selects open or collapsed mode based on state.
///
/// Replaces the old ThreadCard. Flat card (no stacked layers) with
/// glassmorphism background and state-driven border/glow colors.
class FeedCard extends StatefulWidget {
  final CardThreadFeedItem thread;
  final SessionReply? sessionReply;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;
  final ValueChanged<String>? onInlineSend;
  final VoidCallback? onViewFullConversation;
  final String initialText;
  final bool shouldRequestFocus;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<bool>? onInputFocusChanged;
  final ValueChanged<String>? onQuoteReply;
  final VoidCallback? onAttach;
  final Map<String, List<MessageReaction>> reactions;
  final ValueListenable<List<MessageReaction>>? Function(String messageId)?
  reactionListenableForMessage;
  final String? ownPeerId;
  final void Function(String messageId)? onMessageLongPress;
  final void Function(String messageId, String emoji)? onReactionTap;

  const FeedCard({
    super.key,
    required this.thread,
    this.sessionReply,
    this.isExpanded = false,
    this.onToggleExpand,
    this.onInlineSend,
    this.onViewFullConversation,
    this.initialText = '',
    this.shouldRequestFocus = false,
    this.onDraftChanged,
    this.onInputFocusChanged,
    this.onQuoteReply,
    this.onAttach,
    this.reactions = const {},
    this.reactionListenableForMessage,
    this.ownPeerId,
    this.onMessageLongPress,
    this.onReactionTap,
  });

  @override
  State<FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<FeedCard> with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _entryOpacity;
  late final Animation<double> _entryTranslateY;
  late final Animation<double> _entryScale;

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
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  bool get _showOpen => widget.thread.isOpenMode && widget.sessionReply == null;

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
      child: _buildCard(),
    );
  }

  Widget _buildCard() {
    final state = widget.thread.conversationState;
    final isBlocked = widget.thread.isBlocked;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: FeedColors.cardBg,
                border: Border.all(color: _borderColor(state)),
                boxShadow: _boxShadow(state),
              ),
              child: _showOpen ? _buildOpenBody() : _buildCollapsedBody(),
            ),
            if (isBlocked) _buildBlockedOverlay(),
          ],
        ),
      ),
    );
  }

  Color _borderColor(ConversationState state) {
    if (widget.sessionReply != null) return FeedColors.tealBorderTint;
    switch (state) {
      case ConversationState.unread:
      case ConversationState.active:
        return FeedColors.purpleBorderTint;
      case ConversationState.replied:
        return FeedColors.tealBorderTint;
      case ConversationState.read:
        return FeedColors.cardBorder;
    }
  }

  List<BoxShadow>? _boxShadow(ConversationState state) {
    if (widget.sessionReply != null) return null;
    if (state == ConversationState.unread ||
        state == ConversationState.active) {
      return [
        BoxShadow(color: FeedColors.cardBg, blurRadius: 12, spreadRadius: 0),
      ];
    }
    return null;
  }

  Widget _buildOpenBody() {
    final enabled = widget.onInlineSend != null && !widget.thread.isBlocked;
    return OpenModeCardBody(
      thread: widget.thread,
      onViewEarlier: widget.onViewFullConversation,
      onCollapse: widget.onToggleExpand,
      onQuoteReply: widget.onQuoteReply,
      onSend: (text) => widget.onInlineSend?.call(text),
      sendEnabled: enabled,
      initialText: widget.initialText,
      shouldRequestFocus: widget.shouldRequestFocus,
      onDraftChanged: widget.onDraftChanged,
      onInputFocusChanged: widget.onInputFocusChanged,
      onAttach: widget.onAttach,
      reactions: widget.reactions,
      reactionListenableForMessage: widget.reactionListenableForMessage,
      ownPeerId: widget.ownPeerId,
      onMessageLongPress: widget.onMessageLongPress,
      onReactionTap: widget.onReactionTap,
    );
  }

  Widget _buildCollapsedBody() {
    final enabled = widget.onInlineSend != null && !widget.thread.isBlocked;
    return CollapsedModeCardBody(
      thread: widget.thread,
      sessionReply: widget.sessionReply,
      isExpanded: widget.isExpanded,
      onTapExpand: widget.onToggleExpand,
      onCollapse: widget.onToggleExpand,
      onViewFullConversation: widget.onViewFullConversation,
      onQuoteReply: widget.onQuoteReply,
      onSend: (text) => widget.onInlineSend?.call(text),
      sendEnabled: enabled,
      initialText: widget.initialText,
      shouldRequestFocus: widget.shouldRequestFocus,
      onDraftChanged: widget.onDraftChanged,
      onInputFocusChanged: widget.onInputFocusChanged,
      onAttach: widget.onAttach,
      reactions: widget.reactions,
      reactionListenableForMessage: widget.reactionListenableForMessage,
      ownPeerId: widget.ownPeerId,
      onMessageLongPress: widget.onMessageLongPress,
      onReactionTap: widget.onReactionTap,
    );
  }

  Widget _buildBlockedOverlay() {
    return Positioned.fill(
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
    );
  }
}
