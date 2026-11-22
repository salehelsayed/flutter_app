import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/orbit_depth_geometry.dart';
import 'package:flutter_app/features/orbit/domain/orbit_depth_visit.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_draft.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:flutter_app/features/posts/presentation/widgets/thought_reaction_circle.dart'
    show thoughtReactionGreen;
import 'package:flutter_app/features/posts/presentation/widgets/thought_reply_dock.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/features/translate_preview/translate_preview_widgets.dart';
import 'package:flutter_app/features/translate_preview/translate_preview_persistence.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:uuid/uuid.dart';
import 'orbit_depth_media.dart';

/// The production flat surface remains mounted below this local dial. Data,
/// downloads, seen writes and destinations remain the wired host's authority.
/// What friends did with the author's own live thought, shown in place of
/// the reply bar on the author's own card.
typedef OrbitDepthOwnActivity = ({int reacted, int wroteBack, int fresh});

class OrbitDepthSurface extends StatefulWidget {
  const OrbitDepthSurface({
    super.key,
    required this.child,
    required this.items,
    required this.thoughts,
    required this.onFriendTap,
    required this.onThoughtTap,
    this.onThoughtVideoPlay,
    this.ownSeat,
    this.ownActivity,
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
    this.postChanges,
    this.hostChrome,
    this.onReply,
    this.onTextReply,
    this.onStickerReply,
    this.onTypedReplySent,
    this.validateGrace,
    this.replyStatusChanges,
    this.answers,
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

  /// Written with how much of the host's controls should show: 1 flat, 0 in
  /// depth. The dial keeps its place; only the controls leave.
  final ValueNotifier<double>? hostChrome;
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

  /// A lone downloaded video played full screen from the front card.
  final ValueChanged<String>? onThoughtVideoPlay;

  /// The author's own live thought, seated first on the ring.
  final OrbitDepthSeat? ownSeat;

  /// Shown on the author's own card instead of the reply bar.
  final OrbitDepthOwnActivity? ownActivity;
  final Future<List<PostMediaAttachmentModel>> Function(String)? loadMedia;
  final Future<PostMediaAttachmentModel> Function(
    PostMediaAttachmentModel,
    int,
  )?
  downloadMedia;
  final Stream<String>? postChanges;

  /// Sends a reaction as an ordinary quoted chat reply. Null hides the dock.
  final ThoughtReplySender? onReply;
  final ThoughtTextReplySender? onTextReply;
  final ThoughtStickerReplySender? onStickerReply;
  final ValueChanged<String>? onTypedReplySent;
  final Future<bool> Function(ThoughtReplyDraft)? validateGrace;

  /// Shared with the host's full-screen cards; it owns later status updates.
  final OrbitDepthAnswers? answers;

  /// Later delivery updates for those replies, by message id.
  final Stream<({String messageId, ThoughtReplyStatus status})>?
  replyStatusChanges;
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
  OrbitDepthVisit _visit = OrbitDepthVisit.empty;
  _DepthReplyInputState? _replyInput;
  OrbitDepthSeat? _replySeat;
  ThoughtReplyDraft? _replyDraft;
  String? _graceSendId;
  Timer? _graceClock;
  bool _graceValidated = false;
  int _graceValidation = 0;
  int _replyNavigation = 0;
  ({OrbitDepthSeat seat, int epoch, int landing, String id, bool grace})?
  _pendingReplyNavigation;
  StreamSubscription<({String messageId, ThoughtReplyStatus status})>?
  _replyStatuses;
  double _keyboard = 0;
  bool get _composing => _visit.composingPostId != null;
  bool get _active => widget.active && _foreground;
  bool get _enabled => _active && _routeActive && widget.gesturesEnabled;
  bool get _depth => _layer != OrbitDepthLayer.flat || _vertical.value > 0.01;
  bool get _reduceMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  bool get _rtl => Directionality.of(context) == TextDirection.rtl;
  DateTime get _now => (widget.nowProvider ?? DateTime.now)().toUtc();

  List<OrbitDepthSeat> get _queue {
    final own = widget.ownSeat;
    final live = [
      // Your own live thought comes first, the way friends see theirs.
      if (own != null && liveOrbitDepthThought(own.thought, _now) != null) own,
      ...orbitDepthQueue(widget.items, widget.thoughts, _now),
    ];
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
    _vertical.addListener(_publishChrome);
    _listenAnswers();
    _listenReplyStatuses();
  }

  void _listenAnswers([OrbitDepthAnswers? previous]) {
    previous?.removeListener(_onAnswersChanged);
    final answers = widget.answers;
    if (answers == null) return;
    _visit = _visit.withAnswersFrom(answers.value);
    answers.addListener(_onAnswersChanged);
  }

  void _onAnswersChanged() {
    final answers = widget.answers;
    if (mounted && answers != null) {
      setState(() => _visit = _visit.withAnswersFrom(answers.value));
      _maybeOpenPendingReply();
    }
  }

  void _listenReplyStatuses() {
    _replyStatuses?.cancel();
    _replyStatuses = null;
    if (widget.answers != null) return;
    _replyStatuses = widget.replyStatusChanges?.listen((update) {
      if (!mounted || !_visit.sends.containsKey(update.messageId)) return;
      setState(
        () => _visit = _visit.settle(
          update.messageId,
          update.status,
          finished: false,
        ),
      );
      _maybeOpenPendingReply();
    });
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
    _replyNavigation++;
    if (_composing) _closeComposer();
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
    if (oldWidget.answers != widget.answers) {
      _listenAnswers(oldWidget.answers);
    }
    if (oldWidget.answers != widget.answers ||
        oldWidget.replyStatusChanges != widget.replyStatusChanges) {
      _listenReplyStatuses();
    }
    if (!_active || !widget.gesturesEnabled) _reset(notifyBuild: false);
    if (!identical(oldWidget.thoughts, widget.thoughts)) {
      _checkReplySeat();
    }
    if (_composing && widget.onReply == null) _closeComposerAfterFrame();
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
    _endVisit();
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
        [...widget.thoughts.values, ?widget.ownSeat?.thought]
            .map((post) => DateTime.tryParse(post.expiresAt)?.toUtc())
            .whereType<DateTime>()
            .where((expiry) => expiry.isAfter(_now))
            .toList()
          ..sort();
    if (expiries.isNotEmpty) {
      _expiry = Timer(expiries.first.difference(_now), () {
        if (!mounted || !_active) return;
        _checkReplySeat();
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

  /// The host's controls leave with the flat orbit, on the same curve.
  void _publishChrome() {
    final chrome = widget.hostChrome;
    if (chrome == null) return;
    void write() {
      if (mounted) chrome.value = 1 - _smooth(_vertical.value / 320 / .45);
    }

    // Resets move the tilt during build, when the host cannot rebuild yet.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => write());
    } else {
      write();
    }
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
        landing.departedPostId != next &&
        landing.departedPostId != widget.ownSeat?.thought.id) {
      widget.onThoughtDeparted?.call(landing.departedPostId!);
    }
    if (_layer == OrbitDepthLayer.flat) {
      _order = null;
      _flat = null;
      _endVisit();
      _publish(false);
    }
    _armTimers();
    setState(() {});
  }

  void _stepBack() {
    if (_composing) {
      _closeComposer();
      return;
    }
    _replyNavigation++;
    if (!_active || !_depth) return;
    unawaited(_settle(OrbitDepthLayer.flat));
  }

  /// One seat of horizontal finger travel.
  double get _seatTravel => orbitCenterRadius * _scale;

  /// The next friend waits on the right in a left-to-right app and on the
  /// left in a right-to-left one, so pulling it in follows the finger.
  double get _turnSign => _rtl ? 1 : -1;

  void _down(PointerDownEvent event) {
    if (!_enabled || _composing) return;
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
      if (_isOwn(seat)) {
        widget.onThoughtTap?.call(seat.thought.id);
      } else {
        widget.onFriendTap(seat.friend);
      }
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
  void didChangeMetrics() {
    // Android's back key hides the keyboard but leaves the field focused.
    final keyboard = View.of(context).viewInsets.bottom;
    final hidden = _keyboard > 0 && keyboard == 0;
    _keyboard = keyboard;
    if (hidden && _composing) _closeComposerAfterFrame();
  }

  bool get _answerable => _enabled && !_suppressTap && !_composing;

  /// A screen-reader activation comes with no pointer, so the drag that last
  /// set [_suppressTap] cannot be what it means; it starts fresh, as [_down]
  /// does.
  VoidCallback _bySemantics(VoidCallback action) => () {
    if (_pointers.isEmpty) _suppressTap = false;
    action();
  };

  void _endVisit() {
    _discardComposer();
    final answers = widget.answers;
    _visit = answers == null
        ? OrbitDepthVisit.empty
        : OrbitDepthVisit.empty.withAnswersFrom(answers.value);
  }

  void _onReplyInputChanged(OrbitDepthSeat seat, _DepthReplyInputState input) {
    if (!input.focusNode.hasFocus) {
      if (identical(input, _replyInput)) _closeComposerAfterFrame();
      return;
    }
    if (!_composing) {
      if (!_canAnswer(seat.thought.id)) {
        input.focusNode.unfocus();
        return;
      }
      setState(() {
        _replySeat = seat;
        _replyInput = input;
        _replyNavigation++;
        _visit = _visit.openComposer(seat.thought.id);
      });
    }
    if (!identical(input, _replyInput)) return;
    final now = _now;
    if (input.controller.text.trim().isEmpty) {
      if (!_hasExpiredReply) _replyDraft = null;
    } else {
      _replyDraft ??= ThoughtReplyDraft.start(seat.thought, now);
    }
  }

  bool get _hasExpiredReply {
    final expiry = DateTime.tryParse(_replySeat?.thought.expiresAt ?? '');
    return expiry != null && !expiry.isAfter(_now);
  }

  void _checkReplySeat() {
    final seat = _replySeat;
    if (seat == null) return;
    final live = widget.thoughts[seat.friend.peerId];
    final draft = _replyDraft;
    final expired = _hasExpiredReply;
    if (live != null &&
        (expired
            ? draft?.isSupersededBy(live) == true
            : live.id != seat.thought.id ||
                  (draft != null && !draft.matches(live)))) {
      _closeComposerAfterFrame();
      return;
    }
    if (!expired) {
      if (live == null) _closeComposerAfterFrame();
      return;
    }
    if (_graceSendId != null ||
        (_graceValidated && draft != null && !draft.isInGraceAt(_now))) {
      return;
    }
    final validate = widget.validateGrace;
    if (draft == null ||
        validate == null ||
        widget.onTextReply == null ||
        _replyInput?.focusNode.hasFocus != true ||
        _replyInput?.controller.text.trim().isEmpty != false) {
      _closeComposerAfterFrame();
      return;
    }
    final validation = ++_graceValidation;
    unawaited(() async {
      var valid = false;
      try {
        valid = await validate(draft);
      } catch (_) {
        // An unavailable eligibility read cannot keep expired content open.
      }
      if (!mounted ||
          validation != _graceValidation ||
          !identical(draft, _replyDraft)) {
        return;
      }
      if (!valid) {
        _closeComposer();
        return;
      }
      setState(() => _graceValidated = true);
      _graceClock ??= Timer.periodic(const Duration(seconds: 1), (clock) {
        if (!_now.isBefore(draft.deadline)) clock.cancel();
        if (mounted) setState(() {});
      });
    }());
  }

  /// The system Back that hid the keyboard can arrive in this same frame.
  /// Keep the composer open until then so Back dismisses it before the ring.
  void _closeComposerAfterFrame() {
    final input = _replyInput;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && identical(input, _replyInput)) _closeComposer();
      })
      ..ensureVisualUpdate();
  }

  void _discardComposer() {
    final input = _replyInput;
    _replyInput = null;
    _replySeat = null;
    _pendingReplyNavigation = null;
    _replyDraft = null;
    _graceSendId = null;
    _graceClock?.cancel();
    _graceClock = null;
    _graceValidation++;
    _graceValidated = false;
    _replyNavigation++;
    _visit = _visit.closeComposer();
    if (input != null && input.mounted) {
      input.controller.clear();
      if (input.focusNode.hasFocus) input.focusNode.unfocus();
    }
  }

  void _closeComposer() {
    if (_composing) setState(_discardComposer);
  }

  bool _canAnswer(String postId) =>
      widget.onReply != null && _answerable && _center?.thought.id == postId;

  void _react(String postId, ThoughtReaction reaction) {
    if (_canAnswer(postId)) {
      unawaited(_dispatch(_visit.react(postId, reaction, const Uuid().v4())));
    }
  }

  void _sendSticker(String postId, ThoughtStickerSelection selection) {
    // Pop of the bottom sheet may complete before the covered route gets its
    // current-route notification. Recheck the focused thought after that frame.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && _canAnswer(postId) && widget.onStickerReply != null) {
          unawaited(
            _dispatch(_visit.sticker(postId, selection, const Uuid().v4())),
          );
        }
      })
      ..ensureVisualUpdate();
  }

  void _retry(OrbitDepthSend send) {
    final dispatch = _visit.retry(send.messageId);
    if (dispatch == null) return;
    final seat = _replySeat ?? _center;
    if (seat == null || seat.thought.id != send.postId) return;
    if (send.isText) {
      if (_canAnswer(send.postId) ||
          (_hasExpiredReply && _canSendDraftInGrace)) {
        unawaited(_sendText(dispatch, seat));
      }
    } else if (_canAnswer(send.postId)) {
      unawaited(_dispatch(dispatch));
    }
  }

  bool get _canSendDraftInGrace =>
      _graceValidated &&
      _graceSendId == null &&
      _replyDraft?.isInGraceAt(_now) == true;

  void _sendTyped(OrbitDepthSeat seat, TextEditingController controller) {
    if (!_enabled ||
        _replySeat?.thought.id != seat.thought.id ||
        (_hasExpiredReply && !_canSendDraftInGrace)) {
      return;
    }
    final postId = seat.thought.id;
    final latest = _visit.latestFor(postId);
    final text = controller.text;
    final dispatch =
        _hasExpiredReply &&
            latest != null &&
            latest.isText &&
            latest.canRetry &&
            latest.text == text.trim()
        ? _visit.retry(latest.messageId)
        : _visit.reply(postId, text, const Uuid().v4());
    if (dispatch != null) unawaited(_sendText(dispatch, seat));
  }

  Future<void> _sendText(
    OrbitDepthDispatch dispatch,
    OrbitDepthSeat seat,
  ) async {
    final grace = _hasExpiredReply;
    final draft = _replyDraft;
    final send = dispatch.send;
    if (grace) {
      setState(() => _graceSendId = send.messageId);
      dispatch = (visit: dispatch.visit.openComposer(send.postId), send: send);
    } else {
      _closeComposer();
    }
    final epoch = _replyNavigation;
    final landing = _settleGeneration;
    final status = await _dispatch(dispatch, textDraft: draft);
    if (!mounted ||
        epoch != _replyNavigation ||
        landing != _settleGeneration ||
        !_enabled ||
        (grace ? _graceSendId != send.messageId : !_canAnswer(send.postId))) {
      return;
    }
    if (grace) {
      if (status == ThoughtReplyStatus.sent) {
        _closeComposer();
      } else {
        setState(() => _graceSendId = null);
      }
    }
    if (status == ThoughtReplyStatus.sent) {
      widget.onTypedReplySent?.call(seat.thought.authorPeerId);
    } else if (status == ThoughtReplyStatus.queued) {
      _pendingReplyNavigation = (
        seat: seat,
        epoch: epoch,
        landing: landing,
        id: send.messageId,
        grace: grace,
      );
    }
  }

  void _maybeOpenPendingReply() {
    final pending = _pendingReplyNavigation;
    if (pending == null ||
        _visit.sends[pending.id]?.status != ThoughtReplyStatus.sent) {
      return;
    }
    _pendingReplyNavigation = null;
    final post = pending.seat.thought;
    if (pending.epoch == _replyNavigation &&
        pending.landing == _settleGeneration &&
        _enabled &&
        (pending.grace
            ? _replySeat?.thought.id == post.id
            : _canAnswer(post.id))) {
      if (pending.grace) _closeComposer();
      widget.onTypedReplySent?.call(post.authorPeerId);
    }
  }

  /// The send belongs to the host. The visit only records its answer.
  Future<ThoughtReplyStatus?> _dispatch(
    OrbitDepthDispatch? dispatch, {
    ThoughtReplyDraft? textDraft,
  }) async {
    final onReply = widget.onReply;
    if (dispatch == null || onReply == null) return null;
    final send = dispatch.send;
    final onText = widget.onTextReply;
    final onSticker = widget.onStickerReply;
    Future<ThoughtReplyStatus> sendReply(
      String text,
      String postId,
      String messageId,
    ) => send.isText && onText != null
        ? onText(text, postId, messageId, textDraft)
        : onReply(text, postId, messageId);

    final visit = dispatch.visit;
    setState(() => _visit = visit);
    final answers = widget.answers;
    if (answers != null) {
      return answers.dispatch(dispatch, sendReply, onSticker: onSticker);
    }
    final sticker = send.sticker;
    ThoughtReplyStatus status;
    try {
      status = sticker == null
          ? await sendReply(send.text, send.postId, send.messageId)
          : await onSticker?.call(sticker, send.postId, send.messageId) ??
                ThoughtReplyStatus.failed;
    } catch (_) {
      status = ThoughtReplyStatus.failed;
    }
    if (!mounted) return null;
    setState(() => _visit = _visit.settle(send.messageId, status));
    return _visit.sends[send.messageId]?.status;
  }

  @override
  void dispose() {
    widget.resetSignal?.removeListener(_reset);
    _replyStatuses?.cancel();
    widget.answers?.removeListener(_onAnswersChanged);
    _graceClock?.cancel();
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
        // BL-33: a fixed node, so turning the 3D drags off (open arcs)
        // changes only its actions. If the node went away, iOS would drop the
        // moved children's parent and report the orbit at 1/dpr.
        child: Semantics(
          container: true,
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
                          child: RepaintBoundary(
                            child: _dial(constraints.biggest),
                          ),
                        ),
                    ],
                  );
                },
              ),
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
    final places = orbitDepthPlaces(
      anchor: _anchor,
      height: size.height,
      topClearance: widget.topClearance,
      bottomClearance: widget.bottomClearance,
      scale: k,
    );
    final cy = places.ringY;
    final center = Offset(size.width / 2, cy);
    final colors = Theme.of(context).colorScheme;
    final queue = _queue;
    // Faces fly from where the flat orbit showed them to their seats, as the
    // finger drags; a face the flat orbit did not show fades in at its seat.
    final flat = _flat;
    final origin =
        flat?.self?.center ?? Offset(size.width / 2, size.height * .5);
    final from = flat?.faces ?? const <String, Rect>{};
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
    final front = lifted == null ? null : queue[lifted.index];
    final expiredReply = _hasExpiredReply && _replyDraft != null;
    final shown = expiredReply ? _replySeat : front;
    final reveal = _smooth((tiltProgress - .5) / .5);
    final named = _smooth((tiltProgress - .65) / .35);
    final presence = _reduceMotion
        ? 1.0
        : math.pow(lifted?.lift ?? 0, 2).toDouble();
    final hasDock = widget.onReply != null && shown != null && !_isOwn(shown);
    final statusRow = places.statusHeight;
    final composing = _composing;
    // The dock has an extra field and privacy line below the reaction row.
    // Only a friend's replyable card needs that space.
    const dockHeight = 145.0;
    const typingDockHeight = 160.0;
    final dockExtra = hasDock ? dockHeight - places.barHeight : 0.0;
    final cardBottom = math.max(places.areaTop, places.areaBottom - dockExtra);
    final cardInset = size.height - cardBottom;
    if (composing && shown?.thought.id != _visit.composingPostId) {
      _closeComposerAfterFrame();
    }
    final keyboard = math.max(
      widget.bottomClearance,
      MediaQuery.viewInsetsOf(context).bottom,
    );
    // The bar trails the card by about 80 ms as it lands: it is placed where
    // the card was that long ago.
    const trail = .08;
    final trailingTilt = ((_vertical.value - _vertical.velocity * trail) / 320)
        .clamp(0.0, 1.0);
    final trailingLift = lifted == null
        ? 0.0
        : (orbitCenterFaces(
                        count: queue.length,
                        pos: _turn.value - _turn.velocity * trail,
                        scale: k,
                        nextOnRight: !_rtl,
                      )
                      .where((face) => face.index == lifted.index)
                      .firstOrNull
                      ?.lift ??
                  0.0) *
              _smooth(trailingTilt);
    final barReveal = _smooth((trailingTilt - .5) / .5);
    final barPresence = _reduceMotion
        ? 1.0
        : math.pow(trailingLift, 2).toDouble();
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
            if (shown != null && !expiredReply)
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
            if (composing)
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('orbit-depth-composer-dismiss'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeComposer,
                ),
              ),
            // Faces come and go and re-sort every frame; without a key the
            // card's subtree is rebuilt and its media reloads and flickers.
            Positioned(
              key: const ValueKey('orbit-depth-card-slot'),
              left: 14 * k,
              right: 14 * k,
              top: places.areaTop,
              bottom: composing
                  ? math.min(
                      size.height - places.areaTop,
                      math.max(cardInset, keyboard + typingDockHeight),
                    )
                  : cardInset,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: IgnorePointer(
                      ignoring: composing,
                      child: Transform.translate(
                        // The thought slides up into place as the orbit tilts.
                        offset: Offset(0, (1 - reveal) * 40 * k),
                        child: Opacity(
                          // The compact quote is visible while typing. Keep
                          // this card mounted so its loaded media stays alive.
                          opacity: composing
                              ? 0
                              : (presence * reveal).clamp(0.0, 1.0).toDouble(),
                          child: fade(
                            'orbit-depth-content',
                            expiredReply
                                ? null
                                : shown != null
                                ? _card(
                                    shown,
                                    k,
                                    restHeight: cardBottom - places.areaTop,
                                  )
                                : _layer == OrbitDepthLayer.flat ||
                                      _gesture == OrbitDepthGesture.vertical
                                ? null
                                : IgnorePointer(
                                    key: const ValueKey(
                                      'orbit-depth-empty-ring',
                                    ),
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.orbit_depth_empty_ring,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 15 * k,
                                          color: colors.onSurface.withValues(
                                            alpha: .7,
                                          ),
                                        ),
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
            if (hasDock || _isOwn(shown))
              Positioned(
                key: const ValueKey('orbit-depth-answers-slot'),
                left: 14 * k,
                right: 14 * k,
                top: composing ? null : places.barTop - dockExtra,
                bottom: composing ? keyboard : null,
                child: Transform.translate(
                  offset: Offset(0, composing ? 0 : (1 - barReveal) * 40 * k),
                  child: Opacity(
                    opacity: composing
                        ? 1
                        : (barPresence * barReveal).clamp(0.0, 1.0),
                    child: IgnorePointer(
                      ignoring: !composing && trailingLift <= .5,
                      child: fade(
                        'orbit-depth-answers',
                        shown == null
                            ? null
                            : _isOwn(shown)
                            ? _ownActivity(
                                shown,
                                k,
                                places.barHeight + statusRow,
                              )
                            : _answers(shown, statusRow),
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

  bool _isOwn(OrbitDepthSeat? seat) =>
      seat != null && seat.thought.id == widget.ownSeat?.thought.id;

  /// On your own card: what friends did with it, as on the You page. A tap
  /// opens your thought.
  Widget _ownActivity(OrbitDepthSeat seat, double k, double height) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final activity = widget.ownActivity;
    final postId = seat.thought.id;
    final style = TextStyle(
      fontSize: 14 * k,
      color: colors.onSurface.withValues(alpha: .8),
    );
    final parts = <Widget>[
      if (activity != null && activity.reacted > 0)
        Text(l10n.you_page_reacted(activity.reacted), style: style),
      if (activity != null && activity.wroteBack > 0)
        Text(l10n.you_page_wrote_back(activity.wroteBack), style: style),
      if (activity != null && activity.wroteBack > 0 && activity.fresh > 0)
        Text(
          l10n.you_page_new_replies(activity.fresh),
          style: style.copyWith(color: colors.primary),
        ),
    ];
    return Semantics(
      button: true,
      onTap: _bySemantics(() => widget.onThoughtTap?.call(postId)),
      child: GestureDetector(
        key: ValueKey('orbit-depth-own-activity-$postId'),
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onThoughtTap?.call(postId),
        child: SizedBox(
          height: height,
          child: Center(
            child: Wrap(
              spacing: 14 * k,
              alignment: WrapAlignment.center,
              children: parts,
            ),
          ),
        ),
      ),
    );
  }

  Widget _answers(OrbitDepthSeat seat, double statusRow) {
    final post = seat.thought;
    final latest = _visit.latestFor(post.id);
    final typing = _visit.composingPostId == post.id;
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final graceSeconds = typing && _hasExpiredReply
        ? _graceValidated
              ? _replyDraft?.secondsRemaining(_now) ?? 0
              : 0
        : null;
    return _DepthReplyInput(
      key: ValueKey('orbit-depth-answers-${post.id}'),
      onChanged: (input) => _onReplyInputChanged(seat, input),
      builder: (controller, focusNode) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ThoughtReplyDock(
            post: post,
            authorName: seat.friend.username,
            media: _lastLoadedMedia[post.id] ?? const [],
            controller: controller,
            focusNode: focusNode,
            typing: typing,
            visit: _visit,
            reactionKeyPrefix: 'orbit-depth-react',
            onReaction: (reaction) => _react(post.id, reaction),
            onReactionActivate: (reaction) =>
                _bySemantics(() => _react(post.id, reaction))(),
            onSend: () => _sendTyped(seat, controller),
            sendEnabled:
                _graceSendId == null &&
                (!_hasExpiredReply || _canSendDraftInGrace),
            onSticker: widget.onStickerReply == null
                ? null
                : (selection) => _sendSticker(post.id, selection),
            graceSeconds: graceSeconds,
          ),
          if (!typing || _graceSendId != null)
            SizedBox(
              height: statusRow,
              child: latest == null
                  ? null
                  : _answerStatus(latest, l10n, colors),
            ),
        ],
      ),
    );
  }

  /// The thought's latest answer, worded as the full-screen card words it.
  Widget _answerStatus(
    OrbitDepthSend send,
    AppLocalizations l10n,
    ColorScheme colors,
  ) {
    final status = send.status;
    final sent = status == ThoughtReplyStatus.sent;
    final label = sent
        ? l10n.message_status_sent
        : !send.inFlight && status == ThoughtReplyStatus.failed
        ? l10n.error_send_message
        : l10n.post_sending;
    return Row(
      key: const ValueKey('orbit-depth-answer-status'),
      children: [
        if (sent) ...[
          const Icon(Icons.check_rounded, size: 16, color: _answerGreen),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: colors.onSurface),
            ),
          ),
        ),
        if (send.canRetry)
          Semantics(
            button: true,
            label: l10n.btn_retry,
            excludeSemantics: true,
            onTap: _bySemantics(() => _retry(send)),
            child: TextButton(
              key: const ValueKey('orbit-depth-answer-retry'),
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: () => _retry(send),
              child: Text(l10n.btn_retry),
            ),
          ),
      ],
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

  /// [restHeight] is the thought area's height when no reply is open.
  Widget _card(OrbitDepthSeat seat, double k, {required double restHeight}) {
    final post = seat.thought;
    final l10n = AppLocalizations.of(context)!;
    final created = DateTime.tryParse(post.createdAt)?.toUtc();
    final age = created == null ? Duration.zero : _now.difference(created);
    final ageText = age.inMinutes < 1
        ? l10n.time_just_now
        : age.inMinutes < 60
        ? l10n.time_min_ago(age.inMinutes)
        : l10n.time_hour_ago(age.inHours);
    bool openable() =>
        _enabled && !_suppressTap && liveOrbitDepthThought(post, _now) != null;
    void open() {
      if (openable()) widget.onThoughtTap?.call(post.id);
    }

    void play() {
      if (openable()) widget.onThoughtVideoPlay?.call(post.id);
    }

    final media =
        post.mediaKind != 'none' &&
            widget.loadMedia != null &&
            widget.downloadMedia != null
        ? OrbitDepthMedia(
            key: ValueKey('orbit-depth-media-${post.id}'),
            postId: post.id,
            load: widget.loadMedia!,
            download: widget.downloadMedia!,
            postChanges: widget.postChanges,
            onOpen: open,
            onPlayVideo: widget.onThoughtVideoPlay == null ? null : play,
            onActivate: _bySemantics(open),
            lastLoaded: _lastLoadedMedia,
          )
        : null;
    final voice = media != null && post.mediaKind == 'voice';
    final photo = media != null && !voice;
    final length = orbitThoughtLength(post.text);
    final centred = voice || (!photo && length != OrbitThoughtLength.long);
    final type = voice
        ? _voiceType
        : _thoughtType[photo ? OrbitThoughtLength.long : length]!;
    final colors = Theme.of(context).colorScheme;
    Widget tappable(Widget child) => GestureDetector(
      onTap: open,
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      child: child,
    );
    final ageLine = Text(
      ageText,
      style: TextStyle(fontSize: 13 * k, fontWeight: FontWeight.w600),
    );
    // A tap on a link opens it; a tap anywhere else opens the thought.
    Widget words({int? maxLines}) => DefaultTextStyle.merge(
      textAlign: centred ? TextAlign.center : null,
      child: LinkableText(
        key: ValueKey('orbit-depth-text-${post.id}'),
        text: post.text,
        textDirection: detectTextDirection(post.text),
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: type.size * k,
          fontWeight: type.weight,
          height: _thoughtLineHeight,
          color: colors.onSurface,
        ),
      ),
    );
    // As many whole lines as the space holds; the rest is cut with an
    // ellipsis.
    Widget fitted() => LayoutBuilder(
      builder: (context, box) => words(
        maxLines: math.max(
          1,
          (box.maxHeight / (type.size * k * _thoughtLineHeight)).floor(),
        ),
      ),
    );
    // The caption of a photo thought is offered for translation like any
    // text thought. The link sits outside the tap that opens the thought.
    final preview = translatePreviewEnabled && post.text.isNotEmpty
        ? TranslatePreview(
            text: post.text,
            owner: PreviewOwner.thought(post.id),
            ai: translatePreviewAi,
            delivery: translatePreviewDelivery,
            onFreeUpSpace: translatePreviewOpenStorage,
            color: colors.onSurface,
          )
        : null;
    // A drag on the thought tilts or turns the orbit, so it cannot scroll.
    // It clips to its area; the tap opens the whole thought.
    final Widget content;
    if (photo) {
      // Full width, so the text sits on its own side: an Arabic caption on
      // the right even in an English app.
      final caption = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          tappable(
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8 * k),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ageLine,
                  if (post.text.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 12 * k),
                      child: words(maxLines: 3),
                    ),
                ],
              ),
            ),
          ),
          ?preview,
        ],
      );
      // The caption and its translation take at most half of the area,
      // clipped at its end, so the photo always keeps the rest down to the
      // bar.
      content = LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              key: ValueKey('orbit-depth-caption-${post.id}'),
              constraints: BoxConstraints(maxHeight: box.maxHeight / 2),
              child: UnconstrainedBox(
                constrainedAxis: Axis.horizontal,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                child: caption,
              ),
            ),
            Expanded(child: media),
          ],
        ),
      );
    } else if (centred) {
      // While replying, the thought shows from its top, so the words sit in
      // the space above the composer instead of the middle of its rest area.
      content = Align(
        alignment: _composing ? Alignment.topCenter : Alignment.center,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (post.text.isNotEmpty) Flexible(child: tappable(fitted())),
            ?preview,
            if (voice) ...[SizedBox(height: 16 * k), media],
            SizedBox(height: 16 * k),
            tappable(Center(child: ageLine)),
          ],
        ),
      );
    } else {
      // A long thought reads from the top and is cut at the area's end.
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: tappable(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ageLine,
                  SizedBox(height: 12 * k),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: fitted(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ?preview,
        ],
      );
    }
    // Screen readers hear whose thought it is; the name is under the face.
    return Semantics(
      key: ValueKey('orbit-depth-card-${post.id}'),
      container: true,
      label: '${seat.friend.username} · $ageText',
      onTap: _bySemantics(open),
      // While replying, the thought keeps at least its resting height and
      // shows only its top, so a photo and its caption are never squeezed.
      // The clip stays mounted so a playing voice note is never rebuilt.
      child: LayoutBuilder(
        builder: (context, box) => ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: math.max(box.maxHeight, restHeight),
            child: content,
          ),
        ),
      ),
    );
  }
}

const _thoughtLineHeight = 1.3;

/// Text sizes of a thought on the background, by its length, at k = 1.
const _thoughtType = {
  OrbitThoughtLength.short: (size: 34.0, weight: FontWeight.w600),
  OrbitThoughtLength.medium: (size: 26.0, weight: FontWeight.w500),
  OrbitThoughtLength.long: (size: 22.0, weight: FontWeight.w500),
};
const _voiceType = (size: 30.0, weight: FontWeight.w600);

const _answerGreen = thoughtReactionGreen;

/// The near half of the ring is tinted light blue, as in the agreed mock; on
/// a light background the same tint would vanish, so it deepens there.
Color orbitDepthRingFront(Brightness brightness) =>
    (brightness == Brightness.dark
            ? const Color(0xFFCFE0FF)
            : const Color(0xFF2F5FB8))
        .withValues(alpha: .45);

class _DepthReplyInput extends StatefulWidget {
  const _DepthReplyInput({
    super.key,
    required this.onChanged,
    required this.builder,
  });

  final ValueChanged<_DepthReplyInputState> onChanged;
  final Widget Function(TextEditingController, FocusNode) builder;

  @override
  State<_DepthReplyInput> createState() => _DepthReplyInputState();
}

class _DepthReplyInputState extends State<_DepthReplyInput> {
  final controller = TextEditingController();
  final focusNode = FocusNode();

  void _changed() => widget.onChanged(this);

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    focusNode.addListener(_changed);
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(controller, focusNode);
}

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
