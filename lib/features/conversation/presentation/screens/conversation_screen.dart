import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/blocked_banner.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compact_origin_marker.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/empty_conversation_state.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

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
          // Compose area or blocked banner
          if (widget.isBlocked)
            BlockedBanner(onUnblock: widget.onUnblock)
          else
            ComposeArea(onSend: widget.onSend),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return SingleChildScrollView(
      key: const ValueKey('messages'),
      controller: widget.scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: [
          // Origin marker
          CompactOriginMarker(
            contactPeerId: widget.contactPeerId,
            connectionDate: widget.connectionDate,
          ),
          // Messages with date separators and staggered animations
          ..._buildMessagesWithSeparators(),
        ],
      ),
    );
  }

  List<Widget> _buildMessagesWithSeparators() {
    final widgets = <Widget>[];
    String? lastDateLabel;

    for (var i = 0; i < widget.messages.length; i++) {
      final message = widget.messages[i];
      final dateLabel = _formatDateLabel(message.timestamp);

      if (dateLabel != lastDateLabel) {
        widgets.add(DateSeparator(label: dateLabel));
        lastDateLabel = dateLabel;
      }

      final isNew = i == widget.messages.length - 1 && _wasEmpty;

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _AnimatedLetterCard(
            key: ValueKey(message.id),
            delayMs: 0,
            isNewMessage: isNew,
            child: LetterCard(
              senderPeerId: message.senderPeerId,
              senderName: message.isIncoming
                  ? widget.contactUsername
                  : 'You',
              text: message.text,
              time: _formatTime(message.timestamp),
              isIncoming: message.isIncoming,
              status: message.isIncoming ? null : message.status,
            ),
          ),
        ),
      );
    }

    // Reset transition state after build
    if (_wasEmpty && widget.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _wasEmpty = false;
      });
    }

    return widgets;
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
