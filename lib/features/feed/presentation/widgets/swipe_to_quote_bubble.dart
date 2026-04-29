import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';

/// Right-swipe gesture wrapper for received message bubbles.
///
/// Reveals a reply icon behind the bubble as it slides right.
/// At 50% of trigger width → fires [onQuoteTriggered] and snaps back.
class SwipeToQuoteBubble extends StatefulWidget {
  final Widget child;
  final VoidCallback onQuoteTriggered;

  const SwipeToQuoteBubble({
    super.key,
    required this.child,
    required this.onQuoteTriggered,
  });

  @override
  State<SwipeToQuoteBubble> createState() => _SwipeToQuoteBubbleState();
}

class _SwipeToQuoteBubbleState extends State<SwipeToQuoteBubble>
    with SingleTickerProviderStateMixin {
  static const _triggerWidth = 72.0;
  static const _directionThreshold = 8.0;

  late final AnimationController _controller;
  double _dragOffset = 0;
  bool _isDragging = false;
  bool _directionLocked = false;
  bool _isHorizontalDrag = false;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _controller.addListener(() {
      setState(() {
        _dragOffset = _controller.value * _triggerWidth;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    _isDragging = true;
    _directionLocked = false;
    _isHorizontalDrag = false;
    _triggered = false;
    _controller.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final dx = details.delta.dx;
    final dy = details.delta.dy;

    if (!_directionLocked) {
      final totalDx =
          details.localPosition.dx - (details.localPosition.dx - dx);
      final totalDy =
          details.localPosition.dy - (details.localPosition.dy - dy);
      if (totalDx.abs() > _directionThreshold ||
          totalDy.abs() > _directionThreshold) {
        _directionLocked = true;
        _isHorizontalDrag = dx.abs() >= dy.abs();
      }
      if (!_directionLocked) return;
    }

    if (!_isHorizontalDrag) return;

    setState(() {
      _dragOffset += dx;
      // Right-swipe only: clamp to [0, triggerWidth * 1.5] with rubber-banding
      if (_dragOffset > _triggerWidth) {
        final excess = _dragOffset - _triggerWidth;
        _dragOffset = _triggerWidth + excess * 0.3;
      }
      _dragOffset = _dragOffset.clamp(0.0, _triggerWidth * 1.5);

      // Trigger at 50% threshold
      if (!_triggered && _dragOffset >= _triggerWidth * 0.5) {
        _triggered = true;
        widget.onQuoteTriggered();
      }
    });
  }

  void _onDragEnd(DragEndDetails details) {
    _isDragging = false;
    // Always snap back to origin
    final startValue = _dragOffset / _triggerWidth;
    _controller.value = startValue;
    _controller.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragOffset / _triggerWidth).clamp(0.0, 1.0);
    final readableColors = context.backgroundReadableColors;
    final accentColor = readableColors.isLightSurface
        ? const Color(0xFF0F8F87)
        : FeedColors.accentTeal;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Reply icon revealed behind bubble
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.5 + 0.5 * progress,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withValues(alpha: 0.15),
                    ),
                    child: Icon(
                      Icons.reply_rounded,
                      size: 18,
                      color: accentColor.withValues(alpha: 0.80),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Sliding bubble
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
