import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A tap outside the focused text field hides the keyboard, as users expect
/// on phones. Flutter's own default keeps it up for touch on Android and iOS.
///
/// Only a real tap counts: the finger never moves past touch slop, even on
/// the way back, and lifts before a long press. A scroll drag or a long press
/// outside keeps the keyboard. Controls that belong to a field, such as a
/// composer's send button, sit in a [TextFieldTapRegion] and never count as
/// outside.
class TapOutsideHidesKeyboard extends StatefulWidget {
  const TapOutsideHidesKeyboard({super.key, required this.child});

  final Widget child;

  @override
  State<TapOutsideHidesKeyboard> createState() =>
      _TapOutsideHidesKeyboardState();
}

class _TapOutsideHidesKeyboardState extends State<TapOutsideHidesKeyboard> {
  /// Pointers still eligible to be a tap: where and when they went down.
  final _taps = <int, (Offset, DateTime)>{};

  late final Map<Type, Action<Intent>> _actions = {
    EditableTextTapUpOutsideIntent:
        CallbackAction<EditableTextTapUpOutsideIntent>(
          onInvoke: (intent) {
            final up = intent.pointerUpEvent;
            if (_taps.remove(up.pointer) case (
              _,
              final since,
            ) when clock.now().difference(since) < kLongPressTimeout) {
              intent.focusNode.unfocus();
            }
            return null;
          },
        ),
  };

  void _track(PointerMoveEvent event) {
    final down = _taps[event.pointer];
    if (down != null && (event.position - down.$1).distance > kTouchSlop) {
      _taps.remove(event.pointer);
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) =>
        _taps[event.pointer] = (event.position, clock.now()),
    onPointerMove: _track,
    onPointerCancel: (event) => _taps.remove(event.pointer),
    // The up intent, when there is one, runs before this up callback.
    onPointerUp: (event) => _taps.remove(event.pointer),
    child: Actions(actions: _actions, child: widget.child),
  );
}
