import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

part 'photos.dart';

/// Standalone visual prototype: the Orbit inner circle tilting from today's
/// flat rings into a "depth" view where friends' thoughts appear, and a way
/// through a large friend list.
///
/// Pure UI with fake friends — no identity, contacts or P2P.
/// - Swipe up on the flat orbit: it tilts away (rings become ovals, front
///   avatars grow, back avatars shrink and dim, each avatar lifts off a
///   platform that slides out from behind it, thoughts pop in).
/// - In depth, swipe sideways: the orbit turns, with momentum, so friends
///   travel round to the front.
/// - In depth, swipe up again: you fly forward through your orbit into the
///   next layer of friends (people you talk to less often). Swipe down to come
///   back, and once more to flatten.
class OrbitDepthPrototypeScreen extends StatefulWidget {
  const OrbitDepthPrototypeScreen({super.key});

  @override
  State<OrbitDepthPrototypeScreen> createState() =>
      _OrbitDepthPrototypeScreenState();
}

class _Hue {
  final Color color;
  final Color fill;

  const _Hue(this.color, this.fill);
}

const _pink = _Hue(Color(0xFFEE8FD9), Color(0xFF22131F));
const _blue = _Hue(Color(0xFF6CB4FF), Color(0xFF0F1823));
const _purple = _Hue(Color(0xFFB79CFF), Color(0xFF18132A));
const _yellow = _Hue(Color(0xFFF4D35E), Color(0xFF201D0E));
const _orange = _Hue(Color(0xFFF2A65A), Color(0xFF22170D));
const _cyan = _Hue(Color(0xFF7FD1F0), Color(0xFF0F1A1F));
const _green = _Hue(Color(0xFFA3E07F), Color(0xFF151F0F));
const _red = _Hue(Color(0xFFFF9E9E), Color(0xFF241212));
const _grey = _Hue(Color(0xFF9AA59F), Color(0xFF14181A));

class _ProtoFriend {
  final String name;
  final int layer;
  final double angleDeg;
  final _Hue hue;
  final String? thought;
  final bool fresh;
  final bool group;

  const _ProtoFriend(
    this.name,
    this.layer,
    this.angleDeg,
    this.hue, {
    this.thought,
    this.fresh = false,
    this.group = false,
  });
}

const _ground = Color(0xFF040605);
const _ink = Color(0xFFE8ECE9);
const _muted = Color(0xFF9AA59F);
const _accent = Color(0xFF1DB954);

/// One orbit per layer. Layer 0 is the people you talk to most; each deeper
/// layer holds people you talked to less recently.
const _layerNames = [
  'Recent',
  'This week',
  'This month',
  'Last few months',
  'Earlier this year',
  'A while ago',
];
const _perLayer = 7;

/// Friends in orbit order; every [_perLayer] of them make one layer.
const _people = <(String, _Hue, String?, bool)>[
  ('omar', _blue, 'exam at 9. wish me luck', true),
  ('yousef', _yellow, null, false),
  ('tarek', _cyan, 'who has a drill I can borrow?', true),
  ('nour', _purple, 'airport at 6. taxi anyone?', true),
  ('layla', _pink, 'roof sunrise again. who\u2019s up?', true),
  ('sara', _orange, 'we adopted her! meet luna', false),
  ('karim', _red, null, false),
  ('dina', _green, null, false),
  ('rami', _blue, null, false),
  ('weekend trip', _grey, null, false),
  ('zein', _yellow, null, false),
  ('maya', _orange, 'new job starts monday', true),
  ('hana', _green, null, false),
  ('adam', _cyan, null, false),
  ('lina', _pink, 'anyone watching the match?', false),
  ('faris', _purple, null, false),
  ('reem', _red, null, false),
  ('sami', _blue, null, false),
  ('dana', _pink, 'cooking for 10 tonight. come.', true),
  ('hadi', _yellow, null, false),
  ('nada', _cyan, null, false),
  ('ziad', _orange, null, false),
  ('mira', _purple, 'finally finished the book', false),
  ('basil', _green, null, false),
  ('yara', _red, null, false),
  ('fadi', _blue, null, false),
  ('salma', _pink, null, false),
  ('khaled', _yellow, 'lost my keys. again.', true),
  ('jana', _cyan, null, false),
  ('majd', _orange, null, false),
  ('rana', _purple, null, false),
  ('tamer', _green, null, false),
  ('huda', _red, 'back in town next week', false),
  ('wael', _blue, null, false),
  ('lama', _pink, null, false),
  ('jad', _yellow, null, false),
  ('rita', _cyan, null, false),
  ('maher', _orange, null, false),
  ('aya', _purple, null, false),
  ('ward', _green, 'garden finally bloomed', true),
  ('nizar', _red, null, false),
  ('sahar', _blue, null, false),
];

List<_ProtoFriend> _buildFriends() {
  // Angles: -90 is the back of the orbit (top of the screen), 90 the front.
  // Alternate layers start half a step apart so seats don't line up.
  final friends = <_ProtoFriend>[];
  for (var i = 0; i < _people.length; i++) {
    final (name, hue, thought, fresh) = _people[i];
    final layer = i ~/ _perLayer;
    final seat = i % _perLayer;
    final inLayer = math.min(_perLayer, _people.length - layer * _perLayer);
    final offset = layer.isOdd ? 180 / inLayer : 0.0;
    friends.add(
      _ProtoFriend(
        name,
        layer,
        -90 + offset + seat * 360 / inLayer,
        hue,
        thought: thought,
        fresh: fresh,
        group: name == 'weekend trip',
      ),
    );
  }
  return friends;
}

enum _ThoughtKind { text, voice, photo }

/// What a thought carries beyond its one line; shown when the friend turns
/// to the front of the orbit.
class _ThoughtDetail {
  final _ThoughtKind kind;
  final String? more;
  final int seconds;
  final String? photo;
  final int comments;
  final String age;

  const _ThoughtDetail({
    this.kind = _ThoughtKind.text,
    this.more,
    this.seconds = 0,
    this.photo,
    this.comments = 0,
    this.age = '1 d',
  });
}

const _details = <String, _ThoughtDetail>{
  'layla': _ThoughtDetail(
    kind: _ThoughtKind.photo,
    photo: 'layla_card',
    comments: 4,
    age: '2 h',
  ),
  'omar': _ThoughtDetail(
    kind: _ThoughtKind.voice,
    seconds: 14,
    comments: 2,
    age: '35 min',
  ),
  'tarek': _ThoughtDetail(
    more:
        'putting up shelves this weekend and mine died halfway through the first one.',
    comments: 1,
    age: '1 h',
  ),
  'nour': _ThoughtDetail(
    more: 'I land at 5:40 and can share the fare into the city.',
    comments: 3,
    age: '20 min',
  ),
  'sara': _ThoughtDetail(
    kind: _ThoughtKind.photo,
    photo: 'sara_card',
    comments: 6,
    age: '5 h',
  ),
  'maya': _ThoughtDetail(
    kind: _ThoughtKind.voice,
    seconds: 9,
    comments: 5,
    age: '3 h',
  ),
  'dana': _ThoughtDetail(
    more: 'making mansaf and there is way too much. bring containers.',
    comments: 2,
    age: '4 h',
  ),
};

final Map<String, MemoryImage> _photoCache = {};

/// A friend's profile photo (by name), 'you', or a post photo.
ImageProvider _photo(String key) => _photoCache.putIfAbsent(
  key,
  () => MemoryImage(base64Decode(_photoData[key]!)),
);

_ThoughtDetail _detailFor(_ProtoFriend friend) =>
    _details[friend.name] ?? const _ThoughtDetail();

final List<_ProtoFriend> _friends = _buildFriends();
final int _layerCount = _layerNames.length;

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _interval(double t, double begin, double end) =>
    ((t - begin) / (end - begin)).clamp(0.0, 1.0);

double _smoothstep(double begin, double end, double t) {
  final x = _interval(t, begin, end);
  return x * x * (3 - 2 * x);
}

enum _Axis { horizontal, vertical }

class _OrbitDepthPrototypeScreenState extends State<OrbitDepthPrototypeScreen>
    with TickerProviderStateMixin {
  /// Drag distance for flat → depth, and for each layer after that.
  static const double _tiltSpan = 320;
  static const double _layerSpan = 260;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 170,
    damping: 19,
  );

  /// Slightly bouncy, so a friend "clicks" into the front seat.
  static const _rotSpring = SpringDescription(
    mass: 1,
    stiffness: 90,
    damping: 15,
  );

  /// One vertical position in drag pixels: 0..[_tiltSpan] tilts the orbit,
  /// beyond that flies the camera through the layers. Unbounded so the
  /// spring can overshoot, which is what makes the settle feel physical.
  late final AnimationController _v = AnimationController.unbounded(
    vsync: this,
  );

  /// Orbit rotation in radians.
  late final AnimationController _rot = AnimationController.unbounded(
    vsync: this,
  );

  /// Slow idle float; also the per-frame clock for bubble fades.
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  _Axis? _axis;
  Offset _panTravel = Offset.zero;
  double _rotAtStart = 0;
  double _k = 1;
  bool _reduceMotion = false;
  bool _photosWarm = false;

  double get _tilt => (_v.value / _tiltSpan).clamp(-0.08, 1.0);
  double get _camera => math.max(0, (_v.value - _tiltSpan) / _layerSpan);
  double get _maxV => _tiltSpan + (_layerCount - 1) * _layerSpan;
  List<double> get _snaps => [
    0,
    for (var i = 0; i < _layerCount; i++) _tiltSpan + i * _layerSpan,
  ];

  @override
  void initState() {
    super.initState();
    _rot.value = _snapRotation(0, 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_photosWarm) {
      _photosWarm = true;
      for (final key in _photoData.keys) {
        precacheImage(_photo(key), context);
      }
    }
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat();
    }
  }

  @override
  void dispose() {
    _v.dispose();
    _rot.dispose();
    _float.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    _axis = null;
    _rotAtStart = _rot.value;
    _panTravel = Offset.zero;
    _v.stop();
    _rot.stop();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Lock the axis once the finger has really moved; the first update can
    // carry a zero delta.
    if (_axis == null) {
      _panTravel += details.delta;
      if (_panTravel.distance < 4) return;
      _axis = _panTravel.dx.abs() > _panTravel.dy.abs()
          ? _Axis.horizontal
          : _Axis.vertical;
    }
    if (_axis == _Axis.horizontal) {
      if (_tilt < 0.5) return;
      _rot.value -= details.delta.dx / (128 * _k);
      return;
    }
    var delta = -details.delta.dy;
    final next = _v.value + delta;
    if (next > _maxV || next < 0) delta *= 0.35;
    _v.value = (_v.value + delta).clamp(-60.0, _maxV + 90);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_axis == null) {
      final v = details.velocity.pixelsPerSecond;
      _axis = v.dx.abs() > v.dy.abs() ? _Axis.horizontal : _Axis.vertical;
    }
    if (_axis == _Axis.horizontal) {
      if (_tilt < 0.5) return;
      final spin = _reduceMotion
          ? 0.0
          : -details.velocity.pixelsPerSecond.dx / (128 * _k);
      // Coast a quarter second's worth of the flick (at most half a turn),
      // then land the nearest friend exactly at the front.
      final coast = (spin * 0.25).clamp(-math.pi, math.pi);
      final layer = _layer;
      var target = _snapRotation(layer, _rot.value + coast);
      // Pager feel: a deliberate drag of a fifth of a seat moves to the next
      // friend in that direction even if it would round back.
      final from = _snapRotation(layer, _rotAtStart);
      final dragged = _rot.value - _rotAtStart;
      final seat = 2 * math.pi / _friends.where((f) => f.layer == layer).length;
      if ((target - from).abs() < 1e-6 && dragged.abs() > seat * 0.2) {
        target = _snapRotation(layer, from + dragged.sign * seat);
      }
      _snapTo(target, spin);
      return;
    }
    final velocity = -details.velocity.pixelsPerSecond.dy;
    _settle(_pickSnap(velocity), velocity);
  }

  double _pickSnap(double velocity) {
    final v = _v.value;
    final snaps = _snaps;
    if (velocity > 400) {
      return snaps.firstWhere((s) => s > v + 1, orElse: () => snaps.last);
    }
    if (velocity < -400) {
      return snaps.lastWhere((s) => s < v - 1, orElse: () => snaps.first);
    }
    return snaps.reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);
  }

  int get _layer => _camera.round().clamp(0, _layerCount - 1);

  /// The rotation closest to [predicted] that puts one of [layer]'s friends
  /// exactly at the front of the orbit (90 degrees).
  double _snapRotation(int layer, double predicted) {
    var best = predicted;
    var bestGap = double.infinity;
    for (final f in _friends) {
      if (f.layer != layer) continue;
      final base = math.pi / 2 - f.angleDeg * math.pi / 180;
      final turns = ((predicted - base) / (2 * math.pi)).round();
      final candidate = base + turns * 2 * math.pi;
      final gap = (candidate - predicted).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = candidate;
      }
    }
    return best;
  }

  void _snapTo(double target, double velocity) {
    if (_reduceMotion) {
      _rot.value = target;
      return;
    }
    _rot.animateWith(
      SpringSimulation(_rotSpring, _rot.value, target, velocity),
    );
  }

  void _toggle() => _settle(_tilt >= 0.5 ? 0 : _tiltSpan, 0);

  void _settle(double target, double velocity) {
    HapticFeedback.selectionClick();
    if (_reduceMotion) {
      _v.value = target;
    } else {
      _v.animateWith(SpringSimulation(_spring, _v.value, target, velocity));
    }
    // Arriving at a layer lands one of its friends at the front too.
    if (target >= _tiltSpan) {
      final layer = ((target - _tiltSpan) / _layerSpan).round();
      _snapTo(_snapRotation(layer, _rot.value), 0);
    }
  }

  void _openThought(_ProtoFriend friend) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B100E),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _ThoughtSheet(friend: friend),
      ),
    );
  }

  String _hint() {
    if (_tilt < 0.5) return 'Swipe up to see thoughts';
    final layer = _camera.round();
    if (layer == 0) return 'Swipe sideways to turn · up to go further';
    if (layer >= _layerCount - 1) return 'Swipe down to come back';
    return 'Up to go further · down to come back';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Orbit depth prototype',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Toggle depth',
                    onPressed: _toggle,
                    icon: const Icon(Icons.layers_outlined, color: _ink),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: LayoutBuilder(
                  builder: (context, box) {
                    _k = math.min(box.maxWidth / 390, box.maxHeight / 640);
                    return AnimatedBuilder(
                      animation: Listenable.merge([_v, _rot, _float]),
                      builder: (context, _) => _OrbitStage(
                        t: _tilt,
                        camera: _camera,
                        rotation: _rot.value,
                        floatPhase: _reduceMotion
                            ? 0
                            : _float.value * 2 * math.pi,
                        size: box.biggest,
                        onFriendTap: _openThought,
                      ),
                    );
                  },
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _v,
              builder: (context, _) {
                final hint = _hint();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      hint,
                      key: ValueKey(hint),
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// How one layer of friends sits relative to the camera.
class _LayerView {
  final int layer;

  /// Layers ahead of the camera are positive; a layer you flew past is
  /// negative.
  final double rel;
  final double scale;
  final double cy;
  final double opacity;

  const _LayerView(this.layer, this.rel, this.scale, this.cy, this.opacity);
}

/// One friend's projected seat for the current tilt, rotation and camera.
class _Seat {
  final _ProtoFriend friend;
  final int index;
  final _LayerView layer;
  final Offset ringPoint;
  final Offset avatarCenter;
  final double size;
  final double opacity;
  final double depth;
  final Size pedestal;

  const _Seat({
    required this.friend,
    required this.index,
    required this.layer,
    required this.ringPoint,
    required this.avatarCenter,
    required this.size,
    required this.opacity,
    required this.depth,
    required this.pedestal,
  });

  bool get interactive => layer.rel.abs() < 0.35;
}

class _OrbitStage extends StatelessWidget {
  final double t;
  final double camera;
  final double rotation;
  final double floatPhase;
  final Size size;
  final ValueChanged<_ProtoFriend> onFriendTap;

  const _OrbitStage({
    required this.t,
    required this.camera,
    required this.rotation,
    required this.floatPhase,
    required this.size,
    required this.onFriendTap,
  });

  @override
  Widget build(BuildContext context) {
    final k = math.min(size.width / 390, size.height / 640);
    final cx = size.width / 2;
    final tc = t.clamp(0.0, 1.0);
    // Flat, the orbit sits in the middle of the screen. Tilting lifts it, so
    // the front friend's card gets the lower part of the screen, while the far
    // orbit stays visible just under the layer meter.
    final cy = size.height * _lerp(0.5, 0.4, tc);
    final farCy = 78 * k;
    final tilt = t.clamp(-0.05, 1.0) * 52 * math.pi / 180;
    final c = math.cos(tilt);
    final s = math.sin(tilt);
    final ringBase = k * _lerp(140, 150, tc);

    final layers = <int, _LayerView>{};
    for (var layer = 0; layer < _layerCount; layer++) {
      final rel = layer - camera;
      // Only the orbit you are on and the next one, far away. The one after
      // that stays hidden until you start flying towards it.
      if (rel < -0.75 || rel > 1.3) continue;
      final scale = rel >= 0
          ? math.pow(0.14, rel).toDouble()
          : 1 + (-rel) * 1.8;
      final layerCy = rel >= 0
          ? cy - rel * (cy - farCy)
          : cy + (-rel) * 320 * k;
      var opacity = rel >= 0
          ? (rel <= 1
                ? 1 - 0.55 * rel
                : math.max(0.0, 0.45 * (1.3 - rel) / 0.3))
          : math.max(0.0, 1 + rel * 1.5);
      if (layer > 0) opacity *= tc;
      if (opacity <= 0.01) continue;
      layers[layer] = _LayerView(layer, rel, scale, layerCy, opacity);
    }

    final seats = <_Seat>[];
    for (var i = 0; i < _friends.length; i++) {
      final f = _friends[i];
      final lv = layers[f.layer];
      if (lv == null) continue;
      final radius = ringBase * lv.scale;
      final base = 52 * k * lv.scale;
      final theta = f.angleDeg * math.pi / 180 + rotation;
      final d = math.sin(theta);
      final ring = Offset(
        cx + radius * math.cos(theta),
        lv.cy + radius * math.sin(theta) * c,
      );
      final avatarSize = base * (1 + 0.3 * d * s);
      final float = math.sin(floatPhase + i * 0.9) * 2.5 * k * tc * lv.scale;
      final lift = (avatarSize / 2 + 2 * k * lv.scale) * tc;
      final pedW = _lerp(avatarSize * 0.9, avatarSize * 1.35, tc);
      final pedH = _lerp(
        avatarSize * 0.9,
        math.max(4 * k * lv.scale, avatarSize * 1.35 * c * 0.42),
        tc,
      );
      seats.add(
        _Seat(
          friend: f,
          index: i,
          layer: lv,
          ringPoint: ring,
          avatarCenter: ring.translate(0, -lift + float),
          size: avatarSize,
          opacity: (1 - 0.45 * ((1 - d) / 2) * s).clamp(0.0, 1.0) * lv.opacity,
          depth: d,
          pedestal: Size(pedW, pedH),
        ),
      );
    }
    // Far layers behind near ones; within a layer, back of the orbit first.
    seats.sort((a, b) {
      final byLayer = b.layer.rel.compareTo(a.layer.rel);
      if (byLayer != 0) return byLayer;
      return a.ringPoint.dy.compareTo(b.ringPoint.dy);
    });

    // The friend at the front of the current orbit is under the highlight:
    // the only name shown, a brighter platform, a slight lift, and (when they
    // shared a thought) the card.
    final appear = _interval(tc, 0.55, 0.9);
    _Seat? spotlight;
    for (final seat in seats) {
      if (seat.layer.rel.abs() >= 0.35) continue;
      if (spotlight == null || seat.depth > spotlight.depth) spotlight = seat;
    }
    final highlight = spotlight == null
        ? 0.0
        : _smoothstep(0.88, 0.995, spotlight.depth) *
              appear *
              (1 - spotlight.layer.rel.abs() * 3).clamp(0.0, 1.0);

    final home = layers[0];
    final youSize = 76 * k * (home?.scale ?? 1);
    final youRing = Offset(cx, home?.cy ?? cy);
    final youCenter = youRing.translate(0, -(youSize / 2 + 2 * k) * tc * 0.6);
    final youPedestal = Size(
      _lerp(youSize * 0.9, youSize * 1.55, tc),
      _lerp(youSize * 0.9, math.max(4 * k, youSize * 1.55 * c * 0.42), tc),
    );

    final children = <Widget>[
      Positioned.fill(
        child: CustomPaint(
          painter: _DepthPainter(
            t: tc,
            k: k,
            cx: cx,
            camera: camera,
            rotation: rotation,
            layers: layers.values.toList(),
            ringBase: ringBase,
            squash: c,
            seats: seats,
            youRing: home == null ? null : youRing,
            youPedestal: youPedestal,
            youOpacity: home?.opacity ?? 0,
            youSize: youSize,
            spotlight: spotlight,
            highlight: highlight,
            floatPhase: floatPhase,
          ),
        ),
      ),
    ];

    // A label under the far orbit; the one you are on is named by the meter.
    for (final lv in layers.values) {
      if (lv.rel < 0.3) continue;
      final count = _friends.where((f) => f.layer == lv.layer).length;
      children.add(
        Positioned(
          left: cx - 80 * k,
          top: lv.cy + ringBase * lv.scale * c + 8 * k,
          width: 160 * k,
          child: IgnorePointer(
            child: Opacity(
              opacity: lv.opacity,
              child: Text(
                '${_layerNames[lv.layer]} \u00b7 $count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _muted,
                  fontSize: 11 * k * math.max(lv.scale, 0.8),
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
      );
    }

    var youPlaced = home == null;
    void placeYou() {
      children.add(
        _positionedCircle(
          center: youCenter,
          size: youSize,
          child: IgnorePointer(
            ignoring: home!.rel.abs() > 0.35,
            child: Opacity(
              opacity: home.opacity,
              child: _YouAvatar(size: youSize, t: tc),
            ),
          ),
        ),
      );
      youPlaced = true;
    }

    for (final seat in seats) {
      if (!youPlaced &&
          seat.layer.layer == 0 &&
          seat.ringPoint.dy > youRing.dy) {
        placeYou();
      }
      children.add(
        _positionedCircle(
          center: seat.avatarCenter,
          size: seat.size,
          child: IgnorePointer(
            ignoring: !seat.interactive,
            child: _FriendAvatar(
              key: ValueKey('avatar-${seat.friend.name}'),
              seat: seat,
              highlight: identical(seat, spotlight) ? highlight : 0,
              onTap: () => onFriendTap(seat.friend),
            ),
          ),
        ),
      );
    }
    if (!youPlaced) placeYou();

    final named = spotlight;
    if (named != null && highlight > 0.01) {
      final scale = named.layer.scale;
      children.add(
        Positioned(
          left: named.ringPoint.dx - 60 * k * scale,
          top: _nameTop(named, k, tc) + 2 * k * scale,
          width: 120 * k * scale,
          child: IgnorePointer(
            child: Opacity(
              opacity: highlight.clamp(0.0, 1.0),
              child: Text(
                named.friend.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _ink,
                  fontSize: 14 * k * scale,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      );
    }

    children.addAll(_bubbles(seats, k, tc, spotlight, highlight));

    if (tc > 0.02) {
      children.add(_layerMeter(k, tc, size.height));
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }

  /// Where things under an avatar start: just below the front edge of its
  /// platform once tilted (the disc plus its edge), under the avatar when flat.
  double _nameTop(_Seat seat, double k, double tc) =>
      seat.ringPoint.dy +
      _lerp(
        seat.size / 2,
        seat.pedestal.height * 0.55 + 4 * k * seat.layer.scale,
        tc,
      );

  /// Thought bubbles never disappear while the orbit turns. Friends at the
  /// back carry theirs above the head, friends at the front below the name;
  /// at the sides, where both spots are free, the bubble cross-fades from one
  /// to the other. A bubble that would land on a neighbour's is nudged
  /// further out instead of hidden.
  List<Widget> _bubbles(
    List<_Seat> seats,
    double k,
    double tc,
    _Seat? spotlight,
    double highlight,
  ) {
    final candidates =
        seats
            .where((s) => s.friend.thought != null && s.layer.rel.abs() < 0.5)
            .toList()
          ..sort((a, b) => b.depth.compareTo(a.depth));
    final takenAbove = <Rect>[];
    final takenBelow = <Rect>[];
    final widgets = <Widget>[];
    final appear = _interval(tc, 0.55, 0.9);

    // The spotlight friend's bubble grows into a card in the free space below
    // the orbit, dropping just low enough to clear the neighbours' bubbles.
    final focus = spotlight?.friend.thought == null ? 0.0 : highlight;
    for (final seat in candidates) {
      final scale = seat.layer.scale;
      final fade = appear * (1 - seat.layer.rel.abs() * 2.5).clamp(0.0, 1.0);
      if (fade <= 0.01) continue;
      final width = 100 * k * scale;
      final text = seat.friend.thought!;
      final height = (text.length > 16 ? 42 : 27) * k * scale;
      final left = (seat.ringPoint.dx - width / 2)
          .clamp(6 * k, math.max(6 * k, size.width - width - 6 * k))
          .toDouble();
      final avatarTop = seat.avatarCenter.dy - seat.size / 2;
      final isSpotlight = identical(seat, spotlight) && focus > 0.01;
      final below = _smoothstep(-0.05, 0.3, seat.depth);
      final gap = 4 * k * scale;

      Rect nudge(Rect rect, List<Rect> taken, {required bool down}) {
        for (var pass = 0; pass < 4; pass++) {
          final hit = taken.where((r) => r.overlaps(rect)).toList();
          if (hit.isEmpty) break;
          rect = down
              ? rect.translate(
                  0,
                  hit.map((r) => r.bottom).reduce(math.max) + gap - rect.top,
                )
              : rect.translate(
                  0,
                  hit.map((r) => r.top).reduce(math.min) - gap - rect.bottom,
                );
        }
        taken.add(rect);
        return rect;
      }

      Widget bubble(double alpha, {required bool growFromTop}) =>
          _ThoughtBubble(
            text: text,
            fresh: seat.friend.fresh,
            k: k * scale,
            appear: alpha,
            growFromTop: growFromTop,
            onTap: () => onFriendTap(seat.friend),
          );

      if (1 - below > 0.01) {
        final rect = nudge(
          Rect.fromLTWH(
            left,
            avatarTop - 6 * k * scale - height,
            width,
            height,
          ),
          takenAbove,
          down: false,
        );
        widgets.add(
          Positioned(
            left: left,
            bottom: size.height - rect.bottom,
            width: width,
            child: bubble(fade * (1 - below), growFromTop: false),
          ),
        );
      }
      if (isSpotlight) {
        final top = _nameTop(seat, k, tc) + (16 + 22 * focus) * k * scale;
        final cardWidth = _lerp(
          width,
          math.min(320 * k, size.width - 32 * k),
          focus,
        );
        widgets.add(
          Positioned(
            key: ValueKey('card-${seat.friend.name}'),
            left: (seat.ringPoint.dx - cardWidth / 2)
                .clamp(
                  12 * k,
                  math.max(12 * k, size.width - cardWidth - 12 * k),
                )
                .toDouble(),
            top: top,
            width: cardWidth,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(0, size.height - top - 8 * k),
              ),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: _ThoughtCard(
                  friend: seat.friend,
                  expand: focus,
                  k: k * scale,
                  alpha: fade * below,
                  onOpen: () => onFriendTap(seat.friend),
                ),
              ),
            ),
          ),
        );
      } else if (below > 0.01) {
        final rect = nudge(
          Rect.fromLTWH(
            left,
            _nameTop(seat, k, tc) + 4 * k * scale,
            width,
            height,
          ),
          takenBelow,
          down: true,
        );
        widgets.add(
          Positioned(
            left: left,
            top: rect.top,
            width: width,
            child: bubble(fade * below, growFromTop: true),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _layerMeter(double k, double tc, double height) {
    final active = camera.round().clamp(0, _layerCount - 1);
    final count = _friends.where((f) => f.layer == active).length;
    return Positioned(
      left: 0,
      right: 0,
      top: 4,
      child: IgnorePointer(
        child: Opacity(
          opacity: _interval(tc, 0.5, 1),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _layerCount; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == active ? _accent : const Color(0xFF2E3B35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: 10),
              Text(
                '${_layerNames[active]} · $count',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _positionedCircle({
    required Offset center,
    required double size,
    required Widget child,
  }) {
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      height: size,
      child: child,
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  final _Seat seat;
  final double highlight;
  final VoidCallback onTap;

  const _FriendAvatar({
    super.key,
    required this.seat,
    required this.highlight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final f = seat.friend;
    final radius = f.group
        ? BorderRadius.circular(seat.size * 0.3)
        : BorderRadius.circular(seat.size / 2);
    return Semantics(
      button: true,
      label: f.thought == null ? f.name : '${f.name}: ${f.thought}',
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: seat.opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1 + 0.08 * highlight,
            alignment: Alignment.bottomCenter,
            child: _Sheen(
              radius: f.group ? radius : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  // Lit from above: lighter at the top, deeper at the bottom.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(f.hue.fill, f.hue.color, 0.22)!,
                      f.hue.fill,
                      Color.lerp(f.hue.fill, Colors.black, 0.4)!,
                    ],
                  ),
                  border: Border.all(color: f.hue.color, width: 2),
                  boxShadow: [
                    const BoxShadow(
                      color: Color(0x73000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                    if (highlight > 0.01)
                      BoxShadow(
                        color: f.hue.color.withValues(alpha: 0.45 * highlight),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: ClipRRect(
                    borderRadius: f.group
                        ? BorderRadius.circular(seat.size * 0.3 - 2)
                        : BorderRadius.circular(seat.size / 2),
                    child: Image(
                      image: _photo(f.name),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft highlight from the top left laid over an avatar, so it reads as a
/// rounded object catching the light rather than a flat sticker. Sits over a
/// real photo just as well.
class _Sheen extends StatelessWidget {
  final Widget child;

  /// Corner radius for square avatars (groups); null means a circle.
  final BorderRadius? radius;

  const _Sheen({required this.child, this.radius});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: radius,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.55, 1],
                colors: [Color(0x00000000), Color(0x40000000)],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: radius,
              gradient: const RadialGradient(
                center: Alignment(-0.35, -0.55),
                radius: 0.75,
                colors: [Color(0x2EFFFFFF), Color(0x00FFFFFF)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _YouAvatar extends StatelessWidget {
  final double size;
  final double t;

  const _YouAvatar({required this.size, required this.t});

  @override
  Widget build(BuildContext context) {
    return _Sheen(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0F1F15),
          border: Border.all(color: _accent, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: _lerp(0.12, 0.32, t)),
              blurRadius: _lerp(12, 36, t),
              spreadRadius: _lerp(1, 8, t),
            ),
          ],
        ),
        child: Semantics(
          label: 'You',
          child: Padding(
            padding: const EdgeInsets.all(2.5),
            child: ClipOval(
              child: Image(
                image: _photo('you'),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThoughtBubble extends StatelessWidget {
  final String text;
  final bool fresh;
  final double k;
  final double appear;
  final bool growFromTop;
  final VoidCallback onTap;

  const _ThoughtBubble({
    required this.text,
    required this.fresh,
    required this.k,
    required this.appear,
    required this.growFromTop,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = 0.6 + 0.4 * Curves.easeOutBack.transform(appear);
    return Opacity(
      opacity: appear.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        alignment: growFromTop ? Alignment.topCenter : Alignment.bottomCenter,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 9 * k, vertical: 6 * k),
            decoration: BoxDecoration(
              color: fresh ? const Color(0xFF0F1F15) : const Color(0xFF141A18),
              borderRadius: BorderRadius.circular(14 * k),
              border: Border.all(
                color: fresh ? _accent : const Color(0xFF26322D),
                width: fresh ? 1.5 : 1,
              ),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fresh ? _ink : const Color(0xFFB4C0B9),
                fontSize: 11.5 * k,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The spotlight thought: a compact bubble at [expand] 0 that grows into a
/// card with the name, the full text, a photo or a voice note, and comments.
class _ThoughtCard extends StatefulWidget {
  final _ProtoFriend friend;
  final double expand;
  final double k;
  final double alpha;
  final VoidCallback onOpen;

  const _ThoughtCard({
    required this.friend,
    required this.expand,
    required this.k,
    required this.alpha,
    required this.onOpen,
  });

  @override
  State<_ThoughtCard> createState() => _ThoughtCardState();
}

class _ThoughtCardState extends State<_ThoughtCard>
    with SingleTickerProviderStateMixin {
  late final _ThoughtDetail _detail = _detailFor(widget.friend);
  late final AnimationController _playback = AnimationController(
    vsync: this,
    duration: Duration(seconds: math.max(1, _detail.seconds)),
  )..addStatusListener(_onPlaybackStatus);

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  void _onPlaybackStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _playback.value = 0;
      setState(() {});
    }
  }

  void _togglePlayback() {
    setState(() {
      if (_playback.isAnimating) {
        _playback.stop();
      } else {
        _playback.forward();
      }
    });
  }

  @override
  void didUpdateWidget(_ThoughtCard old) {
    super.didUpdateWidget(old);
    // Turning away from the front stops the voice note.
    if (widget.expand < 0.5 && _playback.isAnimating) _playback.stop();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expand;
    final k = widget.k;
    final friend = widget.friend;
    final extra = _interval(e, 0.45, 1);
    final fresh = friend.fresh;

    Widget reveal(Widget child) => ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: extra,
        child: Opacity(opacity: extra, child: child),
      ),
    );

    return Opacity(
      opacity: widget.alpha.clamp(0.0, 1.0),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: _lerp(9, 14, e) * k,
            vertical: _lerp(6, 12, e) * k,
          ),
          decoration: BoxDecoration(
            color: fresh ? const Color(0xFF0F1F15) : const Color(0xFF141A18),
            borderRadius: BorderRadius.circular(_lerp(14, 20, e) * k),
            border: Border.all(
              color: fresh ? _accent : const Color(0xFF26322D),
              width: fresh ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (extra > 0)
                reveal(
                  Padding(
                    padding: EdgeInsets.only(bottom: 6 * k),
                    child: Text(
                      '${_detail.age} ago',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12 * k,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              Text(
                friend.thought!,
                textAlign: TextAlign.center,
                maxLines: e < 0.5 ? 2 : 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fresh ? _ink : const Color(0xFFB4C0B9),
                  fontSize: _lerp(11.5, 15.5, e) * k,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
              if (extra > 0) reveal(_extras(k)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _extras(double k) {
    final detail = _detail;
    final more = detail.more;
    final photo = detail.photo;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (more != null)
          Padding(
            padding: EdgeInsets.only(top: 6 * k),
            child: Text(
              more,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFFB4C0B9),
                fontSize: 13 * k,
                height: 1.35,
              ),
            ),
          ),
        if (detail.kind == _ThoughtKind.photo && photo != null)
          Padding(
            padding: EdgeInsets.only(top: 10 * k),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12 * k),
              child: SizedBox(
                height: 124 * k,
                width: double.infinity,
                child: Image(
                  image: _photo(photo),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        if (detail.kind == _ThoughtKind.voice)
          Padding(
            padding: EdgeInsets.only(top: 10 * k),
            child: _voiceRow(k),
          ),
        Padding(
          padding: EdgeInsets.only(top: 10 * k),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 15 * k, color: _muted),
              SizedBox(width: 5 * k),
              Flexible(
                child: Text(
                  detail.comments == 1
                      ? '1 comment'
                      : '${detail.comments} comments',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted, fontSize: 12.5 * k),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: widget.onOpen,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 4 * k),
                  child: Text(
                    'Reply',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 13 * k,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _voiceRow(double k) {
    return AnimatedBuilder(
      animation: _playback,
      builder: (context, _) {
        final playing = _playback.isAnimating;
        final remaining = (_detail.seconds * (1 - _playback.value))
            .ceil()
            .clamp(0, 999);
        return Row(
          children: [
            Tooltip(
              message: playing ? 'Pause voice note' : 'Play voice note',
              child: GestureDetector(
                onTap: _togglePlayback,
                child: Container(
                  width: 34 * k,
                  height: 34 * k,
                  decoration: const BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    size: 20 * k,
                    color: const Color(0xFF03140A),
                  ),
                ),
              ),
            ),
            SizedBox(width: 10 * k),
            Expanded(
              child: SizedBox(
                height: 28 * k,
                child: CustomPaint(
                  painter: _WaveformPainter(progress: _playback.value),
                ),
              ),
            ),
            SizedBox(width: 10 * k),
            Text(
              '0:${remaining.toString().padLeft(2, '0')}',
              style: TextStyle(color: _muted, fontSize: 12.5 * k),
            ),
          ],
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;

  _WaveformPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 30;
    final step = size.width / bars;
    final barWidth = step * 0.55;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < bars; i++) {
      final level =
          0.25 +
          0.75 *
              (0.5 + 0.5 * math.sin(i * 0.9) * math.cos(i * 0.37 + 1.2)).abs();
      final h = size.height * level;
      final x = i * step + step / 2;
      paint
        ..color = i / bars <= progress ? _accent : const Color(0xFF3A4741)
        ..strokeWidth = barWidth;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.progress != progress;
}

/// A star with a direction from the centre, a spread and a depth in [0, 1).
class _Star {
  final double angle;
  final double spread;
  final double z;

  const _Star(this.angle, this.spread, this.z);
}

final List<_Star> _stars = () {
  final random = math.Random(7);
  return [
    for (var i = 0; i < 56; i++)
      _Star(
        random.nextDouble() * 2 * math.pi,
        0.15 + random.nextDouble() * 0.85,
        random.nextDouble(),
      ),
  ];
}();

class _DepthPainter extends CustomPainter {
  final double t;
  final double k;
  final double cx;
  final double camera;
  final double rotation;
  final List<_LayerView> layers;
  final double ringBase;
  final double squash;
  final List<_Seat> seats;
  final Offset? youRing;
  final Size youPedestal;
  final double youOpacity;
  final double youSize;
  final _Seat? spotlight;
  final double highlight;
  final double floatPhase;

  _DepthPainter({
    required this.t,
    required this.k,
    required this.cx,
    required this.camera,
    required this.rotation,
    required this.layers,
    required this.ringBase,
    required this.squash,
    required this.seats,
    required this.youRing,
    required this.youPedestal,
    required this.youOpacity,
    required this.youSize,
    required this.spotlight,
    required this.highlight,
    required this.floatPhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintStars(canvas, size);

    for (final lv in layers) {
      _oval(
        canvas,
        Offset(cx, lv.cy),
        ringBase * lv.scale,
        const Color(0xFF2E3B35).withValues(alpha: lv.opacity),
        dashLength: 6 * k * lv.scale,
      );
    }

    // Platforms: start as a circle hidden behind the avatar, then flatten
    // into a glowing disc as the avatar lifts off it.
    final reveal = Curves.easeOut.transform(t);
    final you = youRing;
    if (you != null) {
      _pedestal(
        canvas,
        you,
        youPedestal,
        _accent,
        youOpacity,
        reveal,
        avatarSize: youSize,
      );
    }
    for (final seat in seats) {
      _pedestal(
        canvas,
        seat.ringPoint,
        seat.pedestal,
        seat.friend.hue.color,
        seat.opacity,
        reveal,
        avatarSize: seat.size,
        glow: identical(seat, spotlight) ? highlight : 0,
      );
    }
  }

  /// Stars stream outward as the camera flies forward and drift with the
  /// rotation, which is most of the "moving through space" feeling.
  void _paintStars(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45);
    final reach = size.longestSide * 0.75;
    final paint = Paint();
    for (final star in _stars) {
      var z = (star.z - camera * 0.45) % 1.0;
      if (z <= 0) z += 1;
      final distance = star.spread * reach * (0.3 / (z + 0.3));
      final angle = star.angle + rotation * 0.12;
      final position =
          center + Offset(math.cos(angle), math.sin(angle)) * distance;
      final fadeIn = (z < 0.12 ? z / 0.12 : 1.0);
      final twinkle = 0.75 + 0.25 * math.sin(floatPhase * 2 + star.angle * 5);
      final alpha = ((1 - z) * fadeIn * twinkle * (0.25 + 0.75 * t)).clamp(
        0.0,
        1.0,
      );
      paint.color = const Color(0xFF9AA59F).withValues(alpha: alpha * 0.8);
      canvas.drawCircle(position, (0.6 + (1 - z) * 1.4) * k, paint);
    }
  }

  void _oval(
    Canvas canvas,
    Offset center,
    double radius,
    Color color, {
    double dashLength = 6,
  }) {
    if (color.a <= 0.01) return;
    final rect = Rect.fromCenter(
      center: center,
      width: radius * 2,
      height: radius * 2 * squash,
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addOval(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashLength),
          paint,
        );
        distance += dashLength * 2;
      }
    }
  }

  /// The platform under an avatar: a soft pool of light on the orbit's
  /// floor, a faint outline and a gentle contact shadow where the avatar
  /// stands. No hard edge, so it stays quiet under real photos. [glow]
  /// brightens the spotlight friend's platform.
  void _pedestal(
    Canvas canvas,
    Offset at,
    Size pedestal,
    Color color,
    double opacity,
    double reveal, {
    required double avatarSize,
    double glow = 0,
  }) {
    final strength = opacity * reveal;
    if (strength <= 0.01) return;
    final rect = Rect.fromCenter(
      center: at,
      width: pedestal.width,
      height: pedestal.height,
    );
    double a(double v) => (v * strength).clamp(0.0, 1.0);

    // Soft bloom around it.
    canvas.drawOval(
      rect.inflate(4 * k),
      Paint()
        ..color = color.withValues(alpha: a(0.14 + 0.18 * glow))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, (10 + 6 * glow) * k),
    );
    // The pool of light itself, brightest under the avatar.
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: a(0.26 + 0.16 * glow)),
            color.withValues(alpha: a(0.06)),
          ],
        ).createShader(rect),
    );
    // Contact shadow where the avatar stands.
    canvas.drawOval(
      Rect.fromCenter(
        center: at.translate(0, -rect.height * 0.06),
        width: avatarSize * 0.55,
        height: math.max(2 * k, rect.height * 0.32),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: a(0.32))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * k),
    );
    // A faint outline.
    canvas.drawOval(
      rect,
      Paint()
        ..color = color.withValues(alpha: a(0.28 + 0.2 * glow))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(_DepthPainter old) => true;
}

class _ThoughtSheet extends StatelessWidget {
  final _ProtoFriend friend;

  const _ThoughtSheet({required this.friend});

  @override
  Widget build(BuildContext context) {
    final thought = friend.thought;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (thought != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1F15),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _accent, width: 1.5),
                ),
                child: Text(
                  thought,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              thought == null
                  ? '${friend.name} hasn’t shared a thought today'
                  : '${friend.name} · ${_detailFor(friend).age} ago',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
            if (thought != null) ...[
              const SizedBox(height: 18),
              TextField(
                style: const TextStyle(color: _ink),
                decoration: InputDecoration(
                  hintText: 'Comment on ${friend.name}’s thought',
                  hintStyle: const TextStyle(color: Color(0xFF78837C)),
                  filled: true,
                  fillColor: const Color(0xFF0E1311),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(23),
                    borderSide: const BorderSide(color: Color(0xFF1C2420)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
