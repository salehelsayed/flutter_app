import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

extension GestureDetectorPressFeedback on GestureDetector {
  Widget withPressFeedback() {
    final detectorKey = key;
    return _PressFeedback(
      key: detectorKey == null ? null : ValueKey<Key>(detectorKey),
      child: this,
    );
  }
}

class _PressFeedback extends StatefulWidget {
  const _PressFeedback({super.key, required this.child});

  final GestureDetector child;

  @override
  State<_PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<_PressFeedback> {
  static const _duration = Duration(milliseconds: 120);
  static const _curve = Cubic(0.23, 1, 0.32, 1);
  static final _claimedDownEvents = Expando<bool>();

  PointerDownEvent? _down;

  void _handleDown(PointerDownEvent event) {
    if (widget.child.onTap == null || event.buttons != kPrimaryButton) {
      return;
    }
    // Flutter dispatches to the inner hit first. Animate only that control.
    final original = event.original ?? event;
    if (_claimedDownEvents[original] == true) return;
    _claimedDownEvents[original] = true;

    if (_down == null && MediaQuery.maybeDisableAnimationsOf(context) != true) {
      setState(() => _down = event);
    }
  }

  void _handleMove(PointerMoveEvent event) {
    final down = _down;
    if (down != null &&
        (event.position - down.position).distance > kTouchSlop) {
      _handleEnd(event);
    }
  }

  void _handleEnd(PointerEvent event) {
    if (_down?.pointer == event.pointer) {
      setState(() => _down = null);
    }
  }

  @override
  void dispose() {
    _down = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final pressed =
        _down != null && widget.child.onTap != null && !reduceMotion;
    return Listener(
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleEnd,
      onPointerCancel: _handleEnd,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: pressed ? 0.97 : 1),
        duration: reduceMotion ? Duration.zero : _duration,
        curve: _curve,
        child: widget.child,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          transformHitTests: false,
          child: child,
        ),
      ),
    );
  }
}
