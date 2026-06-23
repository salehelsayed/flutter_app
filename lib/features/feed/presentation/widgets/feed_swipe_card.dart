import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';

/// 134-P6: the `Dismissible` host wrapper for a single Feed letter card.
///
/// Wraps [child] in a direction-gated [Dismissible] keyed by the item id:
///   * while the card is [focused] (the "send message" surface), EITHER swipe
///     direction LEAVES the thread → the host's leave handler goes back when no
///     reply was sent and commits (marks read + cleared) when one was. A teal
///     "back" indicator shows on the trailing edge while dragging left, a GREEN
///     check on the leading edge while dragging right.
///   * while the card is RESTING (not focused), swipe-LEFT (`endToStart`) →
///     DISMISS (cleared-only, RED indicator); swipe-RIGHT is inert.
///
/// Removal is STORE-DRIVEN: `confirmDismiss` invokes [onCommit] / [onDismissThread]
/// (which `markCleared` → the feed store re-projects → the item disappears) and
/// then returns `false`, so the `Dismissible` springs back rather than removing
/// the widget itself. This avoids the "dismissed widget still in the tree"
/// assertion AND keeps the cleared-watermark store as the single removal source.
///
/// [onSwipeStart] / [onSwipeEnd] fire on horizontal drag start / settle so the
/// caller can gate the screen-level Feed↔Orbit host swipe (gesture arena, TC-35).
class FeedSwipeCard extends StatelessWidget {
  /// Whether the wrapped card is currently focused. Gates which swipe direction
  /// is permitted (right→commit only while focused; left→dismiss only resting).
  final bool focused;

  /// Invoked when a swipe-RIGHT commit crosses the threshold on a focused card.
  final VoidCallback onCommit;

  /// Invoked when a swipe-LEFT dismiss crosses the threshold on a resting card.
  final VoidCallback onDismissThread;

  /// Fires when a horizontal drag on this card starts (arena gate → active).
  final VoidCallback onSwipeStart;

  /// Fires when a horizontal drag on this card settles (arena gate → inactive).
  final VoidCallback onSwipeEnd;

  /// 134 §7: when true (platform reduced-motion), the spring-back
  /// [movementDuration] collapses to zero (instant settle, no animation).
  final bool reduceMotion;

  final Widget child;

  /// Dismiss fraction (~0.25 ≈ 92px on a typical phone width) for both gates.
  static const double dismissFraction = 0.25;

  const FeedSwipeCard({
    required Key key,
    required this.focused,
    required this.onCommit,
    required this.onDismissThread,
    required this.onSwipeStart,
    required this.onSwipeEnd,
    required this.child,
    this.reduceMotion = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = context.feedTokens;

    return Dismissible(
      key: key!,
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: dismissFraction,
        DismissDirection.endToStart: dismissFraction,
      },
      // Left edge: GREEN check, revealed while dragging RIGHT (commit).
      background: _SwipeIndicatorBackground(
        key: const ValueKey('feed-swipe-commit-indicator'),
        alignment: Alignment.centerLeft,
        color: tokens.green500,
        fill: tokens.greenFill15,
        icon: Icons.check_rounded,
      ),
      // Right edge, revealed while dragging LEFT. On a focused card this is a
      // neutral teal "back" affordance (left-swipe leaves the thread); on a
      // resting card it is the RED dismiss indicator.
      secondaryBackground: focused
          ? _SwipeIndicatorBackground(
              key: const ValueKey('feed-swipe-back-indicator'),
              alignment: Alignment.centerRight,
              color: tokens.teal400,
              fill: tokens.tealFill08,
              icon: Icons.arrow_back_rounded,
            )
          : _SwipeIndicatorBackground(
              key: const ValueKey('feed-swipe-dismiss-indicator'),
              alignment: Alignment.centerRight,
              color: _dismissRed,
              fill: _dismissRedFill,
              icon: Icons.close_rounded,
            ),
      movementDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      confirmDismiss: (direction) async {
        if (focused) {
          // "Swipe away" the send-message surface in EITHER direction. The host
          // leave handler ([onCommit] → _leaveFocusedThread) goes back when no
          // reply was sent and commits (read + cleared) when one was — so a
          // left-swipe is no longer a dead no-op.
          onCommit();
        } else if (direction == DismissDirection.endToStart) {
          // Resting card: swipe-LEFT dismisses (cleared-only); right is inert.
          onDismissThread();
        }
        // ALWAYS spring back — removal is store-driven (re-projection drops the
        // item). Returning true would let Dismissible remove the widget and trip
        // the "dismissed widget still in tree" assertion.
        return false;
      },
      child: _SwipeStartEndTracker(
        onSwipeStart: onSwipeStart,
        onSwipeEnd: onSwipeEnd,
        child: child,
      ),
    );
  }

  // Dismiss-side RED is not a feed token (FeedTokens has no red); use a fixed
  // destructive red consistent with Material error accents.
  static const Color _dismissRed = Color(0xFFEF4444);
  static const Color _dismissRedFill = Color(0x26EF4444);
}

/// Reports the horizontal-drag start/settle edges to the arena gate. A
/// `Dismissible` claims the horizontal gesture itself (so the card tap is
/// suppressed and vertical scroll still wins via the built-in axis handling);
/// this listener only needs the start/end boolean edges, so it taps the
/// horizontal-drag lifecycle via a non-claiming [Listener] wrapper around the
/// drag region.
class _SwipeStartEndTracker extends StatefulWidget {
  final VoidCallback onSwipeStart;
  final VoidCallback onSwipeEnd;
  final Widget child;

  const _SwipeStartEndTracker({
    required this.onSwipeStart,
    required this.onSwipeEnd,
    required this.child,
  });

  @override
  State<_SwipeStartEndTracker> createState() => _SwipeStartEndTrackerState();
}

class _SwipeStartEndTrackerState extends State<_SwipeStartEndTracker> {
  bool _active = false;
  Offset? _down;

  void _markActive() {
    if (_active) return;
    _active = true;
    widget.onSwipeStart();
  }

  void _markInactive() {
    if (!_active) return;
    _active = false;
    widget.onSwipeEnd();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _down = event.position;
      },
      onPointerMove: (event) {
        final start = _down;
        if (start == null) return;
        final delta = event.position - start;
        // Activate the arena gate once the move is recognizably horizontal —
        // BEFORE the host's ~12px claim and the Dismissible's ~18px slop, so the
        // host yields the gesture to the card swipe.
        if (delta.dx.abs() >= 6 && delta.dx.abs() > delta.dy.abs()) {
          _markActive();
        }
      },
      onPointerUp: (_) {
        _down = null;
        _markInactive();
      },
      onPointerCancel: (_) {
        _down = null;
        _markInactive();
      },
      child: widget.child,
    );
  }
}

class _SwipeIndicatorBackground extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final Color fill;
  final IconData icon;

  const _SwipeIndicatorBackground({
    required Key key,
    required this.alignment,
    required this.color,
    required this.fill,
    required this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = context.feedTokens;
    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(tokens.radiusFull),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Icon(icon, color: color, size: 26),
    );
  }
}
