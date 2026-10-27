import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A tap outside the focused text field hides the keyboard, as users expect
/// on phones. Flutter's own default keeps it up for touch on Android and iOS.
///
/// Only a real tap counts: the finger lifts near where it went down and
/// before a long press. A scroll drag or a long press outside keeps the
/// keyboard. Controls that belong to a field, such as a composer's send
/// button, sit in that field's [TextFieldTapRegion] and never count as
/// outside.
class TapOutsideHidesKeyboard extends StatefulWidget {
  const TapOutsideHidesKeyboard({super.key, required this.child});

  final Widget child;

  @override
  State<TapOutsideHidesKeyboard> createState() =>
      _TapOutsideHidesKeyboardState();
}

class _TapOutsideHidesKeyboardState extends State<TapOutsideHidesKeyboard> {
  final _downs = <int, (Offset, DateTime)>{};

  late final Map<Type, Action<Intent>> _actions = {
    EditableTextTapOutsideIntent: CallbackAction<EditableTextTapOutsideIntent>(
      onInvoke: (intent) {
        final down = intent.pointerDownEvent;
        _downs[down.pointer] = (down.position, clock.now());
        return null;
      },
    ),
    EditableTextTapUpOutsideIntent:
        CallbackAction<EditableTextTapUpOutsideIntent>(
          onInvoke: (intent) {
            final up = intent.pointerUpEvent;
            final down = _downs.remove(up.pointer);
            if (down case (final at, final since)?
                when (up.position - at).distance <= kTouchSlop &&
                    clock.now().difference(since) < kLongPressTimeout) {
              intent.focusNode.unfocus();
            }
            return null;
          },
        ),
  };

  @override
  Widget build(BuildContext context) =>
      Actions(actions: _actions, child: widget.child);
}
