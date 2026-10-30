import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/orbit_depth_geometry.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'orbit_depth_media.dart';

/// The production flat surface remains mounted below this local dial. Data,
/// downloads, seen writes and destinations remain the wired host's authority.
class OrbitDepthSurface extends StatefulWidget {
  const OrbitDepthSurface({
    super.key,
    required this.child,
    required this.items,
    required this.thoughts,
    required this.onFriendTap,
    required this.onThoughtTap,
    this.active = true,
    this.gesturesEnabled = true,
    this.topClearance = 0,
    this.bottomClearance = 0,
    this.resetSignal,
    this.nowProvider,
    this.onOwnsHostGestureChanged,
    this.onBackActionChanged,
    this.onThoughtDeparted,
    this.onSettled,
    this.onThoughtsExpired,
    this.loadMedia,
    this.downloadMedia,
  });
  final Widget child;
  final List<OrbitItem> items;
  final Map<String, PostModel> thoughts;
  final bool active;
  final bool gesturesEnabled;

  /// Host chrome (the header row) that the dial must stay below.
  final double topClearance;

  /// Host chrome (the persistent nav band) that the dial must stay above.
  final double bottomClearance;
  final Listenable? resetSignal;
  final DateTime Function()? nowProvider;
  final ValueChanged<bool>? onOwnsHostGestureChanged;
  final ValueChanged<VoidCallback?>? onBackActionChanged;
  final ValueChanged<String>? onThoughtDeparted;

  /// The view came to rest: its ring, the friend in the center, and whether a
  /// sideways turn brought it there. Also called with flat after a reset.
  /// Always delivered after the current frame.
  final void Function(OrbitDepthLayer layer, String? frontPeerId, bool turned)?
  onSettled;
  final VoidCallback? onThoughtsExpired;
  final ValueChanged<OrbitFriend> onFriendTap;
  final ValueChanged<String>? onThoughtTap;
  final Future<List<PostMediaAttachmentModel>> Function(String)? loadMedia;
  final Future<PostMediaAttachmentModel> Function(PostMediaAttachmentModel)?
  downloadMedia;
  @override
  State<OrbitDepthSurface> createState() => _OrbitDepthSurfaceState();
}

/// Where the flat orbit showed each queued friend, and You, when the drag
/// into depth began, in this surface's coordinates.
typedef _FlatSeats = ({Map<String, Rect> faces, Rect? self});

typedef _DepthLanding = ({
  int generation,
  String? departedPostId,
  bool markDeparture,
  bool byTurn,
});

class _OrbitDepthSurfaceState extends State<OrbitDepthSurface>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _vertical = AnimationController.unbounded(
    vsync: this,
  );

  /// The turn position: friend `i` of the queue is `i - value` seats away
  /// from the center.
  late final AnimationController _turn = AnimationController.unbounded(
    vsync: this,
  );
  OrbitDepthLayer _layer = OrbitDepthLayer.flat;
  OrbitDepthAnchor _anchor = OrbitDepthAnchor.top;
  OrbitDepthGesture _gesture = OrbitDepthGesture.idle;
  String? _landedPostId;
  bool _owned = false;
  bool _routeActive = true;
  bool _foreground = true;
  bool _sequenceCancelled = false;
  // Retained through recognizer callbacks after raw pointer-up clears the map.
  bool _suppressTap = false;
  final _pointers = <int, Offset>{};
  Offset? _start;
  double _startVertical = 0;
  double _startTurn = 0;
  VelocityTracker? _velocity;
  int _settleGeneration = 0;
  _DepthLanding? _pendingLanding;
  Timer? _expiry;
  final _lastLoadedMedia = <String, List<PostMediaAttachmentModel>>{};
  Timer? _age;
  double _scale = 1;
  // The queue order is frozen for one visit into depth, so a re-sort of
  // friends (a new message) cannot move faces or swap the card under the
  // finger. Newcomers join at the end.
  List<String>? _order;
  _FlatSeats? _flat;
  List<String> _seated = const [];
  bool get _active => widget.active && _foreground;
  bool get _enabled => _active && _routeActive && widget.gesturesEnabled;
  bool get _depth => _layer != OrbitDepthLayer.flat || _vertical.value > 0.01;
  bool get _reduceMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  bool get _rtl => Directionality.of(context) == TextDirection.rtl;
  DateTime get _now => (widget.nowProvider ?? DateTime.now)().toUtc();

  List<OrbitDepthSeat> get _queue {
    final live = orbitDepthQueue(widget.items, widget.thoughts, _now);
    final order = _order;
    if (order == null) return live;
    final byPeer = {for (final seat in live) seat.friend.peerId: seat};
    return [
      for (final peer in order) ?byPeer.remove(peer),
      ...live.where((seat) => byPeer.containsKey(seat.friend.peerId)),
    ];
  }

  int? _centerIndex(int count, double turn) =>
      count == 0 ? null : turn.round() % count;

  OrbitDepthSeat? get _center {
    final queue = _queue;
    final index = _centerIndex(queue.length, _turn.value);
    return index == null ? null : queue[index];
  }

  double _stop(OrbitDepthLayer layer) => switch (layer) {
    OrbitDepthLayer.flat => 0,
    OrbitDepthLayer.inner => 320,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.resetSignal?.addListener(_reset);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_active) _reset(notifyBuild: false);
    final routeActive = ModalRoute.isCurrentOf(context) ?? true;
    if (routeActive != _routeActive) {
      _routeActive = routeActive;
      if (!routeActive) {
        _hold();
      } else if (_depth) {
        _publish(true);
      }
    }
    if (_reduceMotion) _land();
  }

  /// Lands every controller at its stop and finishes any pending landing.
  void _land() {
    final pending = _pendingLanding;
    _vertical.stop();
    _turn.stop();
    _vertical.value = _stop(_layer);
    _turn.value = _turn.value.roundToDouble();
    if (pending != null) _completeLanding(pending);
  }

  // A covering route (the card, a chat) freezes the dial at its stop and lends
  // the host its gestures back. Ring, anchor and center friend wait for the
  // pop.
  void _hold() {
    _gesture = OrbitDepthGesture.idle;
    _pointers.clear();
    _start = null;
    _land();
    _publish(false);
  }

  @override
  void didUpdateWidget(covariant OrbitDepthSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetSignal != widget.resetSignal) {
      oldWidget.resetSignal?.removeListener(_reset);
      widget.resetSignal?.addListener(_reset);
    }
    if (!_active || !widget.gesturesEnabled) _reset(notifyBuild: false);
    _reseat();
    _armTimers();
  }

  /// Keeps the friend in the center there when friends join or leave the
  /// queue, so the indices shifting under them cannot change who is shown.
  void _reseat() {
    final peers = [for (final seat in _queue) seat.friend.peerId];
    final previous = _seated;
    _seated = peers;
    if (!_depth || previous.isEmpty || peers.isEmpty) return;
    final oldIndex = _centerIndex(previous.length, _turn.value)!;
    final newIndex = peers.indexOf(previous[oldIndex]);
    if (newIndex == oldIndex && peers.length == previous.length) return;
    final pending = _pendingLanding;
    final turning = _turn.isAnimating;
    if (turning) _turn.stop();
    final seat = newIndex < 0 ? math.min(oldIndex, peers.length - 1) : newIndex;
    final drift = turning ? 0.0 : _turn.value - _turn.value.round();
    _turn.value = seat + drift;
    if (newIndex < 0) {
      // The friend in the center left: whoever takes the seat just arrived.
      _landedPostId = _center?.thought.id;
    }
    if (turning && pending != null) _completeLanding(pending);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A shade, Control Center or permission dialog only makes the app
    // inactive; the ring survives that and resets once the app is hidden.
    _foreground = switch (state) {
      AppLifecycleState.resumed || AppLifecycleState.inactive => true,
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => false,
    };
    if (!_foreground) _reset();
  }

  void _publish(bool owned) {
    if (_owned == owned) return;
    _owned = owned;
    // This callback deliberately runs before Feed receives the same raw move.
    widget.onOwnsHostGestureChanged?.call(owned);
    widget.onBackActionChanged?.call(owned ? _stepBack : null);
  }

  void _reset({bool notifyBuild = true}) {
    if (_layer != OrbitDepthLayer.flat) {
      // Resets also run during build; tell the host after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSettled?.call(OrbitDepthLayer.flat, null, false);
      });
    }
    ++_settleGeneration;
    _pendingLanding = null;
    _vertical.stop();
    _turn.stop();
    _vertical.value = 0;
    _turn.value = 0;
    _layer = OrbitDepthLayer.flat;
    _gesture = OrbitDepthGesture.idle;
    _landedPostId = null;
    _order = null;
    _flat = null;
    _pointers.clear();
    _start = null;
    _sequenceCancelled = false;
    _expiry?.cancel();
    _age?.cancel();
    _publish(false);
    if (notifyBuild && mounted) setState(() {});
  }

  void _armTimers() {
    _expiry?.cancel();
    _age?.cancel();
    if (!_active || !_depth) return;
    final expiries =
        widget.thoughts.values
            .map((post) => DateTime.tryParse(post.expiresAt)?.toUtc())
            .whereType<DateTime>()
            .where((expiry) => expiry.isAfter(_now))
            .toList()
          ..sort();
    if (expiries.isNotEmpty) {
      _expiry = Timer(expiries.first.difference(_now), () {
        if (!mounted || !_active) return;
        setState(_reseat);
        widget.onThoughtsExpired?.call();
        _armTimers();
      });
    }
    _age = Timer(const Duration(minutes: 1), () {
      if (mounted && _active) {
        setState(() {});
        _armTimers();
      }
    });
  }

  static double _smooth(double value) {
    final k = value.clamp(0.0, 1.0);
    return k * k * (3 - 2 * k);
  }

  /// The flat orbit's avatars are keyed by peer id and its own photo by
  /// `orbit-center-self-avatar`; measuring them is what lets each face fly
  /// from where the user just saw it, whatever the orbit's geometry knobs.
  _FlatSeats _measureFlat() {
    final surface = context.findRenderObject();
    final wanted = {for (final seat in _queue) seat.friend.peerId};
    final faces = <String, Rect>{};
    Rect? self;
    void visit(Element element) {
      if (element.widget.key case ValueKey<String>(
        :final value,
      ) when wanted.contains(value) || value == 'orbit-center-self-avatar') {
        final box = element.renderObject;
        if (box is RenderBox && box.hasSize && box.attached) {
          final rect =
              box.localToGlobal(Offset.zero, ancestor: surface) & box.size;
          if (value == 'orbit-center-self-avatar') {
            self ??= rect;
          } else {
            faces[value] ??= rect;
          }
        }
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return (faces: faces, self: self);
  }

  Future<void> _spring(
    AnimationController controller,
    double target,
    SpringDescription spring, {
    double velocity = 0,
  }) async {
    if (_reduceMotion || (controller.value - target).abs() < .001) {
      controller.value = target;
      return;
    }
    await controller
        .animateWith(
          SpringSimulation(spring, controller.value, target, velocity),
        )
        .orCancel;
    controller.value = target;
  }

  /// [verticalVelocity] is the release speed, in tilt units per second, so a
  /// flick glides into its stop instead of restarting from rest. [turnTo] is
  /// the turn position to come to rest at; [turnVelocity] is in seats per
  /// second.
  Future<void> _settle(
    OrbitDepthLayer target, {
    double? turnTo,
    bool markDeparture = true,
    double verticalVelocity = 0,
    double turnVelocity = 0,
    bool byTurn = false,
  }) async {
    final generation = ++_settleGeneration;
    final landing = (
      generation: generation,
      departedPostId: _landedPostId,
      markDeparture: markDeparture,
      byTurn: byTurn,
    );
    _pendingLanding = landing;
    if (_layer == OrbitDepthLayer.flat && target != OrbitDepthLayer.flat) {
      _flat ??= _measureFlat();
      // Every visit starts with the friend the user chatted with last.
      _order = [for (final seat in _queue) seat.friend.peerId];
      _seated = _order!;
      _turn.value = 0;
    }
    _layer = target;
    _gesture = OrbitDepthGesture.idle;
    if (target != OrbitDepthLayer.flat) _publish(true);
    setState(() {});
    try {
      await Future.wait([
        _spring(
          _vertical,
          _stop(target),
          const SpringDescription(mass: 1, stiffness: 170, damping: 19),
          velocity: verticalVelocity,
        ),
        _spring(
          _turn,
          turnTo ?? _turn.value.roundToDouble(),
          const SpringDescription(mass: 1, stiffness: 60, damping: 15.5),
          velocity: turnVelocity,
        ),
      ]);
      _completeLanding(landing);
    } on TickerCanceled {
      /* A newer gesture or reset owns the surface. */
    }
  }

  // Both spring completion and Reduce Motion land here. Stopping a ticker
  // alone cancels its future; it must not strand route/Feed ownership.
  void _completeLanding(_DepthLanding landing) {
    if (!mounted ||
        !_active ||
        landing.generation != _settleGeneration ||
        _pendingLanding?.generation != landing.generation) {
      return;
    }
    _pendingLanding = null;
    // A landing can complete during build (Reduce Motion); tell the host
    // after the frame.
    final layer = _layer;
    final center = _layer == OrbitDepthLayer.flat ? null : _center;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onSettled?.call(layer, center?.friend.peerId, landing.byTurn);
      }
    });
    final next = center?.thought.id;
    _landedPostId = next;
    if (landing.markDeparture &&
        landing.departedPostId != null &&
        landing.departedPostId != next) {
      widget.onThoughtDeparted?.call(landing.departedPostId!);
    }
    if (_layer == OrbitDepthLayer.flat) {
      _order = null;
      _flat = null;
      _publish(false);
    }
    _armTimers();
    setState(() {});
  }

  void _stepBack() {
    if (!_active || !_depth) return;
    unawaited(_settle(OrbitDepthLayer.flat));
  }

  /// One seat of horizontal finger travel.
  double get _seatTravel => orbitCenterRadius * _scale;

  /// The next friend waits on the right in a left-to-right app and on the
  /// left in a right-to-left one, so pulling it in follows the finger.
  double get _turnSign => _rtl ? 1 : -1;

  void _down(PointerDownEvent event) {
    if (!_enabled) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length > 1) {
      _suppressTap = true;
      _sequenceCancelled = true;
      ++_settleGeneration;
      _pendingLanding = null;
      _gesture = OrbitDepthGesture.pinch;
      if (_depth) {
        _publish(true);
        _vertical.stop();
        _turn.stop();
        _vertical.value = _stop(_layer);
        _turn.value = _turn.value.roundToDouble();
        setState(() {});
      }
      return;
    }
    _sequenceCancelled = false;
    _suppressTap = false;
    _start = event.localPosition;
    _startVertical = _vertical.value;
    _startTurn = _turn.value;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
  }

  void _move(PointerMoveEvent event) {
    if (!_enabled || !_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length > 1 || _sequenceCancelled || _start == null) return;
    _velocity?.addPosition(event.timeStamp, event.localPosition);
    final delta = event.localPosition - _start!;
    if (_gesture == OrbitDepthGesture.idle) {
      if (delta.distance < 10) return;
      if (delta.dy.abs() > delta.dx.abs()) {
        _gesture = OrbitDepthGesture.vertical;
        if (!_depth) {
          _anchor = delta.dy < 0
              ? OrbitDepthAnchor.top
              : OrbitDepthAnchor.bottom;
          _flat = _measureFlat();
        }
      } else if (_depth && _queue.length > 1) {
        _gesture = OrbitDepthGesture.turn;
      } else {
        _sequenceCancelled = true;
        return;
      }
      _suppressTap = true;
      ++_settleGeneration;
      _pendingLanding = null;
      _vertical.stop();
      _turn.stop();
      _startTurn = _turn.value;
      _publish(true);
    }
    if (_gesture == OrbitDepthGesture.vertical) {
      final direction = _anchor == OrbitDepthAnchor.top ? -1 : 1;
      _vertical.value = (_startVertical + direction * delta.dy / _scale).clamp(
        0,
        _stop(OrbitDepthLayer.inner),
      );
    } else if (_gesture == OrbitDepthGesture.turn) {
      final from = _startTurn.roundToDouble();
      _turn.value = (_startTurn + _turnSign * delta.dx / _seatTravel).clamp(
        from - 1,
        from + 1,
      );
    }
    setState(() {});
  }

  void _up(PointerEvent event, {bool cancelled = false}) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty) return;
    final gesture = _gesture;
    _gesture = OrbitDepthGesture.idle;
    if (_sequenceCancelled || cancelled) {
      _sequenceCancelled = false;
      if (_depth || _owned) unawaited(_settle(_layer, markDeparture: false));
      return;
    }
    if (gesture == OrbitDepthGesture.vertical) {
      final dy = _velocity?.getVelocity().pixelsPerSecond.dy ?? 0;
      final direction = _anchor == OrbitDepthAnchor.top ? -1 : 1;
      var value = _vertical.value;
      if (dy.abs() > 400) value = _startVertical + direction * dy.sign * 200;
      unawaited(
        _settle(
          value < 160 ? OrbitDepthLayer.flat : OrbitDepthLayer.inner,
          verticalVelocity: direction * dy / _scale,
        ),
      );
    } else if (gesture == OrbitDepthGesture.turn) {
      // One swipe moves exactly one seat; the flick speed seeds the spring.
      final dx = _velocity?.getVelocity().pixelsPerSecond.dx ?? 0;
      final speed = _turnSign * dx / _seatTravel;
      final from = _startTurn.roundToDouble();
      final reach = _turn.value - from + speed * .15;
      final step = reach > .3
          ? 1
          : reach < -.3
          ? -1
          : 0;
      unawaited(
        _settle(_layer, turnTo: from + step, turnVelocity: speed, byTurn: true),
      );
    }
  }

  void _tapFace(OrbitDepthSeat seat, int index, int count, double lift) {
    if (!_enabled || _suppressTap || _pointers.length > 1) return;
    if (lift > .5) {
      widget.onFriendTap(seat.friend);
      return;
    }
    final turn = _turn.value.roundToDouble();
    unawaited(
      _settle(
        _layer,
        turnTo: turn + orbitCenterWrap(index - turn, count).roundToDouble(),
        byTurn: true,
      ),
    );
  }

  @override
  void dispose() {
    widget.resetSignal?.removeListener(_reset);
    WidgetsBinding.instance.removeObserver(this);
    ++_settleGeneration;
    _expiry?.cancel();
    _age?.cancel();
    _publish(false);
    _vertical.dispose();
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_active || !_owned,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _stepBack();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: (event) => _up(event),
        onPointerCancel: (event) => _up(event, cancelled: true),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: _enabled ? (_) {} : null,
          onHorizontalDragStart: _enabled && _depth ? (_) {} : null,
          child: AnimatedBuilder(
            animation: Listenable.merge([_vertical, _turn]),
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final stage = Size(
                  constraints.maxWidth,
                  constraints.maxHeight -
                      widget.topClearance -
                      widget.bottomClearance,
                );
                _scale = math.min(stage.width / 390, stage.height / 640);
                final depth = _depth;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      ignoring: depth,
                      // The flat orbit's own clocks (note swim) rest under
                      // the stage instead of ticking unseen.
                      child: TickerMode(
                        enabled: !depth,
                        child: Opacity(
                          opacity: 1 - _smooth(_vertical.value / 320 / .45),
                          child: ScrollConfiguration(
                            behavior: _enabled
                                ? ScrollConfiguration.of(context).copyWith(
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                  )
                                : ScrollConfiguration.of(context),
                            child: widget.child,
                          ),
                        ),
                      ),
                    ),
                    if (depth && _active)
                      Positioned.fill(
                        top: widget.topClearance,
                        bottom: widget.bottomClearance,
                        child: RepaintBoundary(child: _dial(stage)),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _dial(Size size) {
    final k = _scale;
    final tiltProgress = (_vertical.value / 320).clamp(0.0, 1.0);
    final e = _smooth(tiltProgress);
    final top = _anchor == OrbitDepthAnchor.top;
    // The shipped 3D Orbit's placement: at the top, the ring sits as low as
    // its old waiting outer ring needed to stay clear of the header.
    final (outerFarEdge, _) = projectOrbitCenter(
      -math.pi / 2,
      orbitCenterRadius * k * 1.12 * 1.45,
      orbitCenterTilt,
    );
    final cy = top
        ? math.max(size.height * .084, 35 * k - outerFarEdge.dy)
        : size.height * .8;
    final ringDepth = orbitCenterRadius * k * math.cos(orbitCenterTilt);
    final center = Offset(size.width / 2, cy);
    final colors = Theme.of(context).colorScheme;
    final queue = _queue;
    // Faces fly from where the flat orbit showed them to their seats, as the
    // finger drags; a face the flat orbit did not show fades in at its seat.
    final lift = Offset(0, -widget.topClearance);
    final flat = _flat;
    final origin =
        flat?.self?.center.translate(0, lift.dy) ??
        Offset(size.width / 2, size.height * .5);
    final from = {
      for (final MapEntry(:key, :value) in (flat?.faces ?? const {}).entries)
        key: value.shift(lift),
    };
    final flatRadius = from.isEmpty
        ? orbitCenterRadius * k
        : from.values
              .map((rect) => (rect.center - origin).distance)
              .reduce(math.min);
    final faces = [
      for (final face in orbitCenterFaces(
        count: queue.length,
        pos: _turn.value,
        scale: k,
        nextOnRight: !_rtl,
      ))
        switch (from[queue[face.index].friend.peerId]) {
          final rect? => (
            index: face.index,
            offset: Offset.lerp(rect.center, center + face.offset, e)! - center,
            diameter: lerpDouble(rect.shortestSide, face.diameter, e)!,
            opacity: lerpDouble(1, face.opacity, e)!,
            darken: face.darken * e,
            lift: face.lift * e,
          ),
          null => (
            index: face.index,
            offset: face.offset,
            diameter: face.diameter,
            opacity: face.opacity * e,
            darken: face.darken,
            lift: face.lift * e,
          ),
        },
    ];
    final lifted = faces.isEmpty
        ? null
        : faces.reduce((a, b) => b.lift > a.lift ? b : a);
    final shown = lifted == null ? null : queue[lifted.index];
    final reveal = _smooth((tiltProgress - .5) / .5);
    final named = _smooth((tiltProgress - .65) / .35);
    final presence = _reduceMotion
        ? 1.0
        : math.pow(lifted?.lift ?? 0, 2).toDouble();
    final slotTop = top
        ? math.max(cy + ringDepth * 1.45 + 38 * k, 140 * k)
        : 60 * k;
    final slotBottom = top
        ? 20 * k
        : math.max(0.0, size.height - cy + ringDepth + 30 * k);
    Widget fade(String key, Widget? child) => _reduceMotion
        ? AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            // The default layout centres the child; the name and the thought
            // hang from the top of their slots.
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            child: child == null
                ? const SizedBox.shrink()
                : KeyedSubtree(
                    key: ValueKey('$key-${shown?.friend.peerId}'),
                    child: child,
                  ),
          )
        : child ?? const SizedBox.shrink();
    return Opacity(
      key: const ValueKey('orbit-depth-stage'),
      opacity: 1,
      child: Semantics(
        identifier: 'orbit.depth.${_layer.name}.${_anchor.name}',
        child: Stack(
          key: ValueKey('orbit-depth-${_layer.name}-${_anchor.name}'),
          fit: StackFit.expand,
          children: [
            CustomPaint(
              key: const ValueKey('orbit-depth-ring'),
              painter: _RingPainter(
                Offset.lerp(origin, center, e)!,
                lerpDouble(flatRadius, orbitCenterRadius * k, e)!,
                orbitCenterTilt * e,
                back: colors.onSurface.withValues(alpha: .25 * e),
                front: orbitDepthRingFront(
                  Theme.of(context).brightness,
                ).withValues(alpha: .45 * e),
              ),
            ),
            for (final face in faces)
              if (!(_reduceMotion && face.lift > .5))
                _seat(queue[face.index], face, center, queue.length, k),
            if (_reduceMotion && lifted != null && lifted.lift > .5)
              Positioned(
                key: const ValueKey('orbit-depth-center-slot'),
                left: center.dx - lifted.diameter / 2,
                top: center.dy - lifted.diameter / 2,
                width: lifted.diameter,
                height: lifted.diameter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(shown!.friend.peerId),
                    child: _face(shown, lifted, queue.length, k),
                  ),
                ),
              ),
            if (shown != null)
              Positioned(
                key: const ValueKey('orbit-depth-name-slot'),
                left: 0,
                right: 0,
                top: cy + (orbitCenterDiameter / 2 + 12) * k,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: presence * named,
                    child: fade(
                      'orbit-depth-name',
                      Text(
                        shown.friend.username,
                        key: const ValueKey('orbit-depth-name'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17 * k,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Faces come and go and re-sort every frame; without a key the
            // card's subtree is rebuilt and its media reloads and flickers.
            Positioned(
              key: const ValueKey('orbit-depth-card-slot'),
              left: 14 * k,
              right: 14 * k,
              top: slotTop,
              bottom: slotBottom,
              child: Transform.translate(
                // The thought slides up into place as the orbit tilts.
                offset: Offset(0, (1 - reveal) * 40 * k),
                child: Opacity(
                  opacity: (presence * reveal).clamp(0.0, 1.0).toDouble(),
                  child: fade(
                    'orbit-depth-content',
                    shown != null
                        ? _card(shown, k)
                        : _layer == OrbitDepthLayer.flat ||
                              _gesture == OrbitDepthGesture.vertical
                        ? null
                        : IgnorePointer(
                            key: const ValueKey('orbit-depth-empty-ring'),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Text(
                                AppLocalizations.of(
                                  context,
                                )!.orbit_depth_empty_ring,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15 * k,
                                  color: colors.onSurface.withValues(alpha: .7),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seat(
    OrbitDepthSeat seat,
    OrbitCenterFace face,
    Offset center,
    int count,
    double k,
  ) {
    final position = center + face.offset;
    return Positioned(
      key: ValueKey('orbit-depth-seat-inner-${seat.friend.peerId}'),
      left: position.dx - face.diameter / 2,
      top: position.dy - face.diameter / 2,
      width: face.diameter,
      height: face.diameter,
      child: Opacity(opacity: face.opacity, child: _face(seat, face, count, k)),
    );
  }

  Widget _face(OrbitDepthSeat seat, OrbitCenterFace face, int count, double k) {
    final full = orbitCenterDiameter * k;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      key: ValueKey('orbit-depth-face-${seat.friend.peerId}'),
      onTap: () => _tapFace(seat, face.index, count, face.lift),
      child: Semantics(
        identifier: 'orbit.depth.face.${seat.friend.peerId}',
        button: true,
        selected: face.lift > .5,
        label: seat.friend.username,
        // Every face is drawn at the center size and scaled down: the avatar
        // decodes its photo at its own size, so a size that changed every
        // frame of a turn reloaded the photo every frame and it flickered.
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox.square(
            dimension: full,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: face.darken),
                border: face.lift > 0
                    ? Border.all(
                        color: Colors.white,
                        width: 2.5 * face.lift * k * full / face.diameter,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      )
                    : null,
              ),
              child: UserAvatar(
                peerId: seat.friend.peerId,
                size: full,
                showGlow: false,
                showPhotoFrame: false,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(OrbitDepthSeat seat, double k) {
    final post = seat.thought;
    final l10n = AppLocalizations.of(context)!;
    final created = DateTime.tryParse(post.createdAt)?.toUtc();
    final age = created == null ? Duration.zero : _now.difference(created);
    final ageText = age.inMinutes < 1
        ? l10n.time_just_now
        : age.inMinutes < 60
        ? l10n.time_min_ago(age.inMinutes)
        : l10n.time_hour_ago(age.inHours);
    void open() {
      if (_enabled &&
          !_suppressTap &&
          liveOrbitDepthThought(post, _now) != null) {
        widget.onThoughtTap?.call(post.id);
      }
    }

    // A drag on the card tilts or turns the orbit, so the card cannot scroll.
    // It clips to its slot; the tap opens the whole thought.
    return UnconstrainedBox(
      key: ValueKey('orbit-depth-card-${post.id}'),
      constrainedAxis: Axis.horizontal,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: open,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8 * k),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ageText,
                    style: TextStyle(
                      fontSize: 13 * k,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (post.text.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 12 * k),
                      // Full width, so the text sits on its own side: an Arabic
                      // thought on the right even in an English app.
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          post.text,
                          key: ValueKey('orbit-depth-text-${post.id}'),
                          textDirection: detectTextDirection(post.text),
                          style: TextStyle(fontSize: 22 * k, height: 1.3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (post.mediaKind != 'none' &&
              widget.loadMedia != null &&
              widget.downloadMedia != null)
            OrbitDepthMedia(
              key: ValueKey('orbit-depth-media-${post.id}'),
              postId: post.id,
              load: widget.loadMedia!,
              download: widget.downloadMedia!,
              onOpen: open,
              lastLoaded: _lastLoadedMedia,
            ),
        ],
      ),
    );
  }
}

/// The near half of the ring is tinted light blue, as in the agreed mock; on
/// a light background the same tint would vanish, so it deepens there.
Color orbitDepthRingFront(Brightness brightness) =>
    (brightness == Brightness.dark
            ? const Color(0xFFCFE0FF)
            : const Color(0xFF2F5FB8))
        .withValues(alpha: .45);

class _RingPainter extends CustomPainter {
  const _RingPainter(
    this.center,
    this.radius,
    this.tilt, {
    required this.back,
    required this.front,
  });
  final Offset center;
  final double radius, tilt;
  final Color back, front;

  Path _half(bool front) {
    final path = Path();
    var drawing = false;
    for (var i = 0; i <= 160; i++) {
      final angle = i / 160 * 2 * math.pi;
      final sin = math.sin(angle);
      if (front ? sin < -.02 : sin > .02) {
        drawing = false;
        continue;
      }
      final (offset, _) = projectOrbitCenter(angle, radius, tilt);
      final point = center + offset;
      if (drawing) {
        path.lineTo(point.dx, point.dy);
      } else {
        path.moveTo(point.dx, point.dy);
        drawing = true;
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _half(false),
      Paint()
        ..color = back
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawPath(
      _half(true),
      Paint()
        ..color = front
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.center != center ||
      old.radius != radius ||
      old.tilt != tilt ||
      old.back != back ||
      old.front != front;
}
