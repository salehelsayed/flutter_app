part of 'orbit_depth_prototype_screen.dart';

// A chat opened from the orbit: your Close ring folds out of depth into a
// row above the chat, so the people you talk to most come with you. A face in
// the row switches the chat; back flies every face home.

/// Names whose orbit face is hidden while a stand-in flies.
final ValueNotifier<Set<String>> _flying = ValueNotifier(const {});

/// The row a chat opened from the orbit carries. The order is fixed when the
/// chat opens, so switching moves the highlight, never a face under a finger.
class _ChatStrip {
  final List<String> order;

  /// Where each face sat on the orbit when the chat opened, in global
  /// coordinates. Missing for a face that was not on screen.
  final Map<String, Rect> from;
  final ValueNotifier<String> current;

  _ChatStrip(this.order, this.from, String first)
    : current = ValueNotifier(first);
}

const _stripRowHeight = 64.0;
const _stripFace = 40.0;
const _stripFaceOn = 46.0;
const _stripPitch = 52.0;
const _stripLead = 52.0;
const _dmGround = Color(0xFF0C0E14);

/// The centre of face [i] in a row whose top edge is at [top].
Offset _stripCentre(int i, double top) => Offset(
  _stripLead + _stripPitch * i + _stripPitch / 2,
  top + _stripRowHeight / 2,
);

double _span(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

/// Opens your chat with [friend] from a face on the orbit.
void _openDmFromOrbit(
  BuildContext context,
  _ProtoFriend friend, {
  _Quote? quote,
}) {
  HapticFeedback.selectionClick();
  FocusScope.of(context).unfocus();
  final width = MediaQuery.sizeOf(context).width;
  final fit = math.max(1, ((width - _stripLead - 8) / _stripPitch).floor());
  final order = [
    friend.name,
    for (final f in _friends)
      if (f.layer == 0 && f.more == 0 && f.name != friend.name) f.name,
  ].take(fit).toList();
  final strip = _ChatStrip(order, _orbitFaceRects(context, order), friend.name);
  Navigator.of(context).push(
    _FlattenRoute(
      strip,
      _DmScreen(name: friend.name, quote: quote, strip: strip),
      instant: MediaQuery.disableAnimationsOf(context),
    ),
  );
}

/// Where the orbit drew each of [names], found by its avatar key.
Map<String, Rect> _orbitFaceRects(BuildContext context, List<String> names) {
  final want = <Key, String>{for (final n in names) ValueKey('avatar-$n'): n};
  final found = <String, Rect>{};
  void visit(Element e) {
    final name = want[e.widget.key];
    if (name != null) {
      final box = e.renderObject;
      if (box is RenderBox && box.attached && box.hasSize) {
        found[name] = box.localToGlobal(Offset.zero) & box.size;
      }
      return;
    }
    e.visitChildren(visit);
  }

  context.visitChildElements(visit);
  return found;
}

class _FlattenRoute extends PageRoute<void> {
  final _ChatStrip strip;
  final Widget page;
  final bool instant;

  _FlattenRoute(this.strip, this.page, {required this.instant});

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  /// The orbit stays where it is under the chat, so the faces have somewhere
  /// to fly home to, rather than diving away the way it does for other pages.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  Duration get transitionDuration =>
      instant ? Duration.zero : const Duration(milliseconds: 440);

  @override
  Duration get reverseTransitionDuration =>
      instant ? Duration.zero : const Duration(milliseconds: 360);

  @override
  AnimationController createAnimationController() {
    final controller = super.createAnimationController();
    controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) _flying.value = const {};
    });
    return controller;
  }

  @override
  TickerFuture didPush() {
    _flying.value = {...strip.order};
    return super.didPush();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => page;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, strip.current]),
      child: child,
      builder: (context, child) {
        final t = animation.value;
        final flying = animation.status != AnimationStatus.completed && t > 0;
        final top = MediaQuery.paddingOf(context).top;
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.5 * _span(t, 0, 0.6)),
                ),
              ),
            ),
            Positioned.fill(child: child!),
            if (flying)
              for (var i = 0; i < strip.order.length; i++)
                _ghost(strip.order[i], i, t, top),
          ],
        );
      },
    );
  }

  /// The face standing in for [name] on its way between the orbit and slot
  /// [i]; later faces leave a little later.
  Widget _ghost(String name, int i, double t, double top) {
    final on = name == strip.current.value;
    final slot = Rect.fromCircle(
      center: _stripCentre(i, top),
      radius: (on ? _stripFaceOn : _stripFace) / 2,
    );
    final from = strip.from[name];
    final k = Curves.easeInOutCubic.transform(
      _span(t, i * 0.04, 0.72 + i * 0.04),
    );
    final rect = Rect.lerp(from ?? slot, slot, k)!;
    return Positioned.fromRect(
      key: ValueKey('strip-ghost-$name'),
      rect: rect,
      child: IgnorePointer(
        child: Opacity(
          opacity: from == null ? _span(t, 0.3, 0.9) : 1,
          child: _personPhoto(name, rect.width),
        ),
      ),
    );
  }
}

/// Back, then the row of faces. The open chat's face is larger and ringed.
class _ChatStripBar extends StatelessWidget {
  final _ChatStrip strip;
  final ValueChanged<String> onPick;

  /// Hidden while stand-ins fly in or out.
  final bool facesShown;

  const _ChatStripBar({
    required this.strip,
    required this.onPick,
    required this.facesShown,
  });

  @override
  Widget build(BuildContext context) {
    final current = strip.current.value;
    return SizedBox(
      key: const ValueKey('chat-strip'),
      height: _stripRowHeight,
      child: Stack(
        children: [
          Positioned(
            left: 4,
            top: (_stripRowHeight - 48) / 2,
            child: IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back, color: _ink),
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.of(context).maybePop();
              },
            ),
          ),
          for (var i = 0; i < strip.order.length; i++)
            _face(context, strip.order[i], i, strip.order[i] == current),
        ],
      ),
    );
  }

  Widget _face(BuildContext context, String name, int i, bool on) {
    final size = on ? _stripFaceOn : _stripFace;
    final friend = _friends.where((f) => f.name == name).firstOrNull;
    return Positioned.fromRect(
      rect: Rect.fromCircle(
        center: _stripCentre(i, 0),
        radius: _stripPitch / 2,
      ),
      child: Opacity(
        opacity: facesShown ? 1 : 0,
        child: Semantics(
          button: true,
          selected: on,
          label: on ? '$name, open' : 'Chat with $name',
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('strip-face-$name'),
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                on ? _openWorld(context, name, fromChat: true) : onPick(name),
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: on ? Border.all(color: _accent, width: 2) : null,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(on ? 2 : 0),
                      child: _personPhoto(name, on ? size - 4 : size),
                    ),
                  ),
                  if (!on && friend != null && _isNew(friend))
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: _dmGround, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
