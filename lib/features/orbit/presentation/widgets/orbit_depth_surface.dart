import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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
    required this.onOpenFriends,
    this.selfPeerId,
    this.selfAvatarBytes,
    this.active = true,
    this.gesturesEnabled = true,
    this.resetSignal,
    this.nowProvider,
    this.onOwnsHostGestureChanged,
    this.onBackActionChanged,
    this.onThoughtDeparted,
    this.onThoughtsExpired,
    this.loadMedia,
    this.downloadMedia,
  });
  final Widget child;
  final List<OrbitItem> items;
  final Map<String, PostModel> thoughts;
  final String? selfPeerId;
  final Uint8List? selfAvatarBytes;
  final bool active;
  final bool gesturesEnabled;
  final Listenable? resetSignal;
  final DateTime Function()? nowProvider;
  final ValueChanged<bool>? onOwnsHostGestureChanged;
  final ValueChanged<VoidCallback?>? onBackActionChanged;
  final ValueChanged<String>? onThoughtDeparted;
  final VoidCallback? onThoughtsExpired;
  final ValueChanged<OrbitFriend> onFriendTap;
  final ValueChanged<String>? onThoughtTap;
  final VoidCallback? onOpenFriends;
  final Future<List<PostMediaAttachmentModel>> Function(String)? loadMedia;
  final Future<PostMediaAttachmentModel> Function(PostMediaAttachmentModel)?
  downloadMedia;
  @override
  State<OrbitDepthSurface> createState() => _OrbitDepthSurfaceState();
}

typedef _DepthLanding = ({
  int generation,
  String? departedPostId,
  bool markDeparture,
});

class _OrbitDepthSurfaceState extends State<OrbitDepthSurface>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _vertical = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _rotation = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _fold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 260),
  );
  OrbitDepthLayer _layer = OrbitDepthLayer.flat;
  OrbitDepthAnchor _anchor = OrbitDepthAnchor.top;
  OrbitDepthGesture _gesture = OrbitDepthGesture.idle;
  String? _frontPeer;
  String? _landedPostId;
  late final AnimationController _overviewProgress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  bool _owned = false;
  bool _routeActive = true;
  bool _foreground = true;
  bool _sequenceCancelled = false;
  // Retained through recognizer callbacks after raw pointer-up clears the map.
  bool _suppressTap = false;
  bool _pinchDecided = false;
  final _pointers = <int, Offset>{};
  Offset? _start;
  double _startVertical = 0;
  double _startRotation = 0;
  double? _pinchDistance;
  VelocityTracker? _velocity;
  int _settleGeneration = 0;
  _DepthLanding? _pendingLanding;
  bool _overviewRequested = false;
  Timer? _expiry;
  final _lastLoadedMedia = <String, List<PostMediaAttachmentModel>>{};
  Timer? _age;
  double _scale = 1;
  bool get _active => widget.active && _routeActive && _foreground;
  bool get _enabled => _active && widget.gesturesEnabled;
  bool get _depth => _layer != OrbitDepthLayer.flat || _vertical.value > 0.01;
  bool get _reduceMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  bool get _rtl => Directionality.of(context) == TextDirection.rtl;
  DateTime get _now => (widget.nowProvider ?? DateTime.now)().toUtc();
  OrbitDepthLayout get _layout => OrbitDepthLayout.fromItems(
    widget.items,
    widget.thoughts,
    _now,
    mirrored: _rtl,
  );
  List<OrbitDepthSeat> get _seats => _layout.inLayer(_layer);
  OrbitDepthSeat? get _front => _seats
      .where((seat) => seat.friend.peerId == _frontPeer && seat.thought != null)
      .firstOrNull;
  double _stop(OrbitDepthLayer layer) => switch (layer) {
    OrbitDepthLayer.flat => 0,
    OrbitDepthLayer.inner => 320,
    OrbitDepthLayer.outer => 580,
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
    _routeActive = ModalRoute.isCurrentOf(context) ?? true;
    if (!_active) _reset(notifyBuild: false);
    if (_reduceMotion) {
      final pending = _pendingLanding;
      _vertical.stop();
      _rotation.stop();
      _fold.stop();
      _vertical.value = _stop(_layer);
      final front = _front;
      if (front != null) {
        _rotation.value = orbitDepthRotationFor(front, _rotation.value);
      }
      _fold.value = _gesture == OrbitDepthGesture.turn ? 1 : 0;
      _overviewProgress.stop();
      _overviewProgress.value = _overviewRequested ? 1 : 0;
      if (pending != null) _completeLanding(pending);
    }
  }

  @override
  void didUpdateWidget(covariant OrbitDepthSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetSignal != widget.resetSignal) {
      oldWidget.resetSignal?.removeListener(_reset);
      widget.resetSignal?.addListener(_reset);
    }
    if (!_enabled) _reset(notifyBuild: false);
    if (_depth && _front == null) {
      final next = orbitDepthNearest(_seats, _rotation.value);
      _frontPeer = next?.friend.peerId;
      _landedPostId = _gesture == OrbitDepthGesture.idle && !_overviewRequested
          ? next?.thought?.id
          : null;
      if (next != null) {
        _rotation.value = orbitDepthRotationFor(next, _rotation.value);
      }
    } else if (_depth &&
        _gesture == OrbitDepthGesture.idle &&
        !_overviewRequested &&
        _fold.value == 0 &&
        _pendingLanding == null &&
        _landedPostId != null &&
        _front?.thought?.id != _landedPostId) {
      // Same author, new post: arrival is not a read of either version.
      _landedPostId = _front?.thought?.id;
    }
    if (_depth &&
        _gesture == OrbitDepthGesture.idle &&
        !_rotation.isAnimating) {
      final front = _front;
      if (front != null) {
        _rotation.value = orbitDepthRotationFor(front, _rotation.value);
      }
    }
    _armTimers();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
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
    ++_settleGeneration;
    _pendingLanding = null;
    _vertical.stop();
    _rotation.stop();
    _fold.stop();
    _overviewProgress.stop();
    _vertical.value = 0;
    _rotation.value = 0;
    _fold.value = 0;
    _layer = OrbitDepthLayer.flat;
    _gesture = OrbitDepthGesture.idle;
    _frontPeer = null;
    _landedPostId = null;
    _overviewProgress.value = 0;
    _overviewRequested = false;
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
        setState(() {
          if (_front == null) {
            final next = orbitDepthNearest(_seats, _rotation.value);
            _frontPeer = next?.friend.peerId;
            _landedPostId =
                _gesture == OrbitDepthGesture.idle && !_overviewRequested
                ? next?.thought?.id
                : null;
            if (next != null) {
              _rotation.value = orbitDepthRotationFor(next, _rotation.value);
            }
          }
        });
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

  Future<void> _spring(
    AnimationController controller,
    double target,
    SpringDescription spring,
  ) async {
    if (_reduceMotion || (controller.value - target).abs() < .001) {
      controller.value = target;
      return;
    }
    await controller
        .animateWith(SpringSimulation(spring, controller.value, target, 0))
        .orCancel;
    controller.value = target;
  }

  Future<void> _settle(
    OrbitDepthLayer target, {
    OrbitDepthSeat? selected,
    bool markDeparture = true,
  }) async {
    final generation = ++_settleGeneration;
    final landing = (
      generation: generation,
      departedPostId: _landedPostId,
      markDeparture: markDeparture,
    );
    _pendingLanding = landing;
    final enteringRing = target != _layer;
    final candidates = _layout.inLayer(target);
    final front =
        selected ??
        (enteringRing
            ? orbitDepthArrival(candidates, _rotation.value)
            : _front);
    _layer = target;
    _frontPeer = front?.friend.peerId;
    _gesture = OrbitDepthGesture.idle;
    if (target != OrbitDepthLayer.flat) _publish(true);
    setState(() {});
    try {
      await Future.wait([
        _spring(
          _vertical,
          _stop(target),
          const SpringDescription(mass: 1, stiffness: 170, damping: 19),
        ),
        _spring(
          _rotation,
          front == null
              ? _rotation.value
              : orbitDepthRotationFor(front, _rotation.value),
          const SpringDescription(mass: 1, stiffness: 90, damping: 15),
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
    final next = _layer == OrbitDepthLayer.flat ? null : _front?.thought?.id;
    // Overview bubbles do not land a new expanded thought. A thought that
    // was already read at the front remains owned until its actual departure.
    _landedPostId = _overviewRequested
        ? (landing.departedPostId == next ? next : null)
        : next;
    if (landing.markDeparture &&
        landing.departedPostId != null &&
        landing.departedPostId != next) {
      widget.onThoughtDeparted?.call(landing.departedPostId!);
    }
    if (_reduceMotion) {
      _fold.value = 0;
    } else {
      unawaited(
        _fold.reverse().then((_) {
          if (mounted &&
              _active &&
              _gesture == OrbitDepthGesture.idle &&
              !_overviewRequested &&
              _pendingLanding == null &&
              _layer != OrbitDepthLayer.flat) {
            _landedPostId = _front?.thought?.id;
          }
        }),
      );
    }
    if (_layer == OrbitDepthLayer.flat) {
      _overviewProgress.value = 0;
      _overviewRequested = false;
      _publish(false);
    }
    _armTimers();
    setState(() {});
  }

  void _stepBack() {
    if (!_active || !_depth) return;
    unawaited(
      _settle(
        _layer == OrbitDepthLayer.outer
            ? OrbitDepthLayer.inner
            : OrbitDepthLayer.flat,
      ),
    );
  }

  void _down(PointerDownEvent event) {
    if (!_enabled) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length > 1) {
      _suppressTap = true;
      _sequenceCancelled = true;
      ++_settleGeneration;
      _pendingLanding = null;
      _gesture = OrbitDepthGesture.pinch;
      _pinchDistance =
          (_pointers.values.first - _pointers.values.last).distance;
      _pinchDecided = false;
      if (_depth) {
        _publish(true);
        _vertical.stop();
        _rotation.stop();
        _vertical.value = _stop(_layer);
        final front = _front;
        if (front != null) {
          _rotation.value = orbitDepthRotationFor(front, _rotation.value);
        }
        _fold.value = 0;
        setState(() {});
      }
      return;
    }
    _sequenceCancelled = false;
    _suppressTap = false;
    _start = event.localPosition;
    _startVertical = _vertical.value;
    _startRotation = _rotation.value;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
  }

  void _move(PointerMoveEvent event) {
    if (!_enabled || !_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length > 1) {
      if (_depth && !_pinchDecided && (_pinchDistance ?? 0) >= 24) {
        final ratio =
            (_pointers.values.first - _pointers.values.last).distance /
            _pinchDistance!;
        if (ratio < .88 || ratio > 1.12) {
          _overviewRequested = ratio < .88;
          if (_reduceMotion) {
            _overviewProgress.value = _overviewRequested ? 1 : 0;
          } else {
            unawaited(
              _overviewProgress.animateTo(
                ratio < .88 ? 1 : 0,
                curve: Curves.easeInOut,
              ),
            );
          }
          _pinchDecided = true;
        }
      }
      return;
    }
    if (_sequenceCancelled || _start == null) return;
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
        }
      } else if (_depth) {
        _gesture = OrbitDepthGesture.turn;
        if (_reduceMotion) {
          _fold.value = 1;
        } else {
          unawaited(_fold.forward());
        }
      } else {
        _sequenceCancelled = true;
        return;
      }
      ++_settleGeneration;
      _pendingLanding = null;
      _vertical.stop();
      _rotation.stop();
      _publish(true);
    }
    if (_gesture == OrbitDepthGesture.vertical) {
      final direction = _anchor == OrbitDepthAnchor.top ? -1 : 1;
      _vertical.value = (_startVertical + direction * delta.dy / _scale).clamp(
        0,
        580,
      );
    } else if (_gesture == OrbitDepthGesture.turn) {
      _rotation.value =
          _startRotation + (_rtl ? 1 : -1) * delta.dx / (128 * _scale);
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
      final target = value < 160
          ? OrbitDepthLayer.flat
          : value < 450
          ? OrbitDepthLayer.inner
          : OrbitDepthLayer.outer;
      unawaited(_settle(target));
    } else if (gesture == OrbitDepthGesture.turn) {
      final dx = _velocity?.getVelocity().pixelsPerSecond.dx ?? 0;
      final coast = ((_rtl ? 1 : -1) * dx * .25 / (128 * _scale)).clamp(
        -math.pi,
        math.pi,
      );
      var next = orbitDepthNearest(_seats, _rotation.value + coast);
      final turned = _rotation.value - _startRotation;
      final candidates = _seats.where((seat) => seat.thought != null).toList();
      if (next?.friend.peerId == _frontPeer && candidates.length > 1) {
        candidates.removeWhere((seat) => seat.friend.peerId == _frontPeer);
        double distance(OrbitDepthSeat seat) =>
            (turned.sign *
                (math.pi / 2 - seat.placement.angle - _startRotation)) %
            (2 * math.pi);
        candidates.sort((a, b) => distance(a).compareTo(distance(b)));
        if (turned.abs() > .2 * distance(candidates.first))
          next = candidates.first;
      }
      unawaited(_settle(_layer, selected: next));
    }
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
    _rotation.dispose();
    _fold.dispose();
    _overviewProgress.dispose();
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
            animation: Listenable.merge([
              _vertical,
              _rotation,
              _fold,
              _overviewProgress,
            ]),
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                _scale = math.min(
                  constraints.maxWidth / 390,
                  constraints.maxHeight / 640,
                );
                final depth = _depth;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      ignoring: depth,
                      child: Opacity(
                        opacity: 1 - (_vertical.value / 320).clamp(0.0, 1.0),
                        child: ScrollConfiguration(
                          behavior: _enabled
                              ? ScrollConfiguration.of(context).copyWith(
                                  physics: const NeverScrollableScrollPhysics(),
                                )
                              : ScrollConfiguration.of(context),
                          child: widget.child,
                        ),
                      ),
                    ),
                    if (depth && _active)
                      _dial(Size(constraints.maxWidth, constraints.maxHeight)),
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
    final tilt = 67 * math.pi / 180 * tiltProgress;
    final camera = ((_vertical.value - 320) / 260).clamp(0.0, 1.0);
    final cy =
        size.height *
        (.5 +
            ((_anchor == OrbitDepthAnchor.top ? .084 : .8) - .5) *
                tiltProgress);
    final center = Offset(size.width / 2, cy);
    final layout = _layout;
    final colors = Theme.of(context).colorScheme;
    final children = <Widget>[];
    final rings = <_DepthRingPaint>[];
    final faces = <({double depth, Widget widget})>[];
    for (final layer in [OrbitDepthLayer.inner, OrbitDepthLayer.outer]) {
      final rel = (layer == OrbitDepthLayer.inner ? 0 : 1) - camera;
      final away = Curves.easeInOut.transform(rel.abs().clamp(0.0, 1.0));
      final scale =
          (layer == OrbitDepthLayer.outer ? 1.12 : 1) *
          (rel >= 0 ? 1 + .45 * away : 1 - .65 * away);
      final opacity = rel >= 0 ? 1 - .6 * away : 1 - rel.abs().clamp(0.0, 1.0);
      final radius = (140 + 6 * tiltProgress) * k * scale;
      rings.add(_DepthRingPaint(center, radius, tilt, opacity, rel > 0));
      for (final seat in layout.inLayer(layer)) {
        final angle = seat.placement.angle + _rotation.value;
        final (offset, near) = projectOrbitDepth(angle, radius, tilt);
        final front = seat.friend.peerId == _frontPeer && layer == _layer;
        final diameter =
            40 *
            k *
            scale *
            near *
            (layer == OrbitDepthLayer.outer ? .68 : 1) *
            (front ? 1.15 : 1) *
            (seat.thought?.isRead == true ? .84 : 1);
        final position = center + offset;
        final waiting = rel > 0
            ? (1 - ((math.sin(angle) + .35) / .5).clamp(0, 1)) *
                      rel.clamp(0, 1) +
                  (1 - rel.clamp(0, 1))
            : 1.0;
        final alpha =
            (opacity *
                    waiting *
                    (1 - .6 * (1 - math.sin(angle)) / 2 * math.sin(tilt)))
                .clamp(0.0, 1.0);
        if (alpha <= .01) continue;
        final thought = seat.thought;
        final face = thought == null
            ? CustomPaint(
                key: ValueKey('orbit-depth-empty-${seat.friend.peerId}'),
                painter: _EmptySeatPainter(
                  colors.onSurface.withValues(alpha: .35),
                ),
              )
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                key: ValueKey('orbit-depth-face-${seat.friend.peerId}'),
                onTap: () {
                  if (!_enabled || _suppressTap || _pointers.length > 1) return;
                  if (front) {
                    widget.onFriendTap(seat.friend);
                  } else {
                    unawaited(_settle(layer, selected: seat));
                  }
                },
                child: Semantics(
                  identifier: 'orbit.depth.face.${seat.friend.peerId}',
                  button: true,
                  label: seat.friend.username,
                  child: UserAvatar(peerId: seat.friend.peerId, size: diameter),
                ),
              );
        faces.add((
          depth: position.dy,
          widget: Positioned(
            key: ValueKey(
              'orbit-depth-seat-${layer.name}-${seat.friend.peerId}',
            ),
            left: position.dx - diameter / 2,
            top: position.dy - diameter / 2,
            width: diameter,
            height: diameter,
            child: Opacity(opacity: alpha, child: face),
          ),
        ));
        if (thought != null &&
            (_overviewProgress.value > .01 || (front && _fold.value > .5))) {
          faces.add((
            depth: position.dy + 1,
            widget: Positioned(
              key: ValueKey('orbit-depth-note-slot-${thought.id}'),
              left: (position.dx - 52 * k).clamp(
                0,
                math.max(0, size.width - 104 * k),
              ),
              top: math.max(0, position.dy - diameter / 2 - 46 * k),
              width: 104 * k,
              child: IgnorePointer(
                child: Container(
                  key: ValueKey('orbit-depth-note-${thought.id}'),
                  padding: EdgeInsets.all(6 * k),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    thought.text.isEmpty ? seat.friend.username : thought.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11 * k,
                      fontWeight: thought.isRead
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ));
        }
      }
      if (layer == OrbitDepthLayer.outer && rel > .01) {
        final (back, _) = projectOrbitDepth(-math.pi / 2, radius, tilt);
        children.add(
          Positioned(
            top: math.max(0, cy + back.dy - 35 * k),
            left: 0,
            right: 0,
            child: Center(
              child: TextButton(
                key: const ValueKey('orbit-depth-outer-peek'),
                onPressed: () {
                  if (_enabled && !_suppressTap) {
                    unawaited(_settle(OrbitDepthLayer.outer));
                  }
                },
                child: Text(
                  '${AppLocalizations.of(context)!.orbit_depth_outer_ring} · ${layout.inLayer(layer).length}',
                ),
              ),
            ),
          ),
        );
      }
      if (layer == OrbitDepthLayer.outer && layout.overflow != null) {
        final (badge, near) = projectOrbitDepth(
          layout.overflow!.angle + _rotation.value,
          radius,
          tilt,
        );
        final point = center + badge;
        final diameter = 32 * k * near;
        faces.add((
          depth: point.dy,
          widget: Positioned(
            left: point.dx - diameter / 2,
            top: point.dy - diameter / 2,
            width: diameter,
            height: diameter,
            child: GestureDetector(
              key: const ValueKey('orbit-depth-overflow'),
              onTap: () {
                if (_enabled && !_suppressTap) widget.onOpenFriends?.call();
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfaceContainerHighest,
                ),
                child: Center(
                  child: Text(
                    '+${layout.overflow!.overflowCount}',
                    style: TextStyle(fontSize: 10 * k),
                  ),
                ),
              ),
            ),
          ),
        ));
      }
    }
    faces.sort((a, b) => a.depth.compareTo(b.depth));
    final front = _front;
    final cardVisible =
        front != null &&
        _overviewProgress.value < .99 &&
        _fold.value < .99 &&
        _gesture != OrbitDepthGesture.vertical;
    return Opacity(
      key: const ValueKey('orbit-depth-stage'),
      opacity: tiltProgress,
      child: Semantics(
        identifier: 'orbit.depth.${_layer.name}.${_anchor.name}',
        child: Stack(
          key: ValueKey('orbit-depth-${_layer.name}-${_anchor.name}'),
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _DialPainter(
                rings,
                colors.onSurface.withValues(alpha: .25),
              ),
            ),
            ...children,
            Positioned(
              left: center.dx - 26 * k,
              top: center.dy - 26 * k,
              width: 52 * k,
              height: 52 * k,
              child: UserAvatar(
                peerId: widget.selfPeerId ?? '',
                size: 52 * k,
                avatarBytes: widget.selfAvatarBytes,
              ),
            ),
            ...faces.map((face) => face.widget),
            if (cardVisible)
              // Faces come and go and re-sort every frame; without a key the
              // card's subtree is rebuilt and its media reloads and flickers.
              Positioned(
                key: const ValueKey('orbit-depth-card-slot'),
                left: 14 * k,
                right: 14 * k,
                top: _anchor == OrbitDepthAnchor.top
                    ? math.max(
                        cy + 146 * k * math.cos(tilt) * 1.45 + 38 * k,
                        140 * k,
                      )
                    : 60 * k,
                bottom: _anchor == OrbitDepthAnchor.bottom
                    ? math.max(
                        0,
                        size.height - cy + 146 * k * math.cos(tilt) + 30 * k,
                      )
                    : 20 * k,
                child: Opacity(
                  opacity: ((1 - _fold.value) * (1 - _overviewProgress.value))
                      .clamp(0, 1),
                  child: _card(front, k),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card(OrbitDepthSeat front, double k) {
    final post = front.thought!;
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

    return SingleChildScrollView(
      key: ValueKey('orbit-depth-card-${post.id}'),
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
                    '${front.friend.username} · $ageText',
                    style: TextStyle(
                      fontSize: 13 * k,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (post.text.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 12 * k),
                      child: Text(
                        post.text,
                        style: TextStyle(fontSize: 22 * k, height: 1.3),
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

class _DepthRingPaint {
  const _DepthRingPaint(
    this.center,
    this.radius,
    this.tilt,
    this.opacity,
    this.waiting,
  );
  final Offset center;
  final double radius, tilt, opacity;
  final bool waiting;
}

class _DialPainter extends CustomPainter {
  const _DialPainter(this.rings, this.color);
  final List<_DepthRingPaint> rings;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    for (final ring in rings) {
      final paint = Paint()
        ..color = color.withValues(alpha: color.a * ring.opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      final path = Path();
      var drawing = false;
      for (var i = 0; i <= 160; i++) {
        final angle = i / 160 * 2 * math.pi;
        if (ring.waiting && math.sin(angle) > .15) {
          drawing = false;
          continue;
        }
        final (offset, _) = projectOrbitDepth(angle, ring.radius, ring.tilt);
        final point = ring.center + offset;
        if (!drawing) {
          path.moveTo(point.dx, point.dy);
          drawing = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) => true;
}

class _EmptySeatPainter extends CustomPainter {
  const _EmptySeatPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Offset.zero & size;
    for (var i = 0; i < 12; i++) {
      canvas.drawArc(
        rect.deflate(2),
        i * math.pi / 6,
        math.pi / 12,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EmptySeatPainter oldDelegate) =>
      color != oldDelegate.color;
}
