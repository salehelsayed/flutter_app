import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background_mirrored.dart';

part 'carousel.dart';
part 'chat.dart';
part 'circles.dart';
part 'friends_list.dart';
part 'photos.dart';
part 'post_photos.dart';
part 'requests.dart';
part 'spaces.dart';
part 'thread.dart';
part 'world.dart';
part 'you.dart';

/// Standalone visual prototype of Mknoon v1: one home, the orbit, and no
/// tabs.
///
/// Pure UI with fake friends — no identity, contacts or P2P.
/// - The orbit opens flat: your photo in the middle, your Close friends
///   round it with their thoughts in bubbles. Tap a face to chat with them.
/// - Swipe up: the orbit tilts into depth on Close and turns to the first
///   unseen thought, shown as a card with a reply dock under it. Swipe
///   sideways to turn the ring; up once more for Friends; down to come back,
///   and once more to flatten.
/// - People (top corner) lists friends of friends who chose to be found,
///   each in their own words: what they are open for, and which of your
///   friends carry them. Knock, or ask that friend to introduce you.
/// - Chats (other corner) holds requests, every conversation and knocks
///   still waiting. Your photo opens You; its + shares a thought.
class OrbitDepthPrototypeScreen extends StatelessWidget {
  const OrbitDepthPrototypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Its own navigator, so each screen can fly in over the last one, and
    // its own messenger for the short notes that something arrived.
    // System back reaches it too, so the orbit can flatten before leaving.
    return ScaffoldMessenger(
      key: _messenger,
      child: NavigatorPopHandler<Object?>(
        onPopWithResult: (_) => _navigator.currentState?.maybePop(),
        child: Navigator(
          key: _navigator,
          onGenerateRoute: (_) =>
              _diveRoute(const _OrbitHome(), animateIn: false),
        ),
      ),
    );
  }
}

final GlobalKey<NavigatorState> _navigator = GlobalKey();

/// Puts every sample back the way the prototype opens: chats, requests,
/// rings, your thoughts and settings. Tests start each case from here.
@visibleForTesting
void resetOrbitPrototype() {
  for (final t in _friendTimers) {
    t.cancel();
  }
  _friendTimers.clear();
  _seenThoughts.clear();
  _closeNames
    ..clear()
    ..addAll(_seedClose);
  _rings = _Rings.build();
  _postIndex.clear();
  _slideAt.clear();
  _sent.clear();
  _dms
    ..clear()
    ..addAll(_seedDms());
  _myReactions
    ..clear()
    ..['layla#1'] = '😍';
  _answering.clear();
  _messenger.currentState?.clearSnackBars();
  _reaches
    ..clear()
    ..addAll(_seedReaches());
  _requests
    ..clear()
    ..addAll(_seedRequests());
  _blocked.clear();
  _pausedBridges.clear();
  _yourThoughts
    ..clear()
    ..addAll(_seedThoughts());
  _nextThoughtId = 100;
  _reactionsTo
    ..clear()
    ..addAll(_seedReactions());
  _lastAudience = _Audience.friends;
  _picked.clear();
  _findable = true;
  _yourOpenTo
    ..clear()
    ..addAll(['books', 'running partners']);
  _yourOpenNote = _seedOpenNote;
  _spaceOpen
    ..clear()
    ..addAll({'Books': true, 'Runs': false});
  _carryCards = true;
  _carryForAll = true;
  _passToCloseOnly = true;
  _weeklyCount = false;
}

class _OrbitHome extends StatefulWidget {
  const _OrbitHome();

  @override
  State<_OrbitHome> createState() => _OrbitHomeState();
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

  /// 0 is the Close ring, 1 the Friends ring.
  final int layer;
  final double angleDeg;
  final _Hue hue;
  final String? thought;
  final bool fresh;

  /// The last slot on the Friends ring stands for everyone without a slot:
  /// how many they are. 0 for a person.
  final int more;

  const _ProtoFriend(
    this.name,
    this.layer,
    this.angleDeg,
    this.hue, {
    this.thought,
    this.fresh = false,
    this.more = 0,
  });
}

const _ground = Color(0xFF040605);
const _ink = Color(0xFFE8ECE9);
const _muted = Color(0xFF9AA59F);
const _accent = Color(0xFF1DB954);

/// The chat room's colours (the app's dark BackgroundReadableColors): cards,
/// bubbles and sheets use the same fill, border and text as chat bubbles.
const _chat = BackgroundReadableColors.dark;
const _sheet = Color(0xFF181A20);

/// BackgroundReadableColors.dark.textSecondary, usable in const contexts.
const _chatSecondary = Color(0xDDE5E7EB);

/// The two rings, inside out. You choose who is Close; everyone else is a
/// Friend. Thoughts are shared with the same two audiences.
const _ringNames = ['Close', 'Friends'];
const _layerCount = 2;

/// Faces on the Friends ring; one more slot, "+N", opens everyone.
const _friendSlots = 12;

/// Close holds at most this many.
const _closeLimit = 15;

/// Everyone you know, the people you talk to most first: name, colour, the
/// thought they shared today, and whether you have not seen it yet.
const _people = <(String, _Hue, String?, bool)>[
  ('omar', _blue, 'exam at 9. wish me luck', true),
  ('yousef', _yellow, null, false),
  ('tarek', _cyan, 'who has a drill I can borrow?', true),
  ('nour', _purple, 'airport at 6. taxi anyone?', true),
  ('layla', _pink, 'weekend up north. still can’t feel my legs', true),
  ('sara', _orange, 'we adopted her! meet luna', false),
  ('karim', _red, null, false),
  ('dina', _green, null, false),
  ('rami', _blue, null, false),
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

/// Your Close friends, the inner ring. You choose them (You › Close friends,
/// or a long press on a face).
final Set<String> _closeNames = {..._seedClose};

const _seedClose = {'omar', 'tarek', 'nour', 'layla', 'sara', 'dina'};

/// Who sits where. Slots are dealt once, when the app opens or Close
/// changes, and never move while you look at them.
class _Rings {
  /// Every friend, whether or not they have a slot.
  final List<_ProtoFriend> everyone;

  /// The faces on the orbit: all of Close, then the first [_friendSlots] of
  /// Friends and the "+N" slot.
  final List<_ProtoFriend> seats;

  const _Rings(this.everyone, this.seats);

  factory _Rings.build() {
    final close = [
      for (final p in _people)
        if (_closeNames.contains(p.$1)) p,
    ];
    // The Friends ring: unseen thoughts first, then the people you talk to
    // most.
    bool unseen((String, _Hue, String?, bool) p) =>
        p.$3 != null && p.$4 && !_seenThoughts.contains(p.$1);
    final others = [
      for (final p in _people)
        if (!_closeNames.contains(p.$1) && unseen(p)) p,
      for (final p in _people)
        if (!_closeNames.contains(p.$1) && !unseen(p)) p,
    ];
    final seated = others.take(_friendSlots).length;
    final more = others.length - seated;

    final everyone = <_ProtoFriend>[];
    final seats = <_ProtoFriend>[];
    // Angles: -90 is the back of the orbit (top of the screen), 90 the
    // front. The Friends ring starts half a step round, so faces don't line
    // up behind each other.
    void deal(
      List<(String, _Hue, String?, bool)> list,
      int layer,
      int n,
      int slots,
    ) {
      final offset = layer.isOdd ? 180 / n : 0.0;
      for (var i = 0; i < list.length; i++) {
        final (name, hue, thought, fresh) = list[i];
        final friend = _ProtoFriend(
          name,
          layer,
          -90 + offset + i * 360 / n,
          hue,
          thought: thought,
          fresh: fresh,
        );
        everyone.add(friend);
        if (i < slots) seats.add(friend);
      }
    }

    deal(close, 0, close.length, close.length);
    final friendSeats = seated + (more > 0 ? 1 : 0);
    deal(others, 1, friendSeats, seated);
    if (more > 0) {
      seats.add(
        _ProtoFriend(
          '+$more',
          1,
          -90 + 180 / friendSeats + seated * 360 / friendSeats,
          _grey,
          more: more,
        ),
      );
    }
    return _Rings(everyone, seats);
  }
}

var _rings = _Rings.build();

/// Ticks when someone moves between Close and Friends.
final ValueNotifier<int> _ringTick = ValueNotifier(0);

List<_ProtoFriend> get _friends => _rings.seats;
List<_ProtoFriend> get _everyone => _rings.everyone;

_ProtoFriend? _friendNamed(String name) {
  for (final f in _everyone) {
    if (f.name == name) return f;
  }
  return null;
}

bool _isFriend(String name) => _friendNamed(name) != null;

/// Moves [name] between Close and Friends; the rings are dealt again.
void _setClose(String name, bool close) {
  if (close) {
    if (_closeNames.length >= _closeLimit) return;
    _closeNames.add(name);
  } else {
    _closeNames.remove(name);
  }
  _rings = _Rings.build();
  _ringTick.value++;
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

/// Friends who never set a photo: they show the app's default ring avatar,
/// generated from their peer id exactly as in the main app.
const _ringAvatarPeers = <String, String>{
  'karim': '12D3KooWKarimQ7xR2mPqL7vN3sT8bW1cY5dZ',
  'rami': '12D3KooWRamiH4kM9pXcV2nB6zQ1wE8rT5yU',
  'adam': '12D3KooWAdamZ3fG7hJ2kL9mN4bV6cX1qW8e',
  'sami': '12D3KooWSamiP8oI7uY6tR5eW4qA3sD2fG1h',
  'tamer': '12D3KooWTamerL2kJ3hG4fD5sA6qW7eR8tY9',
  'majd': '12D3KooWMajdX9cV8bN7mQ6wE5rT4yU3iO2p',
  'rita': '12D3KooWRitaE3rT6yU9iO2pA5sD8fG1hJ4k',
  'nizar': '12D3KooWNizarM1nB2vC3xZ4lK5jH6gF7dS8',
  'jana': '12D3KooWJanaQ5wE7rT9yU1iO3pA6sD8fG2h',
};

final Map<String, MemoryImage> _photoCache = {};

/// A friend's profile photo (by name), 'you', or a post photo.
ImageProvider _photo(String key) => _photoCache.putIfAbsent(
  key,
  () => MemoryImage(
    base64Decode(
      _photoData[_photoAliases[key] ?? key] ?? _postPhotoData[key]!,
    ),
  ),
);

_ThoughtDetail _detailFor(_ProtoFriend friend) =>
    _details[friend.name] ?? const _ThoughtDetail();

/// The knobs that shape the depth view, gathered so variants can be compared.
/// Defaults are the current look.
class OrbitDepthTuning {
  OrbitDepthTuning._();

  /// How far the orbit leans back.
  static double tiltDegrees = 52;

  /// Orbit radius and avatar size (points).
  static double ringRadius = 150;
  static double avatarSize = 52;

  /// Your own avatar in the centre (points).
  static double youSize = 76;

  /// Linear depth: front avatars grow and back ones shrink by this fraction.
  static double depthScale = 0.3;

  /// True perspective instead: a camera [cameraDistance] orbit-radii away,
  /// so near avatars grow faster than far ones shrink.
  static bool perspective = false;
  static double cameraDistance = 3;

  /// How much friends at the back fade.
  static double backDim = 0.45;

  /// How much thought bubbles follow their avatar's depth (0 = all the same
  /// size).
  static double bubbleDepth = 0;

  /// What to draw (the playground's "Show" switches).
  static bool showStars = true;
  static bool showRing = true;
  static bool showFarOrbit = true;
  static bool showBeam = true;
  static bool showCard = true;
  static bool showBubbles = true;

  /// Where the orbit's centre sits, as a share of the screen height.
  static double orbitHeight = 0.34;

  /// The flat orbit the app opens on (Close alone): where its centre sits,
  /// its radius and the faces' size. Tilting blends from these to depth.
  static double flatOrbitHeight = 0.5;
  static double flatRingRadius = 140;
  static double flatAvatarSize = 52;
  static double flatYouSize = 76;

  /// Platform width as a multiple of the avatar.
  static double platformSize = 1.35;

  /// The platform under your own avatar in the middle.
  static double youPlatformSize = 1.55;

  /// 1 = platforms lie flat on the orbit's tilt, squashed exactly like the
  /// ring; lower is flatter, higher rounder.
  static double platformFlatness = 1;

  /// Gap between an avatar's bottom edge and the centre of its platform
  /// (points); negative sinks it into the platform. [youHover] is the same
  /// for your own avatar in the middle.
  static double avatarHover = 2;
  static double youHover = -10;

  /// The far ring (Friends, seen from Close): its own tilt (null = same as
  /// [tiltDegrees]), size, position from the top, and brightness.
  static double? farOrbitTilt;
  static double farOrbitSize = 0.14;
  static double farOrbitY = 44;
  static double farOrbitBrightness = 0.45;

  /// Thought bubbles.
  static OrbitBubbleStyle bubbleStyle = OrbitBubbleStyle.classic;
  static double bubbleWidth = 100;
  static double bubbleTextSize = 11.5;
  static double maxBubbleSize = 10;
  static double bubbleTint = 0.18;
  static bool unreadDot = true;
  static OrbitNeighbourBubbles frontNeighbourBubbles =
      OrbitNeighbourBubbles.auto;

  /// Where thoughts show: bubbles over a flat orbit, and in depth either a
  /// dot on the avatar (the front friend's thought opens as the card) or the
  /// bubbles as before.
  static bool bubblesWhenFlat = true;
  static OrbitDepthThoughts thoughtsInDepth = OrbitDepthThoughts.dots;

  /// The friend at the front.
  static double frontFriendLift = 0.08;
  static double frontNameSize = 14;

  /// The front card and the beam above it.
  static double cardGap = 44;
  static double cardWidth = 1;
  static double cardScale = 1;
  static double maxPhotoHeight = 168;
  static double beamStrength = 1;

  /// How text posts sit on the stage: in a framed card, or straight on the
  /// night sky, as if from the universe.
  static OrbitPostCards postCards = OrbitPostCards.framed;

  /// Dial: once tilted, the orbit sits small and low around you with the
  /// front friend nearest, and their card takes the screen above it. The
  /// next ring waits outside and closes in; the ring you leave draws in to
  /// you and fades.
  static bool dial = false;

  /// Where the dial rests, as a share of the screen height: at the top with
  /// the card below, or at the bottom with the card above. Dragging the
  /// orbit moves it between the two; [dialOnTop] is where it starts.
  static double dialTopHeight = 0.084;
  static double dialBottomHeight = 0.8;
  static bool dialOnTop = false;
}

/// Framed: a dark card with an outline. Universe: no card at all; the words
/// float on the background.
enum OrbitPostCards { framed, universe }

/// Notes bubbles: a little narrower than the classic box's width times
/// this, and never more than [_notesLines] lines.
const double _notesWidth = 1.12;
const int _notesLines = 2;

/// Classic: a fixed-width box. Notes: hugs its text, soft fill, a thought tail
/// of two little dots towards the friend (like Instagram Notes).
enum OrbitBubbleStyle { classic, notes }

/// How thoughts show on the orbit.
enum OrbitDepthThoughts { dots, bubbles }

/// What the bubbles of the friends either side of an open card do.
enum OrbitNeighbourBubbles { auto, above, small, dot, hide }

double _depthScale(double depth, double s) {
  if (!OrbitDepthTuning.perspective) {
    return 1 + OrbitDepthTuning.depthScale * depth * s;
  }
  final camera = OrbitDepthTuning.cameraDistance;
  return camera / (camera - depth * s);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// The next ring out waits faintly around the dial (rel 1): only its far
/// side, a little wider. How much of a face or a stretch of ring at depth
/// [depth] (-1 back, 1 front) shows for a layer [rel] rings ahead.
double _peekShow(double rel, double depth) => rel <= 0
    ? 1
    : _lerp(1, _smoothstep(0.15, -0.35, depth), rel.clamp(0.0, 1.0));

/// How bright the waiting ring is.
const double _peekAlpha = 0.4;

/// A point on a dial ring seen through a camera [OrbitDepthTuning.cameraDistance]
/// radii away: its offset from the ring's centre, and how much nearer than
/// the centre it is (the size it grows by). [c] and [s] are the cosine and
/// sine of the ring's tilt; [lean] rolls the whole orbit a little.
(Offset, double) _dialProject(
  double theta,
  double radius,
  double c,
  double s,
  double lean,
) {
  final cam = OrbitDepthTuning.cameraDistance;
  final near = cam / (cam - math.sin(theta) * s);
  final p = Offset(
    radius * math.cos(theta) * near,
    radius * math.sin(theta) * c * near,
  );
  if (lean == 0) return (p, near);
  final cl = math.cos(lean), sl = math.sin(lean);
  return (Offset(p.dx * cl - p.dy * sl, p.dx * sl + p.dy * cl), near);
}

double _interval(double t, double begin, double end) =>
    ((t - begin) / (end - begin)).clamp(0.0, 1.0);

double _smoothstep(double begin, double end, double t) {
  final x = _interval(t, begin, end);
  return x * x * (3 - 2 * x);
}

/// The furthest a friend slides along the flat orbit to clear a bubble.
const double _maxShift = 15 * math.pi / 180;

enum _Axis { horizontal, vertical }

/// You shared a thought to this ring (0 Close, 1 Friends); it glows once.
final ValueNotifier<(int, int)> _sharedTo = ValueNotifier((0, 0));

class _OrbitHomeState extends State<_OrbitHome> with TickerProviderStateMixin {
  /// Drag distance for flat → depth, and from Close on to Friends.
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

  /// One vertical position in drag pixels: 0 is flat, 0..[_tiltSpan] tilts
  /// the orbit onto Close, one [_layerSpan] further flies on to Friends.
  /// Unbounded so the spring can overshoot, which is what makes the settle
  /// feel physical.
  late final AnimationController _v = AnimationController.unbounded(
    vsync: this,
  );

  /// Orbit rotation in radians.
  late final AnimationController _rot = AnimationController.unbounded(
    vsync: this,
  );

  /// On the dial, how far the orbit rolls with the finger turning it.
  late final AnimationController _lean = AnimationController.unbounded(
    vsync: this,
  );

  /// On the dial, where the orbit rests: 0 at the top, 1 at the bottom.
  /// From the flat orbit, swiping up opens the dial with the orbit at the
  /// top; swiping down, at the bottom.
  late final AnimationController _dock = AnimationController.unbounded(
    vsync: this,
    value: OrbitDepthTuning.dialOnTop ? 0 : 1,
  );

  /// Which way is "on" (further out): up when the orbit went to the top,
  /// down when it went to the bottom.
  double get _outward =>
      OrbitDepthTuning.dial && _dock.value > 0.5 ? -1.0 : 1.0;

  /// Leaving the flat orbit: the direction of the swipe picks where the
  /// orbit goes. [dy] is the swipe's vertical travel or speed.
  void _pickDock(double dy) {
    if (!OrbitDepthTuning.dial || _v.value > 1) return;
    _dock.value = dy > 0 ? 1 : 0;
  }

  /// 1 while a finger is turning the orbit: the open card folds back into
  /// its bubble so the thumb never sits on its text, and opens on release.
  late final AnimationController _duck = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 260),
  );

  /// 1 once fingers spread on the tilted orbit (see [_OrbitStage.overview]).
  late final AnimationController _overview = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  /// 1 once fingers spread on the flat orbit (see [_OrbitStage.flatZoom]).
  late final AnimationController _flatZoom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  /// Fingers on the orbit, for the pinch, and their spread when the second
  /// one landed.
  final Map<int, Offset> _fingers = {};
  double? _pinchFrom;

  /// This pinch already zoomed in or out; one pinch decides once, so the
  /// fingers lifting can't flip it back.
  bool _pinchDecided = false;

  /// A second finger landed during this drag: it was a pinch, so letting go
  /// neither flicks the orbit round nor flies between rings.
  bool _pinched = false;


  /// Slow idle float; also the per-frame clock for bubble fades.
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  /// The ring you just shared a thought to, glowing once.
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  _Axis? _axis;
  Offset _panTravel = Offset.zero;
  double _rotAtStart = 0;
  double _k = 1;
  bool _reduceMotion = false;
  bool _photosWarm = false;

  /// The friend whose new thought is open at the front. Turning on to
  /// someone else marks it seen.
  String? _reading;

  double get _tilt => (_v.value / _tiltSpan).clamp(-0.08, 1.0);
  double get _camera => math.max(0, (_v.value - _tiltSpan) / _layerSpan);
  double get _maxV => _tiltSpan + (_layerCount - 1) * _layerSpan;
  List<double> get _snaps => [
    0,
    for (var i = 0; i < _layerCount; i++) _tiltSpan + i * _layerSpan,
  ];

  /// Where ring [layer] stands, in [_v].
  double _ringAt(int layer) => _tiltSpan + layer * _layerSpan;

  @override
  void initState() {
    super.initState();
    _seenTick.addListener(_onSeen);
    _ringTick.addListener(_onRings);
    _sharedTo.addListener(_onShared);
    _rot.value = _restRotation(0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_photosWarm) {
      _photosWarm = true;
      for (final key in [..._photoData.keys, ..._postPhotoData.keys]) {
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

  void _onSeen() {
    if (mounted) setState(() {});
  }

  // Close changed: everyone has a new slot, so land a face at the front.
  void _onRings() {
    if (!mounted) return;
    setState(() => _rot.value = _snapRotation(_layer, _rot.value));
  }

  void _onShared() {
    if (!mounted) return;
    _glowLayer = _sharedTo.value.$1;
    if (_reduceMotion) return;
    _glow.forward(from: 0);
  }

  int _glowLayer = 0;

  @override
  void dispose() {
    _seenTick.removeListener(_onSeen);
    _ringTick.removeListener(_onRings);
    _sharedTo.removeListener(_onShared);
    _v.dispose();
    _rot.dispose();
    _lean.dispose();
    _dock.dispose();
    _float.dispose();
    _duck.dispose();
    _overview.dispose();
    _flatZoom.dispose();
    _glow.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    _pinched = _fingers.length > 1;
    _axis = null;
    _rotAtStart = _rot.value;
    _panTravel = Offset.zero;
    _v.stop();
    _rot.stop();
  }

  void _onFinger(PointerEvent e) {
    if (e is PointerDownEvent || e is PointerMoveEvent) {
      _fingers[e.pointer] = e.localPosition;
    } else {
      _fingers.remove(e.pointer);
    }
    if (_fingers.length != 2) {
      _pinchFrom = null;
      _pinchDecided = false;
      return;
    }
    _pinched = true;
    final spread = (_fingers.values.first - _fingers.values.last).distance;
    // iOS can report both touches at one spot as they lift; that is not a
    // pinch.
    if (spread < 24 || _pinchDecided) return;
    final from = _pinchFrom ??= spread;
    // Fingers apart open the bubbles; together close them.
    final open = spread / from > 1.12;
    final close = spread / from < 0.88;
    if (!open && !close) return;
    _pinchDecided = true;
    // Flat, the pinch shows or hides the bubbles; tilted, it trades the card
    // for a bubble over everyone.
    final zoom = _tilt < 0.5 ? _flatZoom : _overview;
    if (open == (zoom.value == 1)) return;
    HapticFeedback.selectionClick();
    if (_reduceMotion) {
      zoom.value = open ? 1 : 0;
    } else if (open) {
      zoom.forward();
    } else {
      zoom.reverse();
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Two fingers pinch; they neither turn nor tilt the orbit, even after
    // one lifts and the drag point jumps to the other.
    if (_fingers.length > 1 || _pinched) return;
    // Lock the axis once the finger has really moved; the first update can
    // carry a zero delta.
    if (_axis == null) {
      _panTravel += details.delta;
      if (_panTravel.distance < 4) return;
      _axis = _panTravel.dx.abs() > _panTravel.dy.abs()
          ? _Axis.horizontal
          : _Axis.vertical;
      if (_axis == _Axis.vertical) _pickDock(_panTravel.dy);
    }
    if (_axis == _Axis.horizontal) {
      // The flat orbit holds still; it turns once tilted.
      if (_tilt < 0.5) return;
      _setTurning(true);
      // Arabic mirrors the turn, like a pager.
      final rtl = Directionality.of(context) == TextDirection.rtl;
      _rot.value -= (rtl ? -1 : 1) * details.delta.dx / (128 * _k);
      if (OrbitDepthTuning.dial && !_reduceMotion) {
        final target = (details.delta.dx * 0.01).clamp(-0.06, 0.06);
        _lean.value = _lerp(_lean.value, target, 0.25);
      }
      return;
    }
    var delta = -details.delta.dy * _outward;
    final next = _v.value + delta;
    if (next > _maxV || next < 0) delta *= 0.35;
    _v.value = (_v.value + delta).clamp(-60.0, _maxV + 90);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_pinched) {
      _pinched = false;
      _setTurning(false);
      if (_tilt >= 0.5) _snapTo(_snapRotation(_layer, _rot.value), 0);
      _settle(_pickSnap(0), 0);
      return;
    }
    if (_axis == null) {
      final v = details.velocity.pixelsPerSecond;
      _axis = v.dx.abs() > v.dy.abs() ? _Axis.horizontal : _Axis.vertical;
      if (_axis == _Axis.vertical) _pickDock(v.dy);
    }
    if (_axis == _Axis.horizontal) {
      if (_tilt < 0.5) return;
      final rtl = Directionality.of(context) == TextDirection.rtl;
      _finishTurn(
        -(rtl ? -1 : 1) * details.velocity.pixelsPerSecond.dx / (128 * _k),
      );
      return;
    }
    final velocity = -details.velocity.pixelsPerSecond.dy * _outward;
    _settle(_pickSnap(velocity), velocity);
  }

  void _onPanCancel() => _setTurning(false);

  void _setTurning(bool turning) {
    if (!turning && _lean.value != 0) {
      _lean.animateWith(SpringSimulation(_spring, _lean.value, 0, 0));
    }
    if (_reduceMotion) {
      _duck.value = turning ? 1 : 0;
    } else if (turning) {
      _duck.forward();
    } else {
      _duck.reverse();
    }
  }

  double get _seatStep =>
      2 * math.pi / _friends.where((f) => f.layer == _layer).length;

  /// Ends a turn with [spin] in radians per
  /// second: coast a quarter second's worth of the flick (at most half a
  /// turn), then land the nearest friend exactly at the front.
  void _finishTurn(double spin) {
    _setTurning(false);
    if (_reduceMotion) spin = 0;
    final coast = (spin * 0.25).clamp(-math.pi, math.pi);
    final layer = _layer;
    var target = _snapRotation(layer, _rot.value + coast);
    // Pager feel: a deliberate drag of a fifth of a seat moves to the next
    // friend in that direction even if it would round back.
    final from = _snapRotation(layer, _rotAtStart);
    final dragged = _rot.value - _rotAtStart;
    if ((target - from).abs() < 1e-6 && dragged.abs() > _seatStep * 0.2) {
      target = _snapRotation(layer, from + dragged.sign * _seatStep);
    }
    _snapTo(target, spin);
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
      final candidate = _rotationFor(f, predicted);
      final gap = (candidate - predicted).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = candidate;
      }
    }
    return best;
  }

  /// The rotation nearest [from] that puts [f] at the front.
  double _rotationFor(_ProtoFriend f, double from) {
    final base = math.pi / 2 - f.angleDeg * math.pi / 180;
    final turns = ((from - base) / (2 * math.pi)).round();
    return base + turns * 2 * math.pi;
  }

  /// Where [layer] comes to rest: on its first unseen thought, else on the
  /// nearest face.
  double _restRotation(int layer) {
    for (final f in _friends) {
      if (f.layer == layer && _isNew(f)) return _rotationFor(f, _rot.value);
    }
    return _snapRotation(layer, _rot.value);
  }

  void _snapTo(double target, double velocity) {
    if (_reduceMotion) {
      _rot.value = target;
      _landed();
      return;
    }
    _rot
        .animateWith(SpringSimulation(_rotSpring, _rot.value, target, velocity))
        .whenCompleteOrCancel(_landed);
  }

  /// A face came to rest at the front. The new thought you were reading
  /// before is seen now: its dot goes and its face steps back.
  void _landed() {
    if (!mounted) return;
    final front = _frontFriend;
    final reading = _reading;
    if (reading != null && reading != front?.name) {
      _seenThoughts.add(reading);
      _seenTick.value++;
    }
    _reading = front != null && _isNew(front) ? front.name : null;
  }

  void _goToRing(int layer) {
    if (layer == _layer && (_v.value - _ringAt(layer)).abs() < 1) return;
    _settle(_ringAt(layer), 0);
  }

  void _settle(double target, double velocity) {
    HapticFeedback.selectionClick();
    if (_reduceMotion) {
      _v.value = target;
    } else {
      _v.animateWith(SpringSimulation(_spring, _v.value, target, velocity));
    }
    // Arriving at a ring turns it to its first unseen thought.
    if (target >= _tiltSpan) {
      final layer = ((target - _tiltSpan) / _layerSpan).round();
      _snapTo(_restRotation(layer), 0);
    }
  }

  /// One stop back towards flat: Friends to Close, Close to flat.
  void _stepBack() {
    final down = _snaps.lastWhere((s) => s < _v.value - 1, orElse: () => 0.0);
    _settle(down, 0);
  }

  /// The friend at the front of the ring you are on.
  _ProtoFriend? get _frontFriend {
    if (_tilt < 0.5) return null;
    _ProtoFriend? best;
    var bestGap = double.infinity;
    for (final f in _friends) {
      if (f.layer != _layer) continue;
      var gap =
          (f.angleDeg * math.pi / 180 + _rot.value - math.pi / 2) %
          (2 * math.pi);
      if (gap > math.pi) gap -= 2 * math.pi;
      if (gap.abs() < bestGap) {
        bestGap = gap.abs();
        best = f;
      }
    }
    return best;
  }

  /// The dock answers the slide showing on the front friend's live thought,
  /// or the older post you swiped up to.
  _DockTarget? get _dockTarget {
    final f = _frontFriend;
    if (f == null || f.thought == null) return null;
    final onLive = (_postIndex[f.name] ?? 0) == 0;
    return _DockTarget(f, onLive ? (_slideAt[f.name] ?? 0) : null);
  }

  /// A face: you open You; "+N" opens everyone. Flat, a friend opens your
  /// chat with them, their new thought ready to quote. In depth, a friend
  /// turns to the front, and the friend already there opens the chat.
  void _onFace(_ProtoFriend? friend) {
    if (friend == null) {
      _openYou(context);
      return;
    }
    if (friend.more > 0) {
      _openFriendsList(context);
      return;
    }
    if (_tilt >= 0.5 && friend.name != _frontFriend?.name) {
      HapticFeedback.selectionClick();
      _snapTo(_rotationFor(friend, _rot.value), 0);
      return;
    }
    // Flat, and at the front of the dial, the chat opens on their thought.
    final quote = _tilt < 0.5 || OrbitDepthTuning.dial
        ? _freshQuote(friend)
        : null;
    _openDm(context, friend.name, quote: quote);
  }

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: AnimatedBuilder(
        animation: Listenable.merge([_v, _seenTick, _chatTick]),
        builder: (context, _) => SizedBox(
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Which ring you stand on, once tilted. The dial names
              // its rings on the orbit itself.
              if (!OrbitDepthTuning.dial)
                IgnorePointer(
                ignoring: _tilt < 0.5,
                child: Opacity(
                  opacity: _interval(_tilt, 0.4, 0.9),
                  child: _RingSwitch(active: _layer, onPick: _goToRing),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: IconButton(
                  key: const ValueKey('open-reach'),
                  tooltip: 'People you can reach',
                  onPressed: () => _openReach(context),
                  icon: const Icon(Icons.people_outline, color: _ink),
                ),
              ),
              const Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _ChatsButton(),
              ),
            ],
          ),
        ),
      ),
    );
    final body = Scaffold(
      backgroundColor: Colors.transparent,
      // The dock rides the keyboard itself; the orbit stays put.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (!OrbitDepthTuning.dial) header,
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Listener(
                      onPointerDown: _onFinger,
                      onPointerMove: _onFinger,
                      onPointerUp: _onFinger,
                      onPointerCancel: _onFinger,
                      child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      onPanCancel: _onPanCancel,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          _k = math.min(
                            box.maxWidth / 390,
                            box.maxHeight / 640,
                          );
                          return AnimatedBuilder(
                            animation: Listenable.merge([
                              _v,
                              _rot,
                              _lean,
                              _dock,
                              _float,
                              _duck,
                              _overview,
                              _flatZoom,
                              _glow,
                              _chatTick,
                              _seenTick,
                            ]),
                            builder: (context, _) => _OrbitStage(
                              t: _tilt,
                              camera: _camera,
                              rotation: _rot.value,
                              floatPhase: _reduceMotion
                                  ? 0
                                  : _float.value * 2 * math.pi,
                              duck: _duck.value,
                              overview: Curves.easeOutCubic.transform(
                                _overview.value,
                              ),
                              flatZoom: Curves.easeOutCubic.transform(
                                _flatZoom.value,
                              ),
                              glow: _glow.isAnimating
                                  ? math.sin(_glow.value * math.pi)
                                  : 0,
                              glowLayer: _glowLayer,
                              size: box.biggest,
                              lean: _lean.value,
                              onRing: _goToRing,
                              dock: _dock.value,
                              onCardTap: (f) =>
                                  _openThought(context, f.name, 0),
                              onFace: _onFace,
                              onShare: () => _openComposer(context),
                              onHold: (f) => _openFriendMenu(context, f),
                            ),
                          );
                        },
                      ),
                    ),
                    ),
                  ),
                  // Every thought in this ring seen.
                  Positioned(
                    top: 4,
                    left: 0,
                    right: 0,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_v, _seenTick]),
                      builder: (context, _) {
                        final layer = _layer;
                        final caughtUp =
                            _tilt > 0.6 &&
                            (_v.value - _ringAt(layer)).abs() < 40 &&
                            !_friends.any(
                              (f) => f.layer == layer && _isNew(f),
                            );
                        return IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: caughtUp ? 1 : 0,
                            duration: const Duration(milliseconds: 300),
                            child: Center(
                              child: Text(
                                caughtUp ? 'All caught up' : '',
                                key: caughtUp
                                    ? const ValueKey('all-caught-up')
                                    : null,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Flat: how many new thoughts wait in depth.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: MediaQuery.paddingOf(context).bottom + 20,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_v, _seenTick]),
                      builder: (context, _) {
                        final unseen = _friends.where(_isNew).length;
                        final show = 1 - _interval(_tilt, 0.05, 0.4);
                        if (OrbitDepthTuning.dial ||
                            unseen == 0 ||
                            show <= 0.01) {
                          return const SizedBox.shrink();
                        }
                        return Opacity(
                          opacity: show,
                          child: Center(
                            child: _TiltHint(
                              unseen: unseen,
                              onTap: () => _settle(_tiltSpan, 0),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // One reply dock for the whole screen, aimed at whatever
                  // the front card is showing.
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _v,
                        _rot,
                        _duck,
                        _slideTick,
                      ]),
                      builder: (context, _) {
                        final target = _dockTarget;
                        final show = target == null || OrbitDepthTuning.dial
                            ? 0.0
                            : _interval(_tilt, 0.6, 1) *
                                  (1 - _duck.value * 0.5);
                        if (target == null || show <= 0.01) {
                          return const SizedBox.shrink();
                        }
                        return Opacity(
                          opacity: show,
                          child: _ReplyDock(target: target, k: _k),
                        );
                      },
                    ),
                  ),
                  // On the dial the orbit runs up under the header; its
                  // buttons float over the sky.
                  if (OrbitDepthTuning.dial)
                    Positioned(top: 0, left: 0, right: 0, child: header),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // Back walks down the stops before it leaves: Friends, Close, flat.
    return AnimatedBuilder(
      animation: _v,
      builder: (context, child) => PopScope(
        canPop: _v.value < 1,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _stepBack();
        },
        child: child!,
      ),
      child: body,
    );
  }
}

/// Chats, in the top corner: requests, every conversation and knocks that
/// wait. Its badge counts unread chats and requests.
class _ChatsButton extends StatelessWidget {
  const _ChatsButton();

  @override
  Widget build(BuildContext context) {
    final count = _unreadChats() + _requests.length;
    return IconButton(
      key: const ValueKey('open-chats'),
      tooltip: 'Chats',
      onPressed: () => _openChats(context),
      icon: Badge(
        key: const ValueKey('chats-badge'),
        isLabelVisible: count > 0,
        backgroundColor: _accent,
        textColor: const Color(0xFF03140A),
        label: Text('$count'),
        child: const Icon(Icons.chat_bubble_outline, color: _ink),
      ),
    );
  }
}

/// "3 new thoughts", under the flat orbit: tap (or swipe up) to tilt into
/// them.
class _TiltHint extends StatelessWidget {
  final int unseen;
  final VoidCallback onTap;

  const _TiltHint({required this.unseen, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$unseen new ${unseen == 1 ? 'thought' : 'thoughts'}. Show them',
    excludeSemantics: true,
    child: GestureDetector(
      key: const ValueKey('tilt-hint'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.keyboard_arrow_up_rounded, color: _accent),
            Text(
              unseen == 1 ? '1 new thought' : '$unseen new thoughts',
              style: const TextStyle(
                color: _ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Close or Friends: which ring you stand on. A dot marks a ring with
/// thoughts you have not seen.
class _RingSwitch extends StatelessWidget {
  final int active;
  final ValueChanged<int> onPick;

  const _RingSwitch({required this.active, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xCC15171C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _chat.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _layerCount; i++)
              Semantics(
                button: true,
                selected: i == active,
                label: '${_ringNames[i]} ring',
                excludeSemantics: true,
                child: GestureDetector(
                  key: ValueKey('ring-${_ringNames[i].toLowerCase()}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    constraints: const BoxConstraints(minHeight: 34),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == active
                          ? const Color(0x331DB954)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _ringNames[i],
                          style: TextStyle(
                            color: i == active ? _ink : _muted,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_friends.any((f) => f.layer == i && _isNew(f))) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: _accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
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

  /// Cosine and sine of this layer's own tilt.
  final double c;
  final double s;

  const _LayerView(
    this.layer,
    this.rel,
    this.scale,
    this.cy,
    this.opacity,
    this.c,
    this.s,
  );
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

  /// 1 while a finger is turning the orbit (see the screen's `_duck`).
  final double duck;

  /// 1 when fingers spread to see everyone's thought at once: a bubble over
  /// every friend, and no card.
  final double overview;

  /// The flat orbit opens with faces only; spreading two fingers on it
  /// brings a bubble over every face (1).
  final double flatZoom;

  /// The ring you just shared a thought to glows once: how much, and which.
  final double glow;
  final int glowLayer;
  final Size size;

  /// On the dial, the orbit rolls a little with the finger turning it.
  final double lean;

  /// The waiting ring's label was tapped: go to that ring.
  final ValueChanged<int>? onRing;

  /// On the dial, where the orbit rests: 0 at the top, 1 at the bottom.
  final double dock;

  /// The front card was tapped: open the thought.
  final ValueChanged<_ProtoFriend> onCardTap;

  /// A face was tapped; null is you.
  final ValueChanged<_ProtoFriend?> onFace;

  /// The + on your photo: share a thought.
  final VoidCallback onShare;

  /// A face was held: what you can do with that friend.
  final ValueChanged<_ProtoFriend> onHold;

  const _OrbitStage({
    required this.t,
    required this.camera,
    required this.rotation,
    required this.floatPhase,
    required this.duck,
    required this.overview,
    required this.flatZoom,
    required this.glow,
    required this.glowLayer,
    required this.size,
    this.lean = 0,
    this.onRing,
    this.dock = 0,
    required this.onCardTap,
    required this.onFace,
    required this.onShare,
    required this.onHold,
  });

  @override
  Widget build(BuildContext context) {
    final k = math.min(size.width / 390, size.height / 640);
    final cx = size.width / 2;
    final tc = t.clamp(0.0, 1.0);
    // Flat, the orbit sits in the middle of the screen. Tilting lifts it, so
    // the front friend's card gets the lower part of the screen, while the far
    // orbit stays visible just under the layer meter.
    // Zoomed out there is no card, so the orbit drops into the space it
    // used, leaving room for a bubble over every friend.
    final cy =
        size.height *
        (_lerp(
              OrbitDepthTuning.flatOrbitHeight,
              OrbitDepthTuning.dial
                  ? _lerp(
                      OrbitDepthTuning.dialTopHeight,
                      OrbitDepthTuning.dialBottomHeight,
                      dock,
                    )
                  : OrbitDepthTuning.orbitHeight,
              tc,
            ) +
            (OrbitDepthTuning.dial ? 0 : 0.2 * overview * tc));
    final farCy = OrbitDepthTuning.farOrbitY * k;
    final tilt =
        t.clamp(-0.05, 1.0) * OrbitDepthTuning.tiltDegrees * math.pi / 180;
    final c = math.cos(tilt);
    final ringBase =
        k *
        _lerp(OrbitDepthTuning.flatRingRadius, OrbitDepthTuning.ringRadius, tc);

    final layers = <int, _LayerView>{};
    for (var layer = 0; layer < _layerCount; layer++) {
      final rel = layer - camera;
      // Only the orbit you are on and the next one, far away. The one after
      // that stays hidden until you start flying towards it.
      if (rel < -0.75 || rel > 1.3) continue;
      // With the far orbit switched off, the next one appears only once you
      // start flying towards it.
      if (!OrbitDepthTuning.dial &&
          !OrbitDepthTuning.showFarOrbit &&
          rel > 0.3) {
        continue;
      }
      if (OrbitDepthTuning.dial) {
        final away = Curves.easeInOut.transform(rel.abs().clamp(0.0, 1.0));
        // The ring you left fades out; the next one out stays, faint.
        var opacity = rel >= 0
            ? _lerp(1, _peekAlpha, away) * (rel > 1 ? 0 : 1)
            : 1 - rel.abs().clamp(0.0, 1.0);
        if (opacity <= 0.01) continue;
        final dialTilt = t.clamp(-0.05, 1.0) *
            OrbitDepthTuning.tiltDegrees *
            math.pi /
            180;
        layers[layer] = _LayerView(
          layer,
          rel,
          // Friends sit on a slightly wider orbit than Close.
          (layer > 0 ? 1.12 : 1) *
              (rel >= 0 ? _lerp(1, 1.45, away) : _lerp(1, 0.35, away)),
          cy,
          opacity,
          math.cos(dialTilt),
          math.sin(dialTilt),
        );
        continue;
      }
      final scale = rel >= 0
          ? math.pow(OrbitDepthTuning.farOrbitSize, rel).toDouble()
          : 1 + (-rel) * 1.8;
      final layerCy = rel >= 0
          ? cy - rel * (cy - farCy)
          : cy + (-rel) * 320 * k;
      final bright = OrbitDepthTuning.farOrbitBrightness;
      var opacity = rel >= 0
          ? (rel <= 1
                ? 1 - (1 - bright) * rel
                : math.max(0.0, bright * (1.3 - rel) / 0.3))
          : math.max(0.0, 1 + rel * 1.5);
      // The flat orbit is Close alone; Friends shows once tilted.
      if (layer > 0) opacity *= tc;
      if (opacity <= 0.01) continue;
      // Each layer has its own tilt, blending from yours to the far one's as
      // it comes towards you.
      final farTilt =
          OrbitDepthTuning.farOrbitTilt ?? OrbitDepthTuning.tiltDegrees;
      final layerTilt =
          t.clamp(-0.05, 1.0) *
          _lerp(OrbitDepthTuning.tiltDegrees, farTilt, rel.clamp(0.0, 1.0)) *
          math.pi /
          180;
      layers[layer] = _LayerView(
        layer,
        rel,
        scale,
        layerCy,
        opacity,
        math.cos(layerTilt),
        math.sin(layerTilt),
      );
    }

    // Over the flat orbit, Close friends a bubble would cover slide a little
    // along the ring until they are clear; the slide fades out as the orbit
    // tilts.
    final flatWeight = OrbitDepthTuning.bubblesWhenFlat
        ? (1 - _interval(tc, 0.05, 0.45)) * flatZoom
        : 0.0;
    final home = layers[0];
    final shifts = flatWeight > 0 && home != null
        ? _flatShifts(k, cx, home.cy, ringBase, c, tc)
        : const <int, double>{};

    final seats = <_Seat>[];
    for (var i = 0; i < _friends.length; i++) {
      final f = _friends[i];
      final lv = layers[f.layer];
      if (lv == null) continue;
      // Flat, the waiting ring is a line and a name: its faces come in only
      // as the orbit tilts.
      if (OrbitDepthTuning.dial && f.layer > 0 && tc <= 0.01) continue;
      final radius = ringBase * lv.scale;
      final base =
          _lerp(
            OrbitDepthTuning.flatAvatarSize,
            OrbitDepthTuning.avatarSize,
            tc,
          ) *
          k *
          lv.scale *
          // Many more Friends than Close: smaller faces, so they fit.
          (OrbitDepthTuning.dial && f.layer > 0 ? 0.68 : 1);
      final theta =
          f.angleDeg * math.pi / 180 + rotation + (shifts[i] ?? 0) * flatWeight;
      final d = math.sin(theta);
      // On the dial every face goes through one camera, so where it sits
      // and how big it is agree.
      final (projected, near) = OrbitDepthTuning.dial
          ? _dialProject(theta, radius, lv.c, lv.s, lean)
          : (
              Offset(
                radius * math.cos(theta),
                radius * math.sin(theta) * lv.c,
              ),
              _depthScale(d, lv.s),
            );
      final ring = Offset(cx, lv.cy) + projected;
      // Seen friends step back: a little smaller and dimmer.
      final quiet = f.more == 0 && !_isNew(f);
      final avatarSize = base * near * (quiet ? 0.84 : 1);
      final float = math.sin(floatPhase + i * 0.9) * 2.5 * k * tc * lv.scale;
      final lift = OrbitDepthTuning.dial
          ? 0.0
          : (avatarSize / 2 + OrbitDepthTuning.avatarHover * k * lv.scale) *
                tc;
      final platform = OrbitDepthTuning.platformSize;
      final pedW = _lerp(avatarSize * 0.9, avatarSize * platform, tc);
      final pedH = _lerp(
        avatarSize * 0.9,
        math.max(
          4 * k * lv.scale,
          avatarSize *
              platform *
              math.min(1.0, lv.c * OrbitDepthTuning.platformFlatness),
        ),
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
          opacity:
              (1 - OrbitDepthTuning.backDim * ((1 - d) / 2) * lv.s).clamp(
                0.0,
                1.0,
              ) *
              lv.opacity *
              (quiet ? 0.72 : 1) *
              (OrbitDepthTuning.dial
                  ? _peekShow(lv.rel * tc, d) * (f.layer > 0 ? tc : 1)
                  : 1),
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

    final youSize =
        _lerp(OrbitDepthTuning.flatYouSize, OrbitDepthTuning.youSize, tc) *
        k *
        (OrbitDepthTuning.dial ? 1 : home?.scale ?? 1);
    // On the dial you stay in the middle whichever ring you are on.
    final youOnDial = OrbitDepthTuning.dial && home == null && tc > 0;
    final youRing = Offset(cx, home?.cy ?? cy);
    // On the dial you sit at the true centre of the orbit, in its plane.
    final youCenter = OrbitDepthTuning.dial
        ? youRing
        : youRing.translate(
            0,
            -(youSize / 2 + OrbitDepthTuning.youHover * k) * tc,
          );
    final youPedestal = Size(
      _lerp(youSize * 0.9, youSize * OrbitDepthTuning.youPlatformSize, tc),
      _lerp(
        youSize * 0.9,
        math.max(
          4 * k,
          youSize *
              OrbitDepthTuning.youPlatformSize *
              math.min(1.0, c * OrbitDepthTuning.platformFlatness),
        ),
        tc,
      ),
    );

    // The front friend's card (and the beam to it) when they shared a thought.
    final cardFocus = OrbitDepthTuning.showCard
        ? (spotlight?.friend.thought == null ? 0.0 : highlight) *
              (OrbitDepthTuning.dial
                  ? _smoothstep(0.3, 1, (2 * dock - 1).abs())
                  : 1 - duck) *
              (1 - overview)
        : 0.0;
    // On the dial an open card is the focus: the orbit steps back, all but
    // the friend whose card it is.
    final dim = OrbitDepthTuning.dial ? 0.5 * cardFocus : 0.0;
    // Thought bubbles over the flat orbit tuck under the faces, so a face is
    // never covered; the card and the dots stay on top.
    final underFaces = <Widget>[];
    // On the dial, the next ring out names itself on its far edge, with a
    // dot when someone out there has a new thought.
    final waiting = OrbitDepthTuning.dial
        ? layers.values.where((l) => l.rel > 0.01 && l.rel <= 1).firstOrNull
        : null;
    Widget? peekLabel;
    double? peekTop;
    if (waiting != null) {
      final show = _interval(waiting.rel, 0.5, 1);
      final radius = ringBase * waiting.scale;
      final (back, near) = _dialProject(
        -math.pi / 2,
        radius,
        waiting.c,
        waiting.s,
        lean,
      );
      final edge = Offset(cx, waiting.cy) + back;
      // Never above the top of the screen: high up, the orbit runs into it.
      final top = math.max(
        2 * k,
        edge.dy -
            OrbitDepthTuning.avatarSize * k * waiting.scale * near * 0.68 / 2 -
            26 * k,
      );
      peekTop = top;
      final layer = waiting.layer;
      final people = _friends
          .where((f) => f.layer == layer)
          .fold<int>(0, (n, f) => n + (f.more > 0 ? f.more : 1));
      final fresh = _friends.any((f) => f.layer == layer && _isNew(f));
      if (show > 0.01) {
        peekLabel = Positioned(
          left: 0,
          right: 0,
          top: top,
          child: Center(
            child: Opacity(
              opacity: show,
              child: Semantics(
                button: true,
                label: '${_ringNames[layer]}, $people people',
                excludeSemantics: true,
                child: GestureDetector(
                  key: ValueKey('peek-ring-$layer'),
                  behavior: HitTestBehavior.opaque,
                  onTap: show > 0.6 ? () => onRing?.call(layer) : null,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12 * k,
                      vertical: 4 * k,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_ringNames[layer]} · $people',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12 * k,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (fresh) ...[
                          SizedBox(width: 6 * k),
                          Container(
                            key: ValueKey('peek-new-$layer'),
                            width: 7 * k,
                            height: 7 * k,
                            decoration: const BoxDecoration(
                              color: _accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    // On the dial the card ends above the orbit's back edge, and above the
    // waiting ring's label.
    final cardLimit = OrbitDepthTuning.dial
        ? _lerp(
            size.height - 40 * k,
            math.min(
              (home?.cy ?? cy) -
                  ringBase * c -
                  OrbitDepthTuning.avatarSize * k -
                  20 * k,
              (peekTop ?? double.infinity) - 6 * k,
            ),
            dock,
          )
        : null;
    final overFaces = _bubbles(
      seats,
      k,
      tc,
      spotlight,
      cardFocus,
      underFaces,
      cardLimit: cardLimit,
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
            youRing: home == null && !youOnDial ? null : youRing,
            youPedestal: youPedestal,
            youOpacity: home?.opacity ?? 0,
            youSize: youSize,
            spotlight: spotlight,
            highlight: highlight,
            floatPhase: floatPhase,
            glow: glow,
            glowLayer: glowLayer,
            lean: lean,
            dim: dim,
          ),
        ),
      ),
    ];

    children.addAll(underFaces);

    var youPlaced = home == null && !youOnDial;
    final youOpacity = OrbitDepthTuning.dial ? 1.0 : home?.opacity ?? 0;
    void placeYou() {
      children.add(
        _positionedCircle(
          center: youCenter,
          size: youSize,
          child: IgnorePointer(
            ignoring: !OrbitDepthTuning.dial && home!.rel.abs() > 0.35,
            child: Opacity(
              opacity: youOpacity * (1 - dim * 0.6),
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  Semantics(
                    button: true,
                    label: 'You',
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: const ValueKey('you-avatar'),
                      onTap: () => onFace(null),
                      // You lean with the orbit as it turns.
                      child: Transform.rotate(
                        angle: OrbitDepthTuning.dial ? lean : 0,
                        child: _YouAvatar(size: youSize, t: tc),
                      ),
                    ),
                  ),
                  // You are where thoughts are shared from.
                  Positioned(
                    right: -youSize * 0.06,
                    bottom: -youSize * 0.02,
                    child: Semantics(
                      button: true,
                      label: 'Share a thought',
                      excludeSemantics: true,
                      child: GestureDetector(
                        key: const ValueKey('share-thought'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onShare,
                        child: _PlusMark(
                          size: math.max(
                            20,
                            youSize * (OrbitDepthTuning.dial ? 0.34 : 0.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      youPlaced = true;
    }

    for (final seat in seats) {
      if (!youPlaced &&
          (seat.layer.layer == 0 || youOnDial) &&
          seat.ringPoint.dy > youRing.dy) {
        placeYou();
      }
      children.add(
        _positionedCircle(
          center: seat.avatarCenter,
          size: seat.size,
          child: IgnorePointer(
            ignoring: !seat.interactive,
            child: Opacity(
              opacity: identical(seat, spotlight) ? 1 : 1 - dim,
              child: seat.friend.more > 0
                ? _MoreAvatar(
                    key: const ValueKey('avatar-more'),
                    seat: seat,
                    highlight: identical(seat, spotlight) ? highlight : 0,
                    onTap: () => onFace(seat.friend),
                  )
                : _FriendAvatar(
                    key: ValueKey('avatar-${seat.friend.name}'),
                    seat: seat,
                    highlight: identical(seat, spotlight) ? highlight : 0,
                    onTap: () => onFace(seat.friend),
                    onLongPress: () => onHold(seat.friend),
                  ),
            ),
          ),
        ),
      );
    }
    if (!youPlaced) placeYou();

    // The beam from the front friend to their card.
    final beamSeat = OrbitDepthTuning.dial ? null : spotlight;
    if (beamSeat != null && cardFocus > 0.01) {
      final card = _cardRect(beamSeat, cardFocus, k, tc);
      final platform = beamSeat.pedestal;
      children.add(
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _BeamPainter(
                from: Rect.fromCenter(
                  center: beamSeat.ringPoint,
                  width: platform.width * 0.8,
                  height: platform.height,
                ),
                to: card,
                color: beamSeat.friend.hue.color,
                strength:
                    cardFocus *
                    beamSeat.opacity *
                    OrbitDepthTuning.beamStrength *
                    (OrbitDepthTuning.showBeam ? 1 : 0),
                k: k,
              ),
            ),
          ),
        ),
      );
    }

    final named = OrbitDepthTuning.dial ? null : spotlight;
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
                named.friend.more > 0 ? 'Everyone' : named.friend.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _ink,
                  fontSize: OrbitDepthTuning.frontNameSize * k * scale,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (peekLabel != null) children.add(peekLabel);
    children.addAll(overFaces);

    return Stack(clipBehavior: Clip.none, children: children);
  }

  /// How far (radians) each friend on the flat orbit slides along the ring so
  /// that no one else's thought bubble covers their face: a few degrees at a
  /// time, never more than [_maxShift], and never into a neighbour.
  Map<int, double> _flatShifts(
    double k,
    double cx,
    double cy,
    double ringBase,
    double squash,
    double tc,
  ) {
    const step = 2.5 * math.pi / 180;
    final ids = [
      for (var i = 0; i < _friends.length; i++)
        if (_friends[i].layer == 0) i,
    ];
    if (ids.isEmpty) return const {};
    final avatar =
        _lerp(OrbitDepthTuning.flatAvatarSize, OrbitDepthTuning.avatarSize, tc) *
        k;
    final base = {
      for (final i in ids)
        i: _friends[i].angleDeg * math.pi / 180 + rotation,
    };
    final shift = {for (final i in ids) i: 0.0};
    // Two faces may not come closer than this along the ring.
    final minGap = 2 * math.asin(((avatar + 6 * k) / (2 * ringBase)).clamp(0, 1));

    Offset at(double theta) => Offset(
      cx + ringBase * math.cos(theta),
      cy + ringBase * math.sin(theta) * squash,
    );

    for (var pass = 0; pass < 14; pass++) {
      final rects = <int, Rect>{
        for (final i in ids)
          if (_friends[i].thought != null)
            i: _flatBubbleRect(
              at(base[i]! + shift[i]!),
              avatar,
              _friends[i].thought!,
              math.sin(base[i]! + shift[i]!),
              k,
            ),
      };
      var moved = false;
      for (final j in ids) {
        final theta = base[j]! + shift[j]!;
        final face = at(theta);
        final reach = avatar / 2 + 3 * k;
        for (final entry in rects.entries) {
          if (entry.key == j) continue;
          final r = entry.value;
          final nearest = Offset(
            face.dx.clamp(r.left, r.right),
            face.dy.clamp(r.top, r.bottom),
          );
          if ((face - nearest).distance >= reach) continue;
          // Slide along the ring, away from the bubble.
          final tangent = Offset(-math.sin(theta), math.cos(theta));
          final away = face - r.center;
          final dir = away.dx * tangent.dx + away.dy * tangent.dy >= 0 ? 1 : -1;
          final next = shift[j]! + dir * step;
          if (next.abs() > _maxShift) break;
          final crowded = ids.any((o) {
            if (o == j) return false;
            var gap = (base[j]! + next - base[o]! - shift[o]!).abs() %
                (2 * math.pi);
            if (gap > math.pi) gap = 2 * math.pi - gap;
            return gap < minGap;
          });
          if (crowded) break;
          shift[j] = next;
          moved = true;
          break;
        }
      }
      if (!moved) break;
    }
    return shift;
  }

  /// Where a flat orbit's thought bubble lands for a face at [ring]: just
  /// above it (as [_bubbles] does).
  Rect _flatBubbleRect(
    Offset ring,
    double avatar,
    String text,
    double depth,
    double k,
  ) {
    final notes = OrbitDepthTuning.bubbleStyle == OrbitBubbleStyle.notes;
    final font = OrbitDepthTuning.bubbleTextSize * k;
    final width = OrbitDepthTuning.bubbleWidth * k;
    final boxWidth = notes ? width * _notesWidth : width;
    // Erring tall: anything beyond a short phrase is taken to fill both lines.
    final lines = text.length > 14 ? _notesLines : 1;
    final boxHeight = notes
        ? lines * font * 1.25 + 16 * k + 14 * k
        : (text.length > 16 ? 42 : 27) * k;
    final left = (ring.dx - boxWidth / 2)
        .clamp(6 * k, math.max(6 * k, size.width - boxWidth - 6 * k))
        .toDouble();
    final bottom = ring.dy - avatar / 2 - (notes ? 0 : 6) * k;
    return Rect.fromLTWH(left, bottom - boxHeight, boxWidth, boxHeight);
  }

  /// Where things under an avatar start: just below the front edge of its
  /// platform once tilted (the disc plus its edge), under the avatar when flat.
  /// Where the front friend's card sits: below their name, far enough down
  /// to leave room for the beam that joins them. Height is left at zero.
  Rect _cardRect(_Seat seat, double focus, double k, double tc) {
    if (OrbitDepthTuning.dial) {
      // Below the orbit at the top; under the header's buttons when the
      // orbit is at the bottom.
      final top = _lerp(
        seat.avatarCenter.dy +
            seat.size / 2 * (1 + OrbitDepthTuning.frontFriendLift) +
            18 * k,
        60 * k,
        dock,
      );
      return Rect.fromLTWH(14 * k, top, size.width - 28 * k, 0);
    }
    final scale = seat.layer.scale;
    final top =
        _nameTop(seat, k, tc) +
        (16 + OrbitDepthTuning.cardGap * focus) * k * scale;
    final width = _lerp(
      100 * k * scale,
      (size.width - 28 * k) * OrbitDepthTuning.cardWidth,
      focus,
    );
    final left = (seat.ringPoint.dx - width / 2)
        .clamp(12 * k, math.max(12 * k, size.width - width - 12 * k))
        .toDouble();
    return Rect.fromLTWH(left, top, width, 0);
  }

  /// Below the platform, and always below the avatar itself, which can sit
  /// low on its ring point when the hover is negative.
  double _nameTop(_Seat seat, double k, double tc) => math.max(
    seat.ringPoint.dy +
        _lerp(
          seat.size / 2,
          seat.pedestal.height * 0.55 + 4 * k * seat.layer.scale,
          tc,
        ),
    seat.avatarCenter.dy + seat.size / 2 + 4 * k * seat.layer.scale,
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
    double cardFocus,
    List<Widget> underFaces, {
    double? cardLimit,
  }) {
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
    final focus = cardFocus;
    final tiltSin = math.sin(tc * OrbitDepthTuning.tiltDegrees * math.pi / 180);
    final notes = OrbitDepthTuning.bubbleStyle == OrbitBubbleStyle.notes;
    // Bubbles belong to the flat orbit; once tilted, thoughts become dots
    // (unless the depth bubbles are switched back on).
    final depthBubbles =
        OrbitDepthTuning.thoughtsInDepth == OrbitDepthThoughts.bubbles;
    final flatBubbles = OrbitDepthTuning.bubblesWhenFlat
        ? (1 - _interval(tc, 0.05, 0.45)) * flatZoom
        : 0.0;
    final bubbleAlpha = OrbitDepthTuning.showBubbles
        ? math.min(1.0, flatBubbles + (depthBubbles ? appear : appear * overview))
        : 0.0;
    // Faces only on the flat orbit until pinched: a dot marks a new thought.
    final flatDots = (1 - _interval(tc, 0.05, 0.45)) * (1 - flatZoom);
    final dotAlpha = depthBubbles
        ? 0.0
        : math.max(appear * (1 - overview), flatDots);
    for (final seat in candidates) {
      final scale = seat.layer.scale;
      final isSpotlight = identical(seat, spotlight) && focus > 0.01;
      final near = (1 - seat.layer.rel.abs() * 2.5).clamp(0.0, 1.0);
      final cardAlpha = appear * near;
      if (isSpotlight) {
        final card = _cardRect(seat, focus, k, tc);
        // Leave the bottom of the screen to the reply dock.
        final maxHeight = math.max(
          0.0,
          (cardLimit ?? size.height - 8 * k - _dockInset * k) - card.top,
        );
        widgets.add(
          Positioned(
            key: ValueKey('card-${seat.friend.name}'),
            left: card.left,
            top: card.top,
            width: card.width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: _PostStack(
                  friend: seat.friend,
                  maxHeight: maxHeight,
                  expand: focus,
                  k: k * scale * OrbitDepthTuning.cardScale,
                  alpha: cardAlpha,
                  onOpen: () => onCardTap(seat.friend),
                  onWorld: () => onFace(seat.friend),
                ),
              ),
            ),
          ),
        );
        continue;
      }

      // A dot on the avatar says this friend has a thought you have not
      // seen.
      if (dotAlpha * near > 0.01 && _isNew(seat.friend)) {
        final dot = (seat.size * 0.22).clamp(6 * k, 12 * k);
        widgets.add(
          Positioned(
            key: ValueKey('thought-dot-${seat.friend.name}'),
            left: seat.avatarCenter.dx + seat.size * 0.5 - dot * 0.9,
            top: seat.avatarCenter.dy - seat.size * 0.5 + dot * 0.1,
            width: dot,
            height: dot,
            child: IgnorePointer(
              child: Opacity(
                opacity: (dotAlpha * near * seat.opacity).clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _isNew(seat.friend)
                        ? _accent
                        : const Color(0xFF9AA59F),
                    shape: BoxShape.circle,
                    border: Border.all(color: _ground, width: 2),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      var depthGrowth = _lerp(
        math.min(
          1 + OrbitDepthTuning.bubbleDepth * seat.depth * tiltSin,
          OrbitDepthTuning.maxBubbleSize,
        ),
        1,
        overview,
      );
      // Over the flat orbit, and when zoomed out, every bubble sits just
      // above its friend.
      var below = depthBubbles
          ? _smoothstep(-0.05, 0.3, seat.depth) * (1 - overview)
          : 0.0;
      var fade = bubbleAlpha * near;
      final avatarTop = seat.avatarCenter.dy - seat.size / 2;

      // The friends either side of an open card.
      if (!isSpotlight && focus > 0.01 && seat.depth > 0.3) {
        switch (OrbitDepthTuning.frontNeighbourBubbles) {
          case OrbitNeighbourBubbles.auto:
            break;
          case OrbitNeighbourBubbles.above:
            below *= 1 - focus;
          case OrbitNeighbourBubbles.small:
            depthGrowth = math.min(
              depthGrowth,
              _lerp(depthGrowth, 0.75, focus),
            );
          case OrbitNeighbourBubbles.hide:
            fade *= 1 - focus;
          case OrbitNeighbourBubbles.dot:
            fade *= 1 - focus;
            final dot = 9 * k * scale;
            widgets.add(
              Positioned(
                left: seat.avatarCenter.dx + seat.size * 0.32,
                top: avatarTop,
                width: dot,
                height: dot,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (focus * appear).clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _isNew(seat.friend)
                            ? _accent
                            : const Color(0xFF6B7A72),
                        shape: BoxShape.circle,
                        border: Border.all(color: _ground, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
            );
        }
      }
      if (fade <= 0.01) continue;
      final bubbleScale = scale * depthGrowth;
      final text = seat.friend.thought!;
      final font = OrbitDepthTuning.bubbleTextSize * k * bubbleScale;
      final width = OrbitDepthTuning.bubbleWidth * k * bubbleScale;
      // Notes bubbles are wider (so most thoughts fit on one or two lines) and
      // carry a tail of two dots; estimate their height for stacking.
      final boxWidth = notes ? width * _notesWidth : width;
      final tail = notes ? 14 * k * bubbleScale : 0.0;
      final lines = notes
          ? ((text.length * font * 0.55) / (boxWidth - 26 * k * bubbleScale))
                .ceil()
                .clamp(1, _notesLines)
          : 0;
      final boxHeight = notes
          ? lines * font * 1.25 + 16 * k * bubbleScale + tail
          : (text.length > 16 ? 42 : 27) * k * bubbleScale;
      final left = (seat.ringPoint.dx - boxWidth / 2)
          .clamp(6 * k, math.max(6 * k, size.width - boxWidth - 6 * k))
          .toDouble();
      final aboveBottom = notes ? avatarTop : avatarTop - 6 * k * scale;
      final gap = 4 * k * bubbleScale;

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
            name: seat.friend.name,
            text: text,
            fresh: _isNew(seat.friend),
            hue: seat.friend.hue.color,
            k: k * bubbleScale,
            appear: alpha,
            growFromTop: growFromTop,
            onTap: () => onCardTap(seat.friend),
          );

      if (1 - below > 0.01) {
        final rect = nudge(
          Rect.fromLTWH(left, aboveBottom - boxHeight, boxWidth, boxHeight),
          takenAbove,
          down: false,
        );
        (tc < 0.5 ? underFaces : widgets).add(
          Positioned(
            left: left,
            bottom: size.height - rect.bottom,
            width: boxWidth,
            child: bubble(fade * (1 - below), growFromTop: false),
          ),
        );
      }
      if (below > 0.01) {
        final rect = nudge(
          Rect.fromLTWH(
            left,
            _nameTop(seat, k, tc) + 4 * k * scale,
            boxWidth,
            boxHeight,
          ),
          takenBelow,
          down: true,
        );
        (tc < 0.5 ? underFaces : widgets).add(
          Positioned(
            left: left,
            top: rect.top,
            width: boxWidth,
            child: bubble(fade * below, growFromTop: true),
          ),
        );
      }
    }
    return widgets;
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
  final VoidCallback onLongPress;

  const _FriendAvatar({
    super.key,
    required this.seat,
    required this.highlight,
    required this.onTap,
    required this.onLongPress,
  });

  String get _label {
    final f = seat.friend;
    return [f.name, if (f.thought != null) f.thought!].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final f = seat.friend;
    final peerId = _ringAvatarPeers[f.name];
    if (peerId != null) return _ringAvatar(peerId);
    final radius = BorderRadius.circular(seat.size / 2);
    return Semantics(
      button: true,
      label: _label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Opacity(
          opacity: seat.opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1 + OrbitDepthTuning.frontFriendLift * highlight,
            alignment: Alignment.bottomCenter,
            child: _Sheen(
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
                child: ClipOval(
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
    );
  }
}

extension on _FriendAvatar {
  /// The main app's default avatar, drawn the way `UserAvatar` draws it for a
  /// contact without a photo: the generated rings plus a soft glow in the
  /// person's hue, no photo frame.
  Widget _ringAvatar(String peerId) {
    final glow = RingAvatarGenerator.glowColorForPeerId(peerId);
    return Semantics(
      button: true,
      label: _label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Opacity(
          opacity: seat.opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1 + OrbitDepthTuning.frontFriendLift * highlight,
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: glow.withValues(alpha: 0.35 + 0.2 * highlight),
                    blurRadius: seat.size * 0.35,
                    spreadRadius: seat.size * 0.05,
                  ),
                ],
              ),
              child: RingAvatar(peerId: peerId, size: seat.size),
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

  const _Sheen({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
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
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
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
          boxShadow: [
            // On the dial a faint rim, not a halo: you are part of the scene.
            BoxShadow(
              color: _accent.withValues(
                alpha: OrbitDepthTuning.dial ? 0.45 : _lerp(0.12, 0.32, t),
              ),
              blurRadius: OrbitDepthTuning.dial ? 5 : _lerp(12, 36, t),
              spreadRadius: OrbitDepthTuning.dial ? 1 : _lerp(1, 8, t),
            ),
          ],
        ),
        child: Semantics(
          label: 'You',
          child: Padding(
            padding: EdgeInsets.zero,
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

/// The last slot on the Friends ring: everyone without a slot of their own.
/// Opens them all as a list.
class _MoreAvatar extends StatelessWidget {
  final _Seat seat;
  final double highlight;
  final VoidCallback onTap;

  const _MoreAvatar({
    super.key,
    required this.seat,
    required this.highlight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = seat.size;
    return Semantics(
      button: true,
      label: '${seat.friend.more} more friends',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: seat.opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1 + OrbitDepthTuning.frontFriendLift * highlight,
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF15181B),
                border: Border.all(color: const Color(0xFF3A4741)),
              ),
              child: Center(
                child: Text(
                  '+${seat.friend.more}',
                  style: TextStyle(
                    color: _ink,
                    fontSize: size * 0.3,
                    fontWeight: FontWeight.w700,
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

/// The small plus on your own photo: tap to share a thought.
class _PlusMark extends StatelessWidget {
  final double size;

  const _PlusMark({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: _accent,
      shape: BoxShape.circle,
      border: Border.all(color: _ground, width: size * 0.12),
    ),
    child: Icon(Icons.add, size: size * 0.66, color: const Color(0xFF03140A)),
  );
}

class _ThoughtBubble extends StatelessWidget {
  final String name;
  final String text;

  /// New since you last opened this friend's thread.
  final bool fresh;

  /// The friend's colour, for the Notes tint.
  final Color hue;
  final double k;
  final double appear;
  final bool growFromTop;
  final VoidCallback onTap;

  const _ThoughtBubble({
    required this.name,
    required this.text,
    required this.fresh,
    required this.hue,
    required this.k,
    required this.appear,
    required this.growFromTop,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = 0.6 + 0.4 * Curves.easeOutBack.transform(appear);
    final notes = OrbitDepthTuning.bubbleStyle == OrbitBubbleStyle.notes;
    return Opacity(
      opacity: appear.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        alignment: growFromTop ? Alignment.topCenter : Alignment.bottomCenter,
        child: GestureDetector(
          onTap: onTap,
          child: notes ? _notes() : _classic(),
        ),
      ),
    );
  }

  Widget _classic() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9 * k, vertical: 6 * k),
      decoration: BoxDecoration(
        color: _chat.surfaceRaised,
        borderRadius: BorderRadius.circular(14 * k),
        border: Border.all(color: _chat.border, width: 1),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _chat.textPrimary,
          fontSize: OrbitDepthTuning.bubbleTextSize * k,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
      ),
    );
  }

  /// Like Instagram Notes: hugs its text, soft tinted fill, and a tail of two
  /// little dots pointing at the friend (down above them, up below them).
  /// Like Instagram Notes: a soft solid bubble (the chat bubble's colour, no
  /// outline) with a thought tail of two dots trailing diagonally towards the
  /// friend: a bigger one touching the bubble, a smaller one beyond it.
  Widget _notes() {
    final fill = Color.lerp(
      const Color(0xFF181A20),
      hue,
      OrbitDepthTuning.bubbleTint,
    )!;
    final shadow = BoxShadow(
      color: const Color(0x66000000),
      blurRadius: 14 * k,
      offset: Offset(0, 5 * k),
    );
    Widget dot(double d, double dx) => Transform.translate(
      offset: Offset(dx * k, 0),
      child: Container(
        width: d * k,
        height: d * k,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          boxShadow: [shadow],
        ),
      ),
    );
    final bubble = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12 * k, vertical: 8 * k),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16 * k),
            boxShadow: [shadow],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: _notesLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _chat.textPrimary,
              fontSize: OrbitDepthTuning.bubbleTextSize * k,
              fontWeight: FontWeight.w600,
              height: 1.25,
              letterSpacing: 0.1,
            ),
          ),
        ),
        if (fresh && OrbitDepthTuning.unreadDot)
          Positioned(
            key: ValueKey('new-thought-$name'),
            top: -2 * k,
            right: -2 * k,
            child: Container(
              width: 10 * k,
              height: 10 * k,
              decoration: BoxDecoration(
                color: _accent,
                shape: BoxShape.circle,
                border: Border.all(color: _ground, width: 2 * k),
              ),
            ),
          ),
      ],
    );
    // The tail runs from the bubble down and to the left, like a thought.
    // A short tail of two small dots, so the bubble sits just over the head.
    final tail = <Widget>[
      SizedBox(height: 1 * k),
      dot(7, 3),
      SizedBox(height: 1 * k),
      dot(4.5, 8),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: growFromTop ? [...tail.reversed, bubble] : [bubble, ...tail],
    );
  }
}

/// The spotlight thought: a compact bubble at [expand] 0 that grows into a
/// card with the name, the full text, a photo or a voice note, and comments.
class _ThoughtCard extends StatefulWidget {
  final _ProtoFriend friend;

  /// The room left below the orbit; the photo shrinks to fit inside it.
  final double maxHeight;
  final double expand;
  final double k;
  final double alpha;
  final VoidCallback onOpen;

  /// Dives into the friend's world, where this thought is kept.
  final VoidCallback onWorld;

  /// One of the friend's older posts; null shows the live thought.
  final _PastThought? post;

  const _ThoughtCard({
    super.key,
    this.post,
    required this.friend,
    required this.maxHeight,
    required this.expand,
    required this.k,
    required this.alpha,
    required this.onOpen,
    required this.onWorld,
  });

  @override
  State<_ThoughtCard> createState() => _ThoughtCardState();
}

class _ThoughtCardState extends State<_ThoughtCard> {
  _PastThought get _detail =>
      widget.post ?? _thoughtsOf(widget.friend.name).first;

  @override
  Widget build(BuildContext context) {
    final e = widget.expand;
    final k = widget.k;
    final extra = _interval(e, 0.45, 1);

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
            color: _chat.surfaceRaised,
            borderRadius: BorderRadius.circular(_lerp(14, 20, e) * k),
            border: Border.all(color: _chat.border, width: 1),
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
                _detail.text,
                textAlign: TextAlign.center,
                maxLines: e < 0.5 ? 2 : 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _chat.textPrimary,
                  fontSize: _lerp(11.5, 16.5, e) * k,
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
                color: _chatSecondary,
                fontSize: 14 * k,
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
                // Everything else on the card takes about 150pt; the photo
                // gets the rest, up to 168pt, so the card never runs off
                // the bottom of the screen.
                height: (widget.maxHeight - 150 * k).clamp(
                  72 * k,
                  math.max(
                    72 * k,
                    OrbitDepthTuning.maxPhotoHeight *
                        k /
                        OrbitDepthTuning.cardScale,
                  ),
                ),
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
            child: _VoicePlayer(
              seconds: _detail.seconds,
              k: k,
              active: widget.expand >= 0.5,
            ),
          ),
        if (detail.space != null)
          Padding(
            padding: EdgeInsets.only(top: 10 * k),
            child: Center(
              child: GestureDetector(
                onTap: () =>
                    _openSpace(context, widget.friend.name, detail.space!),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10 * k,
                    vertical: 5 * k,
                  ),
                  decoration: BoxDecoration(
                    color: _chat.surfaceSubtle,
                    borderRadius: BorderRadius.circular(10 * k),
                  ),
                  child: Text(
                    'from ${detail.space}  ›',
                    style: TextStyle(
                      color: _chatSecondary,
                      fontSize: 12.5 * k,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: 10 * k),
          child: Row(
            children: [
              // Someone else's thought shows no counts: only the way to
              // their world and to your own reply.
              const Spacer(),
              Flexible(
                child: GestureDetector(
                  onTap: widget.onWorld,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4 * k),
                    child: Text(
                      "${widget.friend.name}'s world ›",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _chatSecondary,
                        fontSize: 12.5 * k,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 16 * k),
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
}

/// Which of a friend's posts you got to, while the prototype runs.
final Map<String, int> _postIndex = {};

/// The front friend's posts as a stack. The top card is the one you read;
/// the next ones peek out underneath as card edges. Swipe up on the card to
/// send it back into the beam and bring the next one up; swipe down to bring
/// the previous one back.
class _PostStack extends StatefulWidget {
  final _ProtoFriend friend;
  final double maxHeight;
  final double expand;
  final double k;
  final double alpha;
  final VoidCallback onOpen;
  final VoidCallback onWorld;

  const _PostStack({
    required this.friend,
    required this.maxHeight,
    required this.expand,
    required this.k,
    required this.alpha,
    required this.onOpen,
    required this.onWorld,
  });

  @override
  State<_PostStack> createState() => _PostStackState();
}

class _PostStackState extends State<_PostStack>
    with SingleTickerProviderStateMixin {
  static const double _fly = 260;

  late final List<_PastThought> _posts = _thoughtsOf(widget.friend.name);
  late int _index = (_postIndex[widget.friend.name] ?? 0).clamp(
    0,
    _posts.length - 1,
  );

  /// Vertical offset of the top card while dragging (up is negative).
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );

  bool get _canNext => _index < _posts.length - 1;

  /// The line under the card: your own chat with the author, from your
  /// first reply to this post on. Null until you replied or reacted.
  bool get _hasLine => _replyLine(widget.friend.name, _index) != null;

  /// Room for the cards, less the reply line under them.
  double get _room =>
      widget.maxHeight - (_hasLine ? _ReplyLine.height * widget.k : 0);

  @override
  void initState() {
    super.initState();
    _chatTick.addListener(_onChat);
  }

  void _onChat() {
    if (mounted) setState(() {});
  }

  bool get _canPrev => _index > 0;
  bool get _open => widget.expand > 0.9;

  @override
  void dispose() {
    _chatTick.removeListener(_onChat);
    _drag.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!_open) return;
    _drag.stop();
    final next = _drag.value + details.delta.dy;
    final blocked = (next < 0 && !_canNext) || (next > 0 && !_canPrev);
    _drag.value = blocked ? _drag.value + details.delta.dy * 0.25 : next;
  }

  Future<void> _onEnd(DragEndDetails details) async {
    if (!_open) return;
    final velocity = details.primaryVelocity ?? 0;
    final reduce = MediaQuery.disableAnimationsOf(context);
    if ((_drag.value < -70 || velocity < -500) && _canNext) {
      HapticFeedback.selectionClick();
      if (!reduce) {
        await _drag.animateTo(
          -_fly,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeIn,
        );
      }
      if (!mounted) return;
      setState(() => _postIndex[widget.friend.name] = ++_index);
      _drag.value = 0;
    } else if ((_drag.value > 70 || velocity > 500) && _canPrev) {
      HapticFeedback.selectionClick();
      setState(() => _postIndex[widget.friend.name] = --_index);
      if (reduce) {
        _drag.value = 0;
      } else {
        _drag.value = -_fly;
        await _drag.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    } else {
      await _drag.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _card(int i, {required double expand}) {
    // A live thought that leads with photos opens as a carousel; every other
    // post opens as a post card. Both fold back to the plain bubble while
    // the orbit turns.
    final name = widget.friend.name;
    if (expand >= 0.5 && (i > 0 || _textLed(widget.friend))) {
      final post = i == 0 ? _livePost(widget.friend) : _pastPost(name, _posts[i]);
      final space = post.space;
      // The "more from" hint only needs its room when there is more.
      final hint = _posts.length - 1 - i > 0 ? 48 * widget.k : 0.0;
      return _PostCard(
        key: ValueKey(i == 0 ? 'text-post-$name' : 'post-$name-$i'),
        post: post,
        maxHeight: _room - hint,
        expand: expand,
        k: widget.k,
        alpha: widget.alpha,
        onOpen: () => _openThought(context, name, i),
        onSpace: space == null ? null : () => _openSpace(context, name, space),
      );
    }
    // In the universe look, media posts float on the sky too.
    if (i == 0 &&
        expand >= 0.5 &&
        OrbitDepthTuning.postCards == OrbitPostCards.universe) {
      final hint = _posts.length - 1 > 0 ? 48 * widget.k : 0.0;
      return _UniverseMediaCard(
        key: ValueKey('universe-media-card-$name'),
        friend: widget.friend,
        maxHeight: _room - hint,
        expand: expand,
        k: widget.k,
        alpha: widget.alpha,
        onOpen: () => _openThought(context, name, 0),
      );
    }
    if (i == 0 && expand >= 0.5) {
      return _CarouselCard(
        key: ValueKey('carousel-card-${widget.friend.name}'),
        friend: widget.friend,
        maxHeight: _room - 48 * widget.k,
        expand: expand,
        k: widget.k,
        alpha: widget.alpha,
      );
    }
    return _thoughtCard(i, expand: expand);
  }

  Widget _thoughtCard(int i, {required double expand}) => _ThoughtCard(
    key: ValueKey('post-${widget.friend.name}-$i'),
    friend: widget.friend,
    post: i == 0 ? null : _posts[i],
    maxHeight: _room - 48 * widget.k,
    expand: expand,
    k: widget.k,
    alpha: widget.alpha,
    onOpen: widget.onOpen,
    onWorld: widget.onWorld,
  );

  @override
  Widget build(BuildContext context) {
    // On the sky the post only shows the latest thought: every swipe over it
    // belongs to the orbit, and older posts wait in the thread.
    final universe = OrbitDepthTuning.postCards == OrbitPostCards.universe;
    return GestureDetector(
      onVerticalDragUpdate: universe ? null : _onUpdate,
      onVerticalDragEnd: universe ? null : _onEnd,
      child: AnimatedBuilder(
        animation: _drag,
        builder: (context, _) {
          final k = widget.k;
          final t = (-_drag.value / _fly).clamp(0.0, 1.0);
          final peek = 12 * k;
          final open = _interval(widget.expand, 0.85, 1);
          final layers = <Widget>[];

          // Edges of the posts underneath; they step up as the top one
          // leaves. Without a card to hide behind they would show through
          // the words, so the universe look leaves them out.
          final peeks =
              OrbitDepthTuning.postCards == OrbitPostCards.framed;
          for (var j = 2; j >= 1; j--) {
            if (!peeks || _index + j >= _posts.length || open <= 0) continue;
            final depth = j - t;
            layers.add(
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (open * (1 - 0.3 * depth)).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, depth * peek),
                      child: Transform.scale(
                        scale: 1 - 0.05 * depth,
                        alignment: Alignment.bottomCenter,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _chat.surfaceSubtle,
                            borderRadius: BorderRadius.circular(20 * k),
                            border: Border.all(
                              color: _chat.border.withValues(alpha: 0.35),
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
          // The next post rising into place as the top one leaves.
          if (t > 0 && _canNext) {
            layers.add(
              IgnorePointer(
                child: Opacity(
                  // Fades in only once the top card is mostly gone, so the
                  // two never show through each other.
                  opacity: _interval(t, 0.35, 1),
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * peek),
                    child: _card(_index + 1, expand: 1),
                  ),
                ),
              ),
            );
          }
          // The top card: it goes back up into the beam, shrinking away.
          final down = _drag.value > 0 ? _drag.value * 0.5 : 0.0;
          layers.add(
            Opacity(
              opacity: (1 - t * 2.2).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, _drag.value < 0 ? _drag.value : down),
                child: Transform.scale(
                  scale: 1 - 0.2 * t,
                  alignment: Alignment.topCenter,
                  child: _card(_index, expand: widget.expand),
                ),
              ),
            ),
          );

          final remaining = _posts.length - 1 - _index;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(clipBehavior: Clip.none, children: layers),
              if (_hasLine && open > 0)
                Opacity(
                  opacity: open,
                  child: _ReplyLine(
                    owner: widget.friend.name,
                    post: _index,
                    k: k,
                  ),
                ),
              if (remaining > 0 &&
                  open > 0 &&
                  OrbitDepthTuning.postCards == OrbitPostCards.framed)
                Padding(
                  padding: EdgeInsets.only(top: peek * 2 + 10 * k),
                  child: Opacity(
                    opacity: open,
                    child: Text(
                      remaining == 1
                          ? '1 more from ${widget.friend.name} · swipe up'
                          : '$remaining more from ${widget.friend.name} · swipe up',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, fontSize: 12 * k),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A beam of light from the front friend's platform down to their card, so
/// the card reads as projected out of them, towards you.
class _BeamPainter extends CustomPainter {
  final Rect from;
  final Rect to;
  final Color color;
  final double strength;
  final double k;

  _BeamPainter({
    required this.from,
    required this.to,
    required this.color,
    required this.strength,
    required this.k,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0.01) return;
    final inset = 14 * k;
    final topY = from.center.dy;
    final bottomY = to.top + 2;
    if (bottomY <= topY) return;
    final path = Path()
      ..moveTo(from.left, topY)
      ..lineTo(from.right, topY)
      ..lineTo(to.right - inset, bottomY)
      ..lineTo(to.left + inset, bottomY)
      ..close();
    final bounds = Rect.fromLTRB(to.left, topY, to.right, bottomY);
    double a(double v) => (v * strength).clamp(0.0, 1.0);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: a(0.22)),
            color.withValues(alpha: a(0.05)),
          ],
        ).createShader(bounds),
    );
    final edge = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: a(0.45)),
          color.withValues(alpha: a(0.1)),
        ],
      ).createShader(bounds)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(from.left, topY),
      Offset(to.left + inset, bottomY),
      edge,
    );
    canvas.drawLine(
      Offset(from.right, topY),
      Offset(to.right - inset, bottomY),
      edge,
    );
  }

  @override
  bool shouldRepaint(_BeamPainter old) => true;
}

/// A voice note: play/pause, a waveform that fills as it plays, and the time
/// left. Stops when [active] turns false (the card turned away).
class _VoicePlayer extends StatefulWidget {
  final int seconds;
  final double k;
  final bool active;

  const _VoicePlayer({
    required this.seconds,
    required this.k,
    this.active = true,
  });

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _playback = AnimationController(
    vsync: this,
    duration: Duration(seconds: math.max(1, widget.seconds)),
  )..addStatusListener(_onStatus);

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_VoicePlayer old) {
    super.didUpdateWidget(old);
    if (!widget.active && _playback.isAnimating) _playback.stop();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _playback.value = 0;
      setState(() {});
    }
  }

  void _toggle() {
    setState(() {
      if (_playback.isAnimating) {
        _playback.stop();
      } else {
        _playback.forward();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.k;
    return AnimatedBuilder(
      animation: _playback,
      builder: (context, _) {
        final playing = _playback.isAnimating;
        final remaining = (widget.seconds * (1 - _playback.value)).ceil().clamp(
          0,
          999,
        );
        return Row(
          children: [
            Tooltip(
              message: playing ? 'Pause voice note' : 'Play voice note',
              child: GestureDetector(
                onTap: _toggle,
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
  final double glow;
  final int glowLayer;
  final double lean;

  /// On the dial, how far the orbit steps back while a card is open (the
  /// front friend stays bright).
  final double dim;

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
    required this.glow,
    required this.glowLayer,
    this.lean = 0,
    this.dim = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (OrbitDepthTuning.showStars) _paintStars(canvas, size);

    for (final lv in layers) {
      if (!OrbitDepthTuning.showRing) continue;
      if (OrbitDepthTuning.dial) {
        _dialRing(canvas, lv);
      } else {
        _oval(
        canvas,
        Offset(cx, lv.cy),
        ringBase * lv.scale,
        const Color(0xFF2E3B35).withValues(alpha: lv.opacity),
          dashLength: 6 * k * lv.scale,
          layerSquash: lv.c,
        );
      }
      // The ring you just shared a thought to lights up once.
      if (glow > 0.01 && lv.layer == glowLayer) {
        final rect = Rect.fromCenter(
          center: Offset(cx, lv.cy),
          width: ringBase * lv.scale * 2,
          height: ringBase * lv.scale * 2 * lv.c,
        );
        canvas.drawOval(
          rect,
          Paint()
            ..color = _accent.withValues(alpha: 0.75 * glow * lv.opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * k
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * k),
        );
      }
    }

    // Platforms: start as a circle hidden behind the avatar, then flatten
    // into a glowing disc as the avatar lifts off it.
    final reveal = OrbitDepthTuning.dial ? 0.0 : Curves.easeOut.transform(t);
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
    if (OrbitDepthTuning.dial) {
      final shadow = Paint();
      if (you != null) {
        shadow
          ..color = Colors.black.withValues(alpha: 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * k);
        canvas.drawOval(
          Rect.fromCenter(
            center: you.translate(0, youSize * 0.56),
            width: youSize * 0.8,
            height: math.max(3 * k, youSize * 0.16),
          ),
          shadow,
        );
      }
      for (final seat in seats) {
        final a =
            0.5 * seat.opacity * (identical(seat, spotlight) ? 1 : 1 - dim);
        if (a <= 0.01) continue;
        shadow
          ..color = Colors.black.withValues(alpha: a)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * k);
        canvas.drawOval(
          Rect.fromCenter(
            center: seat.avatarCenter.translate(0, seat.size * 0.56),
            width: seat.size * 0.8,
            height: math.max(3 * k, seat.size * 0.16),
          ),
          shadow,
        );
      }
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

  /// A dial ring through the same camera as the faces on it: thin and faint
  /// at the back, fuller at the front.
  void _dialRing(Canvas canvas, _LayerView lv) {
    const steps = 96;
    final centre = Offset(cx, lv.cy);
    final radius = ringBase * lv.scale;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    var (prev, _) = _dialProject(0, radius, lv.c, lv.s, lean);
    for (var i = 1; i <= steps; i++) {
      final theta = i / steps * 2 * math.pi;
      final (next, _) = _dialProject(theta, radius, lv.c, lv.s, lean);
      final depth = math.sin(theta - math.pi / steps);
      final front = (depth + 1) / 2;
      paint
        ..color = _ink.withValues(
          alpha:
              _lerp(0.16, _lerp(0.05, 0.3, front), t) *
              lv.opacity *
              (1 - dim) *
              _peekShow(lv.rel * t, depth),
        )
        ..strokeWidth = _lerp(1, _lerp(0.5, 1.6, front), t) * k;
      canvas.drawLine(centre + prev, centre + next, paint);
      prev = next;
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
      final angle =
          star.angle +
          rotation *
              (OrbitDepthTuning.dial ? 0.03 + 0.3 * (1 - star.z) : 0.12);
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
    double? layerSquash,
  }) {
    if (color.a <= 0.01) return;
    final rect = Rect.fromCenter(
      center: center,
      width: radius * 2,
      height: radius * 2 * (layerSquash ?? squash),
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
