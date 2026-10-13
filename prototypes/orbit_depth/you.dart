part of 'orbit_depth_prototype_screen.dart';

// You: your thoughts, your Spaces, who is Close, and who can reach you
// through your friends. A thought is shared from the plus on your photo in
// the middle of the orbit: to Close, to Friends, or to people you pick. It
// stays on the orbit for 24 h, then in your Thoughts for 30 days. Under each
// thought you see reactions and how many wrote to you, never who viewed it
// and never what anyone wrote; that is in your chats.

/// Who a thought goes to.
enum _Audience { close, friends, picked }

/// One thought you shared. [id] keys its reactions and the replies that
/// quote it, so they stay with it as newer thoughts arrive.
class _MyThought {
  final int id;
  final _PastThought thought;
  final _Audience audience;

  /// Photos, videos and voice notes shared with it, in order.
  final List<_Slide> media;

  const _MyThought(this.id, this.thought, this.audience, {this.media = const []});
}

/// Your thoughts, newest first. They last while the prototype runs.
final List<_MyThought> _yourThoughts = _seedThoughts();

List<_MyThought> _seedThoughts() => [
  const _MyThought(
    0,
    _PastThought(
      'ran 5k in 28:55. slowly getting there',
      age: '2 d',
      kind: _ThoughtKind.photo,
      photo: 'trip_road',
      space: 'Runs',
    ),
    _Audience.friends,
    media: [
      _Slide.photo('trip_road'),
      _Slide.video('trip_valley', 14),
      _Slide.photo('trip_ridge'),
    ],
  ),
  const _MyThought(
    1,
    _PastThought(
      'chapter 12 of Thinking, Fast and Slow. my brain hurts',
      age: '4 d',
      space: 'Books',
    ),
    _Audience.close,
    media: [_Slide.voice(18, 'what I think about it so far')],
  ),
  const _MyThought(
    2,
    _PastThought(
      'sunset at the falls. worth the climb',
      age: '6 d',
      kind: _ThoughtKind.photo,
      photo: 'trip_falls',
    ),
    _Audience.friends,
    media: [_Slide.video('trip_falls', 12)],
  ),
];

int _nextThoughtId = 100;

/// '2 d ago', or just 'now'.
String _ago(String age) => age == 'now' ? 'now' : '$age ago';

/// Ticks when you share a thought or a friend reacts to one.
final ValueNotifier<int> _yourTick = ValueNotifier(0);

/// Your thoughts as [_thoughtsOf] lists them: the newest is the live one.
List<_PastThought> _yourPastThoughts() => [
  for (var i = 0; i < _yourThoughts.length; i++)
    i == 0 ? _asLive(_yourThoughts[i].thought) : _yourThoughts[i].thought,
];

_PastThought _asLive(_PastThought t) => _PastThought(
  t.text,
  age: t.age,
  kind: t.kind,
  more: t.more,
  seconds: t.seconds,
  photo: t.photo,
  comments: t.comments,
  space: t.space,
  live: true,
);

/// Friends answer in the prototype a little later; cancelled with the app.
final List<Timer> _friendTimers = [];

/// Who reacted to each of your thoughts (by its id), and with what. You see
/// them only as counts.
final Map<int, Map<String, String>> _reactionsTo = _seedReactions();

Map<int, Map<String, String>> _seedReactions() => {
  0: {
    'omar': '😍',
    'nour': '😍',
    'layla': '👏',
    'tarek': '🔥',
    'sara': '😍',
    'dana': '👏',
  },
  1: {'layla': '😂', 'omar': '😂'},
};

/// How many friends sent each reaction to your thought [id].
Map<String, int> _reactionCounts(int id) {
  final counts = <String, int>{};
  for (final emoji in (_reactionsTo[id] ?? const {}).values) {
    counts[emoji] = (counts[emoji] ?? 0) + 1;
  }
  return counts;
}

/// Friends who wrote to you about your thought [id], newest chat first.
List<String> _wroteAbout(int id) => [
  for (final e in _dms.entries)
    if (e.value.messages.any(
      (m) => !m.mine && m.about?.author == 'you' && m.about?.post == id,
    ))
      e.key,
];

/// The audience you used last; the composer starts there.
var _lastAudience = _Audience.friends;

/// People you picked for a thought.
final Set<String> _picked = {};

String _audienceName(_Audience a) => switch (a) {
  _Audience.close => 'Close',
  _Audience.friends => 'Friends',
  _Audience.picked => 'Picked people',
};

int _audienceSize(_Audience a) => switch (a) {
  _Audience.close => _closeNames.length,
  _Audience.friends => _everyone.length,
  _Audience.picked => _picked.length,
};

void _shareThought(String text, _Audience audience, {String? photo}) {
  final id = _nextThoughtId++;
  final quote = _Quote('you', id, text);
  _yourThoughts.insert(
    0,
    _MyThought(
      id,
      _PastThought(
        text,
        age: 'now',
        kind: photo == null ? _ThoughtKind.text : _ThoughtKind.photo,
        photo: photo,
      ),
      audience,
      media: [if (photo != null) _Slide.photo(photo)],
    ),
  );
  _lastAudience = audience;
  _yourTick.value++;
  _sharedTo.value = (audience == _Audience.close ? 0 : 1, id);
  void later(int seconds, void Function() answer) {
    _friendTimers.add(
      Timer(Duration(seconds: seconds), () {
        answer();
        _yourTick.value++;
      }),
    );
  }

  later(3, () => (_reactionsTo[id] ??= {})['omar'] = '😍');
  later(5, () => (_reactionsTo[id] ??= {})['layla'] = '👏');
  later(7, () {
    final dm = _dms.putIfAbsent('nour', () => _Dm([]));
    dm.messages.add(
      _Msg('nour', 'love this. tell me more?', 'now', about: quote),
    );
    dm.unread++;
    _chatTick.value++;
    _notify('Reply from nour on your thought');
  });
}

void _push(BuildContext context, Widget page) {
  HapticFeedback.selectionClick();
  Navigator.of(context).push(_diveRoute(page));
}

void _openYou(BuildContext context) => _push(context, const _YouPage());

/// The + on your photo: your page with the keyboard up, ready to write.
void _openComposer(BuildContext context) =>
    _push(context, const _YouPage(compose: true));

// ---------------------------------------------------------------------------
// You: opened from your photo in the middle of the orbit. Your thoughts as
// one running feed, oldest at the top like a chat, in the look of a terminal:
// who sees each one, its photo, its reactions as counts, and under it one row
// for each friend who wrote to you about it. A row opens your chat with
// them; nobody else sees what they wrote, so these are never comments. The
// counts in the corner open your world: who sees you, Spaces and settings.
// ---------------------------------------------------------------------------

/// The terminal half of the page: names, tags, times and commands. Thoughts
/// and replies stay in the readable sans.
const _mono = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: ['Courier', 'monospace'],
);
const _friendsBlue = Color(0xFF5FB3C9);
const _faint = Color(0xFF59625D);

/// Photos you can attach while writing, one more each tap.
const _photoPicks = ['trip_canoe', 'trip_falls', 'food_latte', 'trip_ridge'];

Color _audienceColor(_Audience a) => switch (a) {
  _Audience.close => _accent,
  _Audience.friends => _friendsBlue,
  _Audience.picked => _ink,
};

/// A friend's colour on your page: green if they are Close.
Color _personColor(String name) =>
    _closeNames.contains(name) ? _accent : _friendsBlue;

/// Frosted glass over the sky.
class _Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final Color edge;
  final double tint;

  const _Glass({
    super.key,
    required this.child,
    this.radius = 14,
    this.edge = const Color(0x14E8ECE9),
    this.tint = 0.035,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: tint),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: edge),
        ),
        child: child,
      ),
    ),
  );
}

class _YouPage extends StatefulWidget {
  /// Opened from the + to write: the field takes focus at once.
  final bool compose;

  const _YouPage({this.compose = false});

  @override
  State<_YouPage> createState() => _YouPageState();
}

class _YouPageState extends State<_YouPage> {
  final TextEditingController _field = TextEditingController();
  late _Audience _audience = _lastAudience;
  String? _attached;
  int _nextPick = 0;

  /// Typing / asks who sees the thought.
  bool get _asking => _field.text.endsWith('/');

  @override
  void initState() {
    super.initState();
    _field.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _pick(_Audience a) {
    HapticFeedback.selectionClick();
    final text = _field.text;
    _field.text = text.substring(0, text.length - 1).trimRight();
    setState(() => _audience = a);
  }

  Future<void> _pickPeople() async {
    _pick(_Audience.picked);
    await _openSheet(context, const _PickPeopleSheet());
    if (mounted) setState(() {});
  }

  void _attach() {
    HapticFeedback.selectionClick();
    setState(() {
      _attached = _photoPicks[_nextPick % _photoPicks.length];
      _nextPick++;
    });
  }

  void _share() {
    final text = _field.text.replaceAll(RegExp(r'/$'), '').trim();
    if (text.isEmpty || _audienceSize(_audience) == 0) return;
    HapticFeedback.mediumImpact();
    _shareThought(text, _audience, photo: _attached);
    _field.clear();
    setState(() => _attached = null);
    final n = _audienceSize(_audience);
    _notify(
      'Shared with ${_audience == _Audience.picked ? '$n you picked' : _audienceName(_audience)} · $n ${n == 1 ? 'person' : 'people'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('you'),
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: Listenable.merge([_yourTick, _chatTick, _ringTick]),
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const Divider(height: 1, color: Color(0x14E8ECE9)),
              Expanded(
                child: ListView(
                  key: const ValueKey('you-feed'),
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: [
                    for (var i = 0; i < _yourThoughts.length; i++)
                      _FeedThought(index: i),
                  ],
                ),
              ),
              _composer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 8, 6),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: _ink),
        ),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x991DB954), width: 2),
          ),
          child: _personPhoto('you', 28),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            const TextSpan(
              children: [
                TextSpan(text: 'you/', style: TextStyle(color: _accent)),
                TextSpan(text: ' @saleh'),
              ],
            ),
            style: _mono.copyWith(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Tooltip(
          message: 'Your world',
          child: InkWell(
            key: const ValueKey('you-world'),
            borderRadius: BorderRadius.circular(22),
            onTap: () => _push(context, const _YouWorldPage()),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Text('● ', style: _mono.copyWith(color: _accent, fontSize: 12)),
                    Text(
                      '${_closeNames.length}  ',
                      style: _mono.copyWith(color: _muted, fontSize: 12),
                    ),
                    Text('● ', style: _mono.copyWith(color: _friendsBlue, fontSize: 12)),
                    Text(
                      '${_everyone.length}',
                      style: _mono.copyWith(color: _muted, fontSize: 12),
                    ),
                    const Icon(Icons.chevron_right, size: 16, color: _muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _composer(BuildContext context) {
    final color = _audienceColor(_audience);
    final ready = _field.text.replaceAll('/', '').trim().isNotEmpty;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0x2E05070C),
            border: Border(top: BorderSide(color: Color(0x14E8ECE9))),
          ),
          padding: EdgeInsets.fromLTRB(
            12,
            10,
            12,
            MediaQuery.viewInsetsOf(context).bottom > 0
                ? 10
                : MediaQuery.paddingOf(context).bottom + 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_asking) ...[_commands(), const SizedBox(height: 10)],
              if (_attached case final photo?) ...[
                Row(
                  children: [
                    const SizedBox(width: 52),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image(
                            key: const ValueKey('attached-photo'),
                            image: _photo(photo),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: -10,
                          right: -10,
                          child: IconButton(
                            tooltip: 'Remove photo',
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF1B2026),
                            ),
                            onPressed: () => setState(() => _attached = null),
                            icon: const Icon(Icons.close, size: 12, color: _ink),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('add-photo'),
                    tooltip: 'Add a photo',
                    onPressed: _attach,
                    style: IconButton.styleFrom(
                      fixedSize: const Size(44, 44),
                      backgroundColor: const Color(0x0FFFFFFF),
                    ),
                    icon: const Icon(
                      Icons.image_outlined,
                      color: Color(0xFFC7CEC9),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.only(left: 12, right: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x0DFFFFFF),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: _asking
                              ? color.withValues(alpha: 0.5)
                              : const Color(0x14E8ECE9),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text('>', style: _mono.copyWith(color: _accent, fontSize: 14)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('you-field'),
                              controller: _field,
                              autofocus: widget.compose,
                              minLines: 1,
                              maxLines: 4,
                              textAlignVertical: TextAlignVertical.center,
                              style: const TextStyle(color: _ink, fontSize: 15),
                              decoration: const InputDecoration(
                                hintText: 'share a thought',
                                hintStyle: TextStyle(color: Color(0xFF8A8F98)),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          TextButton(
                            key: const ValueKey('you-audience'),
                            onPressed: () => _field.text = '${_field.text}/',
                            style: TextButton.styleFrom(
                              foregroundColor: color,
                              minimumSize: const Size(44, 44),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: Text(
                              _audience == _Audience.picked
                                  ? 'picked'
                                  : _audience.name,
                              style: _mono.copyWith(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const ValueKey('you-share'),
                    tooltip: 'Share',
                    onPressed: ready ? _share : null,
                    style: IconButton.styleFrom(
                      fixedSize: const Size(44, 44),
                      backgroundColor: _accent,
                      foregroundColor: const Color(0xFF03140A),
                      disabledBackgroundColor: const Color(0x401DB954),
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The / menu: who sees the thought.
  Widget _commands() {
    Widget row(_Audience a, String command, String who, VoidCallback onTap) =>
        InkWell(
          key: ValueKey('command-${a.name}'),
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: a == _audience ? _audienceColor(a).withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    command,
                    style: _mono.copyWith(color: _audienceColor(a), fontSize: 14),
                  ),
                ),
                Expanded(
                  child: Text(
                    who,
                    style: const TextStyle(color: Color(0xFFC7CEC9), fontSize: 14),
                  ),
                ),
                if (a == _lastAudience)
                  Text(
                    'last used',
                    style: _mono.copyWith(color: _audienceColor(a), fontSize: 11),
                  ),
              ],
            ),
          ),
        );
    return _Glass(
      tint: 0.06,
      radius: 16,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          key: const ValueKey('commands'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
              child: Text(
                'who sees it',
                style: _mono.copyWith(color: const Color(0xFF8C968F), fontSize: 11.5),
              ),
            ),
            row(
              _Audience.close,
              '/close',
              '${_closeNames.length} Close friends',
              () => _pick(_Audience.close),
            ),
            row(
              _Audience.friends,
              '/friends',
              '${_everyone.length} friends',
              () => _pick(_Audience.friends),
            ),
            row(
              _Audience.picked,
              '/pick',
              _picked.isEmpty ? 'people you choose' : '${_picked.length} picked',
              _pickPeople,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
              child: Text(
                'friends of friends never see thoughts',
                style: _mono.copyWith(color: const Color(0xFF8C968F), fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of your thoughts in the feed, and the friends who wrote to you about
/// it.
class _FeedThought extends StatelessWidget {
  final int index;

  const _FeedThought({required this.index});

  @override
  Widget build(BuildContext context) {
    final t = _yourThoughts[index];
    final color = _audienceColor(t.audience);
    final photo = t.thought.photo;
    final reactions = _reactionCounts(t.id).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final wrote = _wroteAbout(t.id);
    final small = _mono.copyWith(color: _faint, fontSize: 11.5);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '── ${t.thought.age == 'now' ? 'today' : _ago(t.thought.age)} '
            '${'─' * 24}',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: small,
          ),
          const SizedBox(height: 6),
          Text(
            '[${t.audience == _Audience.picked ? 'picked' : t.audience.name}] >',
            style: _mono.copyWith(color: color, fontSize: 12),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            key: ValueKey('your-thought-${t.id}'),
            onTap: () => _openThought(context, 'you', index),
            child: Text(
              t.thought.text,
              style: const TextStyle(
                color: _ink,
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (t.media.isNotEmpty) ...[
            const SizedBox(height: 8),
            _FeedMedia(id: t.id, media: t.media, edge: color),
          ] else if (photo != null) ...[
            const SizedBox(height: 8),
            _FeedMedia(id: t.id, media: [_Slide.photo(photo)], edge: color),
          ],
          if (reactions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [for (final e in reactions) '${e.key} ${e.value}'].join('  '),
              style: _mono.copyWith(color: _muted, fontSize: 12.5),
            ),
          ],
          if (index == 0) ...[
            const SizedBox(height: 4),
            Text(
              '* on the orbit for 24 h · ${_audienceSize(t.audience)} people *',
              style: _mono.copyWith(
                color: const Color(0xFF8C968F),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (wrote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.lock_outline, size: 12, color: Color(0xFF8C968F)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'wrote to you · each one is private',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mono.copyWith(color: const Color(0xFF8C968F), fontSize: 11.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _Glass(
              edge: color.withValues(alpha: 0.25),
              child: Column(
                children: [
                  for (var i = 0; i < wrote.length; i++)
                    _WroteRow(id: t.id, name: wrote[i], last: i == wrote.length - 1),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What a thought carries, at a size you can see: photos and videos as
/// tiles that open full screen, voice notes that play right here.
class _FeedMedia extends StatelessWidget {
  final int id;
  final List<_Slide> media;
  final Color edge;

  const _FeedMedia({required this.id, required this.media, required this.edge});

  @override
  Widget build(BuildContext context) {
    final visual = [
      for (final m in media)
        if (m.kind == _SlideKind.photo || m.kind == _SlideKind.video) m,
    ];
    Widget tile(int i, {double radius = 12}) => _MediaTile(
      key: ValueKey('media-$id-$i'),
      slide: visual[i],
      edge: edge,
      radius: radius,
      onTap: () => _openMedia(context, visual, i),
    );
    final Widget? grid = switch (visual.length) {
      0 => null,
      1 => SizedBox(height: 170, child: tile(0)),
      2 => SizedBox(
        height: 140,
        child: Row(
          children: [
            Expanded(child: tile(0)),
            const SizedBox(width: 4),
            Expanded(child: tile(1)),
          ],
        ),
      ),
      _ => SizedBox(
        height: 180,
        child: Row(
          children: [
            Expanded(flex: 3, child: tile(0)),
            const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Expanded(child: tile(1)),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        tile(2),
                        if (visual.length > 3)
                          IgnorePointer(
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0x99000000),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '+${visual.length - 3}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?grid,
        for (final m in media)
          if (m.kind == _SlideKind.voice)
            Padding(
              padding: EdgeInsets.only(top: grid == null ? 0 : 6),
              child: _Glass(
                key: ValueKey('voice-$id'),
                edge: edge.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.text case final label?)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 2),
                          child: Text(
                            label,
                            style: _mono.copyWith(color: _muted, fontSize: 11.5),
                          ),
                        ),
                      _VoicePlayer(seconds: m.seconds, k: 1),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// One photo or video in the feed. A video shows its length and a play
/// button; either opens full screen.
class _MediaTile extends StatelessWidget {
  final _Slide slide;
  final Color edge;
  final double radius;
  final VoidCallback onTap;

  const _MediaTile({
    super.key,
    required this.slide,
    required this.edge,
    required this.radius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final video = slide.kind == _SlideKind.video;
    return Semantics(
      button: true,
      label: video ? 'Play video' : 'Open photo',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: edge.withValues(alpha: 0.35)),
            image: DecorationImage(image: _photo(slide.photo!), fit: BoxFit.cover),
          ),
          child: video
              ? Stack(
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.75),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _Pill(
                        text: '\u25b6 0:${'${slide.seconds}'.padLeft(2, '0')}',
                        k: 1,
                      ),
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
  }
}

/// Photos and videos full screen: swipe between them, pinch a photo to zoom,
/// tap a video to play it.
void _openMedia(BuildContext context, List<_Slide> media, int start) {
  HapticFeedback.selectionClick();
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => _MediaViewer(media: media, start: start),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _MediaViewer extends StatefulWidget {
  final List<_Slide> media;
  final int start;

  const _MediaViewer({required this.media, required this.start});

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  late final PageController _pages = PageController(initialPage: widget.start);
  late int _at = widget.start;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    return Scaffold(
      key: const ValueKey('media-viewer'),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: media.length,
            onPageChanged: (i) => setState(() => _at = i),
            itemBuilder: (context, i) {
              final m = media[i];
              return Center(
                child: m.kind == _SlideKind.video
                    ? AspectRatio(
                        aspectRatio: 4 / 5,
                        child: _VideoSlide(slide: m, k: 1.2, active: i == _at),
                      )
                    : InteractiveViewer(
                        maxScale: 4,
                        child: Image(image: _photo(m.photo!), fit: BoxFit.contain),
                      ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Spacer(),
                  if (media.length > 1)
                    Text(
                      '${_at + 1} / ${media.length}',
                      style: _mono.copyWith(color: Colors.white, fontSize: 13),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A friend who wrote to you about a thought: the newest line of your chat,
/// and whether there is something new. It opens that chat.
class _WroteRow extends StatelessWidget {
  final int id;
  final String name;
  final bool last;

  const _WroteRow({required this.id, required this.name, required this.last});

  @override
  Widget build(BuildContext context) {
    final dm = _dms[name]!;
    final newest = dm.messages.last;
    final first = dm.messages.indexWhere(
      (m) => m.about?.author == 'you' && m.about?.post == id,
    );
    final since = dm.messages.length - first;
    final color = _personColor(name);
    return InkWell(
      key: ValueKey('wrote-$id-$name'),
      onTap: () => _openDm(context, name),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Color(0x0FE8ECE9))),
        ),
        child: Row(
          children: [
            _personPhoto(name, 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '<@$name ', style: TextStyle(color: color)),
                        const TextSpan(
                          text: '→ you',
                          style: TextStyle(color: Color(0xFF8C968F)),
                        ),
                        TextSpan(text: '>', style: TextStyle(color: color)),
                        TextSpan(
                          text: '  ${newest.age}',
                          style: const TextStyle(color: _faint),
                        ),
                      ],
                    ),
                    style: _mono.copyWith(fontSize: 12),
                  ),
                  Text(
                    newest.mine ? 'you: ${newest.text}' : newest.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: newest.mine ? _muted : _ink,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            if (dm.unread > 0)
              Container(
                key: ValueKey('unread-$name'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              )
            else if (since > 1)
              Text('$since msgs', style: _mono.copyWith(color: _muted, fontSize: 11)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF8C968F)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Your world: opened from the counts on your page. Your photo sits in
// the middle with three rings around it: Close, Friends, and friends of
// friends. Each card on your page is a dot on the ring of the people who see
// it. The camera never turns; swiping up on the rings, or tapping one, goes
// out to that ring, and the cards it holds are listed flat below.
// ---------------------------------------------------------------------------

enum _Ring {
  close('Close', Color(0xFF1DB954), 'a Close friend'),
  friends('Friends', Color(0xFF5FB3C9), 'a friend'),
  fof('Friends of friends', Color(0xFFA993E6), 'a friend of a friend');

  final String label;
  final Color color;
  final String one;

  const _Ring(this.label, this.color, this.one);

  /// World radius of the ring, and how far the camera stands to frame it.
  double get radius => const [1.0, 1.75, 2.5][index];
  double get frame => const [9.5, 10.8, 12.0][index];
}

/// One card on your page, on the ring of the people who see it.
class _YouCard {
  final String id;
  final _Ring ring;

  /// Seen only by people you picked, so nobody viewing a ring sees it.
  final bool picked;
  /// [viewing] when shown as someone else sees it: your counts stay yours.
  final Widget Function(BuildContext context, bool viewing) build;

  const _YouCard(this.id, this.ring, this.build, {this.picked = false});
}

List<_YouCard> _youCards() => [
  for (var i = 0; i < _yourThoughts.length; i++)
    _YouCard(
      'thought-${_yourThoughts[i].id}',
      _yourThoughts[i].audience == _Audience.close ? _Ring.close : _Ring.friends,
      picked: _yourThoughts[i].audience == _Audience.picked,
      (context, viewing) => _YourThoughtCard(index: i, viewing: viewing),
    ),
  for (final space in _spacesFor('you'))
    if (space.kind != _SpaceKind.add)
      _YouCard(
        'space-${space.title}',
        _spaceOpen[space.title] == true ? _Ring.fof : _Ring.friends,
        (context, _) => _YouCardShell(
          key: ValueKey('you-space-${space.title}'),
          ring: _spaceOpen[space.title] == true ? _Ring.fof : _Ring.friends,
          kind: 'Space · ${space.title}',
          text: space.items.isEmpty
              ? 'Nothing yet'
              : '${space.items.first.status} · ${space.items.first.title}',
          meta: '${space.items.length} ${space.kind == _SpaceKind.books ? 'books' : space.unit}',
          onTap: () => _openSpace(context, 'you', space.title),
        ),
      ),
  if (_findable)
    _YouCard(
      'note',
      _Ring.fof,
      (context, _) => _YouCardShell(
        key: const ValueKey('you-note'),
        ring: _Ring.fof,
        kind: 'Open for · in your words',
        text: _yourOpenNote,
        meta: _yourOpenTo.join(' · '),
        onTap: () => _push(context, const _FofSettingsPage()),
      ),
    ),
];

/// How many people see a ring.
String _ringPeople(_Ring r) => switch (r) {
  _Ring.close => '${_closeNames.length} Close friends',
  _Ring.friends => '${_everyone.length} friends',
  _Ring.fof => 'People your friends carry',
};

class _YouWorldPage extends StatefulWidget {
  const _YouWorldPage();

  @override
  State<_YouWorldPage> createState() => _YouWorldPageState();
}

class _YouWorldPageState extends State<_YouWorldPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<int> _frame = ValueNotifier(0);
  Duration? _last;

  _Ring _ring = _Ring.close;

  /// Whose eyes you look through, or null for your own.
  _Ring? _viewer;
  _Ring _beforeViewing = _Ring.close;

  double _spin = 0;
  double _spinLeft = 0;
  late double _cam = _ring.frame;
  double _camFrom = 0, _camTo = 0, _camT = 1;

  /// A ring glows once when a card lands on it.
  _Ring? _pulse;
  double _pulseT = 0;

  /// Cards still flying out from your photo to their ring, 0 → 1.
  final Map<String, double> _arriving = {};

  double _pull = 0;

  bool _reduce = false;
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    _route = ModalRoute.of(context);
  }

  @override
  void initState() {
    super.initState();
    _yourTick.addListener(_changed);
    _ringTick.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _stir());
  }

  @override
  void dispose() {
    _yourTick.removeListener(_changed);
    _ringTick.removeListener(_changed);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  /// The rings turn while you use the page and rest a while after, so a page
  /// left open costs nothing.
  void _stir() {
    _spinLeft = 20;
    _wake();
  }

  void _onTick(Duration elapsed) {
    final dt = _last == null
        ? 0.0
        : math.min(0.05, (elapsed - _last!).inMicroseconds / 1e6);
    _last = elapsed;
    var moving = false;
    final onTop = _route?.isCurrent ?? true;
    if (_spinLeft > 0) {
      _spinLeft -= dt;
      if (!_reduce && onTop) _spin += dt * 0.12;
      moving = true;
    }
    if (_camT < 1) {
      _camT = _reduce ? 1 : math.min(1, _camT + dt / 0.75);
      _cam = _camFrom + (_camTo - _camFrom) * Curves.easeInOutCubic.transform(_camT);
      moving = true;
    }
    for (final id in _arriving.keys.toList()) {
      final t = _reduce ? 1.0 : _arriving[id]! + dt / 0.9;
      if (t >= 1) {
        _arriving.remove(id);
      } else {
        _arriving[id] = t;
      }
      moving = true;
    }
    if (_pulse != null) {
      _pulseT += dt * 1.1;
      if (_pulseT > 1) _pulse = null;
      moving = true;
    }
    _frame.value++;
    if (!moving) _ticker.stop();
  }

  void _go(_Ring r) {
    HapticFeedback.selectionClick();
    setState(() => _ring = r);
    _camFrom = _cam;
    _camTo = r.frame;
    _camT = 0;
    _wake();
  }

  void _step(int by) {
    final i = (_ring.index + by).clamp(0, _Ring.values.length - 1);
    if (i != _ring.index) _go(_Ring.values[i]);
  }

  Future<void> _share() async {
    final before = _yourThoughts.isEmpty ? null : _yourThoughts.first.id;
    _lastAudience = _ring == _Ring.close ? _Audience.close : _Audience.friends;
    await _openSheet(context, const _ComposerSheet());
    if (!mounted || _yourThoughts.isEmpty) return;
    final t = _yourThoughts.first;
    if (t.id == before) return;
    final ring = t.audience == _Audience.close ? _Ring.close : _Ring.friends;
    _arriving['thought-${t.id}'] = 0;
    _pulse = ring;
    _pulseT = 0;
    _go(ring);
    _notify(
      t.audience == _Audience.picked
          ? 'Shared with ${_picked.length} people you picked'
          : 'Shared with ${ring.label} · ${_ringPeople(ring).toLowerCase()}',
    );
  }

  Future<void> _pickViewer(List<_YouCard> cards) async {
    final picked = await _openSheet<_Ring>(
      context,
      _ViewAsSheet(cards: cards),
    );
    if (picked == null || !mounted) return;
    _beforeViewing = _ring;
    setState(() => _viewer = picked);
    _go(picked);
  }

  void _backToYou() {
    setState(() => _viewer = null);
    _go(_beforeViewing);
  }

  @override
  Widget build(BuildContext context) {
    final cards = _youCards();
    return Listener(
      onPointerDown: (_) => _stir(),
      child: Scaffold(
        key: const ValueKey('you-world-page'),
        backgroundColor: Colors.transparent,
        floatingActionButton: _viewer == null
            ? FloatingActionButton(
                key: const ValueKey('you-add'),
                tooltip: 'Share a thought',
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF03140A),
                shape: const CircleBorder(),
                onPressed: _share,
                child: const Icon(Icons.add, size: 30),
              )
            : null,
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, box) {
              final sceneHeight = math.max(250.0, box.maxHeight * 0.42);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _DiveHeader(trail: ['Your world']),
                  SizedBox(
                    height: sceneHeight - 48,
                    child: _scene(cards),
                  ),
                  Expanded(child: _panel(cards)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _scene(List<_YouCard> cards) {
    final dots = <_Dot>[];
    for (final r in _Ring.values) {
      final here = [
        for (final c in cards)
          if (c.ring == r) c,
      ];
      for (var i = 0; i < here.length; i++) {
        final c = here[i];
        dots.add(
          _Dot(
            r,
            i / here.length * 2 * math.pi + r.index * 1.1,
            _arriving[c.id],
            seen: _viewer == null || (!c.picked && r.index >= _viewer!.index),
          ),
        );
      }
    }
    return GestureDetector(
      key: const ValueKey('you-rings'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _pull = 0,
      onVerticalDragUpdate: (d) => _pull += d.delta.dy,
      onVerticalDragEnd: (_) {
        if (_viewer == null && _pull.abs() > 36) _step(_pull < 0 ? 1 : -1);
        _pull = 0;
      },
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          onTapUp: (d) {
            if (_viewer != null) return;
            final hit = _RingsPainter.ringAt(
              d.localPosition,
              box.biggest,
              _cam,
            );
            if (hit != null) _go(hit);
          },
          child: ValueListenableBuilder<int>(
            valueListenable: _frame,
            builder: (context, _, _) {
              final camera = _Camera(_cam, box.biggest);
              final photo = camera.scale(_Vec(0, 0, 0)) * 0.75;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RingsPainter(
                        camera: camera,
                        spin: _spin,
                        lit: (r) => _viewer == null
                            ? r == _ring
                            : r.index >= _viewer!.index,
                        dark: (r) =>
                            _viewer != null && r.index < _viewer!.index,
                        fill: _viewer == null ? _ring : null,
                        pulse: _pulse,
                        pulseT: _pulseT,
                        dots: dots,
                      ),
                    ),
                  ),
                  Positioned(
                    left: box.maxWidth / 2 - photo / 2,
                    top: camera.center.dy - photo / 2,
                    child: Opacity(
                      opacity: _viewer == null ? 1 : 0.35,
                      child: Container(
                        width: photo,
                        height: photo,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withValues(alpha: 0.45),
                              blurRadius: photo * 0.7,
                              spreadRadius: photo * 0.08,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image(image: _photo('you'), fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 4,
                    child: Text(
                      _viewer == null
                          ? _ring == _Ring.fof
                                ? 'swipe down to come back in'
                                : 'swipe up or tap a ring to go further out'
                          : _viewer == _Ring.close
                          ? 'a Close friend sees every ring'
                          : 'the rings closer to you stay dark to them',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _muted, fontSize: 11.5),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _panel(List<_YouCard> cards) {
    final viewer = _viewer;
    final Widget top;
    final List<Widget> list;
    if (viewer == null) {
      final here = [
        for (final c in cards)
          if (c.ring == _ring) c,
      ];
      top = Column(
        children: [
          Row(
            children: [
              for (final r in _Ring.values)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: r.index == 0 ? 0 : 6),
                    child: _RingButton(
                      ring: r,
                      on: r == _ring,
                      count: cards.where((c) => c.ring == r).length,
                      onTap: () => _go(r),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(child: _ringLink()),
                TextButton(
                  key: const ValueKey('view-as'),
                  onPressed: () => _pickViewer(cards),
                  style: TextButton.styleFrom(foregroundColor: _accent),
                  child: const Text('View as…'),
                ),
              ],
            ),
          ),
        ],
      );
      list = here.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  'Nothing only ${_ring.label} sees yet.\n'
                  '${_ring == _Ring.fof ? 'Open a Space to them, or say what you’re open for.' : 'Tap + and pick ${_ring.label}.'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontSize: 14.5),
                ),
              ),
            ]
          : [
              for (final c in here) c.build(context, false),
              if (_ring == _Ring.friends)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey('you-new-space'),
                    onPressed: () => _openNewSpaceSheet(context),
                    style: TextButton.styleFrom(foregroundColor: _accent),
                    child: const Text('+ New space'),
                  ),
                ),
            ];
    } else {
      final seen = [
        for (final c in cards)
          if (!c.picked && c.ring.index >= viewer.index) c,
      ];
      top = Container(
        key: const ValueKey('viewing'),
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.only(left: 14, right: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: viewer.color),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Viewing as ${viewer.one} · sees ${seen.length} of ${cards.length}',
                style: const TextStyle(color: _ink, fontSize: 14),
              ),
            ),
            TextButton(
              key: const ValueKey('as-me'),
              onPressed: _backToYou,
              style: TextButton.styleFrom(foregroundColor: viewer.color),
              child: const Text('Back to you'),
            ),
          ],
        ),
      );
      list = [
        for (final r in _Ring.values.skip(viewer.index))
          if (seen.any((c) => c.ring == r)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
              child: Text(
                (r == viewer
                        ? 'Shared with ${r.label}'
                        : '${r.label} · reaches them too')
                    .toUpperCase(),
                style: TextStyle(
                  color: r.color,
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final c in seen)
              if (c.ring == r) IgnorePointer(child: c.build(context, true)),
          ],
      ];
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          top,
          if (viewer != null) const SizedBox(height: 6),
          Expanded(
            child: ListView(
              key: const ValueKey('you-list'),
              padding: EdgeInsets.only(
                top: 4,
                bottom: MediaQuery.paddingOf(context).bottom + 96,
              ),
              children: list,
            ),
          ),
        ],
      ),
    );
  }

  /// Who sees this ring, and where you choose them.
  Widget _ringLink() {
    Widget link(String key, String text, Widget page) => Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: ValueKey(key),
        onPressed: () => _push(context, page),
        style: TextButton.styleFrom(
          foregroundColor: _ink,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        child: Text('$text  ›', style: const TextStyle(fontSize: 14)),
      ),
    );
    return switch (_ring) {
      _Ring.close => link(
        'you-close',
        'Close friends (${_closeNames.length})',
        const _CloseFriendsPage(),
      ),
      _Ring.friends => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          '${_ringPeople(_Ring.friends)} see these',
          style: const TextStyle(color: _muted, fontSize: 14),
        ),
      ),
      _Ring.fof => link(
        'you-fof',
        _findable ? 'You can be found' : 'You can’t be found',
        const _FofSettingsPage(),
      ),
    };
  }
}

class _RingButton extends StatelessWidget {
  final _Ring ring;
  final bool on;
  final int count;
  final VoidCallback onTap;

  const _RingButton({
    required this.ring,
    required this.on,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: GestureDetector(
      key: ValueKey('ring-${ring.name}'),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? const Color(0x12FFFFFF) : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? ring.color : const Color(0x1FE8ECE9)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ring.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: on ? ring.color : _muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$count',
              style: TextStyle(color: on ? ring.color : _muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A card on your page: a coloured edge for its ring, what it is, the words.
class _YouCardShell extends StatelessWidget {
  final _Ring ring;
  final String kind;
  final String text;
  final String meta;
  final VoidCallback onTap;
  final Widget? below;

  const _YouCardShell({
    super.key,
    required this.ring,
    required this.kind,
    required this.text,
    required this.meta,
    required this.onTap,
    this.below,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GestureDetector(
      onTap: onTap,
      child: _Edged(
        color: ring.color,
        fill: _chat.surfaceRaised,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kind.toUpperCase(),
              style: TextStyle(
                color: ring.color,
                fontSize: 11,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              text,
              style: const TextStyle(color: _ink, fontSize: 15.5, height: 1.4),
            ),
            const SizedBox(height: 6),
            Text(meta, style: _soft),
            ?below,
          ],
        ),
      ),
    ),
  );
}

/// A rounded box with a hairline outline and its ring's colour down the left.
class _Edged extends StatelessWidget {
  final Color color;
  final Color fill;
  final EdgeInsets padding;
  final double minHeight;
  final Widget child;

  const _Edged({
    required this.color,
    required this.fill,
    required this.padding,
    required this.child,
    this.minHeight = 0,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: _chat.border),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          alignment: minHeight > 0 ? Alignment.centerLeft : null,
          padding: padding,
          decoration: BoxDecoration(
            color: fill,
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _YourThoughtCard extends StatelessWidget {
  final int index;
  final bool viewing;

  const _YourThoughtCard({required this.index, this.viewing = false});

  @override
  Widget build(BuildContext context) {
    final t = _yourThoughts[index];
    return _YouCardShell(
      key: ValueKey('your-thought-${t.id}'),
      ring: t.audience == _Audience.close ? _Ring.close : _Ring.friends,
      kind: t.audience == _Audience.picked
          ? 'Thought · ${_picked.length} picked'
          : 'Thought',
      text: t.thought.text,
      meta: '${_ago(t.thought.age)}${index == 0 ? ' · on the orbit now' : ''}',
      onTap: () => _openThought(context, 'you', index),
      below: viewing ? null : _YourThoughtStats(id: t.id),
    );
  }
}

/// Stand where they stand: what a Close friend, a friend, or a friend of a
/// friend sees of your page.
class _ViewAsSheet extends StatelessWidget {
  final List<_YouCard> cards;

  const _ViewAsSheet({required this.cards});

  @override
  Widget build(BuildContext context) {
    int sees(_Ring r) =>
        cards.where((c) => !c.picked && c.ring.index >= r.index).length;
    return Padding(
      padding: _sheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'View your page as…',
            style: TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final r in _Ring.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                key: ValueKey('view-as-${r.name}'),
                onTap: () => Navigator.of(context).pop(r),
                child: _Edged(
                  color: r.color,
                  fill: const Color(0x0DFFFFFF),
                  minHeight: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.one[0].toUpperCase() + r.one.substring(1),
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        'sees ${sees(r)} of ${cards.length}',
                        style: const TextStyle(color: _muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---- The rings, drawn in 3D: a world tilted a little toward you, a camera
// above and in front of it looking at your photo.

class _Vec {
  final double x, y, z;

  const _Vec(this.x, this.y, this.z);

  _Vec operator -(_Vec o) => _Vec(x - o.x, y - o.y, z - o.z);
  double dot(_Vec o) => x * o.x + y * o.y + z * o.z;
  _Vec cross(_Vec o) =>
      _Vec(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  _Vec get unit {
    final l = math.sqrt(dot(this));
    return _Vec(x / l, y / l, z / l);
  }
}

/// The world tilts 0.12 rad toward you, like the rest of the orbit.
_Vec _tilt(_Vec p) {
  const c = 0.99281, s = 0.11971;
  return _Vec(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

class _Camera {
  final _Vec eye;
  final _Vec right, up, forward;
  final Offset center;
  final double focal;

  factory _Camera(double frame, Size size) {
    final eye = _Vec(0, frame * 0.55, frame);
    final forward = (const _Vec(0, 0, 0) - eye).unit;
    final right = forward.cross(const _Vec(0, 1, 0)).unit;
    return _Camera._(
      eye,
      right,
      right.cross(forward),
      forward,
      Offset(size.width / 2, size.height / 2 - 8),
      size.height * 2.5,
    );
  }

  const _Camera._(
    this.eye,
    this.right,
    this.up,
    this.forward,
    this.center,
    this.focal,
  );

  /// Where a world point lands on screen, and its depth.
  (Offset, double) project(_Vec world) {
    final d = _tilt(world) - eye;
    final z = d.dot(forward);
    return (
      center + Offset(d.dot(right) / z * focal, -d.dot(up) / z * focal),
      z,
    );
  }

  /// Screen pixels per world unit at a point.
  double scale(_Vec world) => focal / project(world).$2;
}

class _Dot {
  final _Ring ring;
  final double angle;

  /// Still flying out from your photo, 0 → 1, or null once on its ring.
  final double? arriving;
  final bool seen;

  const _Dot(this.ring, this.angle, this.arriving, {required this.seen});
}

class _RingsPainter extends CustomPainter {
  final _Camera camera;
  final double spin;
  final bool Function(_Ring) lit;
  final bool Function(_Ring) dark;
  final _Ring? fill;
  final _Ring? pulse;
  final double pulseT;
  final List<_Dot> dots;

  _RingsPainter({
    required this.camera,
    required this.spin,
    required this.lit,
    required this.dark,
    required this.fill,
    required this.pulse,
    required this.pulseT,
    required this.dots,
  });

  /// The innermost ring under a tap: rings nest, so it is the one you see
  /// there.
  static _Ring? ringAt(Offset at, Size size, double frame) {
    final camera = _Camera(frame, size);
    final d = (at - camera.center).distance;
    for (final r in _Ring.values) {
      if (d <= r.radius * camera.scale(const _Vec(0, 0, 0))) return r;
    }
    return null;
  }

  static final List<Offset> _stars = () {
    final rnd = math.Random(7);
    return [
      for (var i = 0; i < 90; i++) Offset(rnd.nextDouble(), rnd.nextDouble()),
    ];
  }();

  _Vec _onRing(double r, double a) => _Vec(math.cos(a) * r, 0, math.sin(a) * r);

  @override
  void paint(Canvas canvas, Size size) {
    final starPaint = Paint()..color = const Color(0x669AA59F);
    for (final s in _stars) {
      canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height), 0.8, starPaint);
    }
    final perUnit = camera.scale(const _Vec(0, 0, 0));
    for (final r in _Ring.values) {
      final glow = r == pulse ? math.sin(math.min(1, pulseT) * math.pi) : 0.0;
      final a = (r == fill ? 0.05 : 0.0) + glow * 0.16;
      if (a > 0) {
        canvas.drawCircle(
          camera.center,
          r.radius * perUnit,
          Paint()..color = r.color.withValues(alpha: a),
        );
      }
    }
    for (final r in _Ring.values) {
      final opacity = dark(r) ? 0.08 : lit(r) ? 0.95 : 0.35;
      final paint = Paint()
        ..color = r.color.withValues(alpha: opacity)
        ..strokeWidth = lit(r) ? 1.6 : 1.1
        ..style = PaintingStyle.stroke;
      // Dashes ride the ring as it turns.
      final dashes = (2 * math.pi * r.radius / 0.22).round();
      final step = 2 * math.pi / dashes;
      for (var i = 0; i < dashes; i++) {
        final from = i * step + spin;
        final path = Path();
        for (var k = 0; k <= 3; k++) {
          final (p, _) = camera.project(_onRing(r.radius, from + step * 0.55 * k / 3));
          k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
    for (final d in dots) {
      var world = _onRing(d.ring.radius, d.angle + spin);
      if (d.arriving case final t?) {
        final k = Curves.easeOutCubic.transform(t);
        world = _Vec(world.x * k, 0, world.z * k);
      }
      final (p, z) = camera.project(world);
      final size = 0.2 * camera.focal / z;
      final opacity = !d.seen || dark(d.ring) ? 0.08 : lit(d.ring) ? 1.0 : 0.45;
      canvas.drawCircle(
        p,
        size,
        Paint()
          ..shader = RadialGradient(
            colors: [
              d.ring.color.withValues(alpha: opacity),
              d.ring.color.withValues(alpha: opacity * 0.5),
              d.ring.color.withValues(alpha: 0),
            ],
            stops: const [0, 0.25, 1],
          ).createShader(Rect.fromCircle(center: p, radius: size)),
      );
    }
    for (final r in _Ring.values) {
      final (p, _) = camera.project(_Vec(0, 0, -r.radius));
      final opacity = dark(r) ? 0.15 : lit(r) ? 1.0 : 0.5;
      final text = TextPainter(
        text: TextSpan(
          text: r.label,
          style: TextStyle(
            color: r.color.withValues(alpha: opacity),
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            shadows: const [Shadow(blurRadius: 6)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, p - Offset(text.width / 2, 19));
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => true;
}

/// Under your own thought: reactions as counts, and how many wrote to you.
/// Never who viewed it, never what they wrote.
class _YourThoughtStats extends StatelessWidget {
  final int id;

  const _YourThoughtStats({required this.id});

  @override
  Widget build(BuildContext context) {
    final reactions = _reactionCounts(id).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final wrote = _wroteAbout(id);
    if (reactions.isEmpty && wrote.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          for (final e in reactions.take(3))
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                '${e.key} ${e.value}',
                style: const TextStyle(color: _chatSecondary, fontSize: 13.5),
              ),
            ),
          const Spacer(),
          if (wrote.isNotEmpty)
            GestureDetector(
              key: ValueKey('wrote-$id'),
              onTap: () => _openSheet(context, _WroteSheet(id: id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${wrote.length} wrote  ›',
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Who wrote to you about one of your thoughts; each opens your chat.
class _WroteSheet extends StatelessWidget {
  final int id;

  const _WroteSheet({required this.id});

  @override
  Widget build(BuildContext context) {
    final wrote = _wroteAbout(id);
    return Padding(
      padding: _sheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            wrote.length == 1 ? '1 wrote to you' : '${wrote.length} wrote to you',
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text('Replies are in your chats.', style: _soft),
          const SizedBox(height: 8),
          for (final name in wrote)
            ListTile(
              key: ValueKey('wrote-row-$name'),
              contentPadding: EdgeInsets.zero,
              leading: _personPhoto(name, 40),
              title: Text(name, style: const TextStyle(color: _ink)),
              trailing: const Icon(Icons.chevron_right, color: _muted),
              onTap: () {
                Navigator.of(context).pop();
                _openDm(context, name);
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The composer.
// ---------------------------------------------------------------------------

class _ComposerSheet extends StatefulWidget {
  const _ComposerSheet();

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  final TextEditingController _text = TextEditingController();
  late _Audience _audience = _lastAudience;

  /// Null while writing; then Sharing…, then Shared.
  String? _status;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final text = _text.text.trim();
    if (text.isEmpty || _audienceSize(_audience) == 0) return;
    HapticFeedback.mediumImpact();
    setState(() => _status = 'Sharing…');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _shareThought(text, _audience);
    setState(() => _status = 'Shared');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickPeople() async {
    await _openSheet(context, const _PickPeopleSheet());
    if (mounted) setState(() => _audience = _Audience.picked);
  }

  @override
  Widget build(BuildContext context) {
    final n = _audienceSize(_audience);
    final ready = _text.text.trim().isNotEmpty && n > 0 && _status == null;
    Widget choice(_Audience a, String label) => _Chip(
      label,
      key: ValueKey('audience-${a.name}'),
      on: _audience == a,
      onTap: a == _Audience.picked
          ? _pickPeople
          : () => setState(() => _audience = a),
    );
    return Padding(
      padding: _sheetPadding(context),
      child: Column(
        key: const ValueKey('composer'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('composer-field'),
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(color: _ink, fontSize: 17),
            decoration: const InputDecoration(
              hintText: 'What’s on your mind?',
              hintStyle: TextStyle(color: Color(0xFF8A8F98), fontSize: 17),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 8),
          const Text('To', style: _soft),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              choice(_Audience.close, 'Close · ${_closeNames.length}'),
              choice(_Audience.friends, 'Friends · ${_everyone.length}'),
              choice(
                _Audience.picked,
                _picked.isEmpty ? 'Pick people…' : 'Picked · ${_picked.length}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            n == 1 ? '1 person will see this.' : '$n people will see this.',
            key: const ValueKey('audience-count'),
            style: const TextStyle(color: _ink, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'On the orbit for 24 h, then in your Thoughts.',
                  style: _soft,
                ),
              ),
              if (_status case final status?)
                Text(
                  status,
                  key: const ValueKey('share-status'),
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                IconButton.filled(
                  key: const ValueKey('share-send'),
                  tooltip: 'Share',
                  onPressed: ready ? _share : null,
                  style: IconButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: const Color(0xFF04110A),
                    disabledBackgroundColor: const Color(0x331DB954),
                  ),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Who sees it is fixed once shared. To change it, delete and '
            'share again.',
            style: TextStyle(color: Color(0xFF6E7570), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Pick the people a thought goes to.
class _PickPeopleSheet extends StatefulWidget {
  const _PickPeopleSheet();

  @override
  State<_PickPeopleSheet> createState() => _PickPeopleSheetState();
}

class _PickPeopleSheetState extends State<_PickPeopleSheet> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Picked · ${_picked.length}',
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: _accent),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final f in _everyone)
                  CheckboxListTile(
                    key: ValueKey('pick-${f.name}'),
                    value: _picked.contains(f.name),
                    activeColor: _accent,
                    secondary: _personPhoto(f.name, 36),
                    title: Text(f.name, style: const TextStyle(color: _ink)),
                    onChanged: (on) => setState(
                      () => on == true
                          ? _picked.add(f.name)
                          : _picked.remove(f.name),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Close friends.
// ---------------------------------------------------------------------------

class _CloseFriendsPage extends StatelessWidget {
  const _CloseFriendsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _ringTick,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DiveHeader(
                trail: ['Close friends · ${_closeNames.length} of $_closeLimit'],
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Close friends sit on your inner ring and see thoughts you '
                  'share with Close. Nobody is told when you add or remove '
                  'them.',
                  style: _soft,
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final f in _everyone)
                      CheckboxListTile(
                        key: ValueKey('close-${f.name}'),
                        value: _closeNames.contains(f.name),
                        activeColor: _accent,
                        secondary: _personPhoto(f.name, 40),
                        title: Text(
                          f.name,
                          style: const TextStyle(color: _ink),
                        ),
                        onChanged:
                            !_closeNames.contains(f.name) &&
                                _closeNames.length >= _closeLimit
                            ? null
                            : (on) => _setClose(f.name, on == true),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Friends of friends: two separate yeses. Being found is yours to give;
// carrying cards for your friends is a second, separate choice.
// ---------------------------------------------------------------------------

/// Whether friends of your friends can find you, and what you are open to.
bool _findable = true;
final List<String> _yourOpenTo = ['books', 'running partners'];

/// What you are open for, in your own words: what friends of friends read
/// before they knock.
const _seedOpenNote =
    'Always happy to swap book recommendations. Also looking for someone to '
    'run with early on weekends, slowly.';
String _yourOpenNote = _seedOpenNote;
const _openToChoices = [
  'books',
  'running partners',
  'coffee chats',
  'design feedback',
  'career advice',
];

/// Which of your Spaces friends of friends see; the rest stay with friends.
final Map<String, bool> _spaceOpen = {'Books': true, 'Runs': false};

/// Whether you carry your findable friends' cards to your own friends, for
/// whom, and to whom.
bool _carryCards = true;
bool _carryForAll = true;
bool _passToCloseOnly = true;
bool _weeklyCount = false;

/// Your friends who chose to be found, whose cards you carry.
const _carriedForYou = ['sara', 'tarek'];

class _FofSettingsPage extends StatefulWidget {
  const _FofSettingsPage();

  @override
  State<_FofSettingsPage> createState() => _FofSettingsPageState();
}

class _FofSettingsPageState extends State<_FofSettingsPage> {
  late final TextEditingController _note = TextEditingController(
    text: _yourOpenNote,
  )..addListener(() => _yourOpenNote = _note.text);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _set(VoidCallback change) {
    HapticFeedback.selectionClick();
    setState(change);
    _yourTick.value++;
  }

  Widget _switch(String key, String title, bool value, ValueChanged<bool> on) =>
      SwitchListTile(
        key: ValueKey(key),
        contentPadding: EdgeInsets.zero,
        activeThumbColor: _accent,
        title: Text(
          title,
          style: const TextStyle(color: _ink, fontSize: 15.5),
        ),
        value: value,
        onChanged: (v) => _set(() => on(v)),
      );

  Widget _pair(
    String label,
    String a,
    String b, {
    required bool first,
    required ValueChanged<bool> on,
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: enabled ? _ink : _muted, fontSize: 14.5),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            _Chip(
              a,
              key: ValueKey('$label-$a'),
              on: first,
              onTap: enabled ? () => _set(() => on(true)) : null,
            ),
            _Chip(
              b,
              key: ValueKey('$label-$b'),
              on: !first,
              onTap: enabled ? () => _set(() => on(false)) : null,
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final carried = [
      for (final f in _carriedForYou)
        if (_isFriend(f)) f,
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DiveHeader(trail: ['Friends of friends']),
            Expanded(
              child: ListView(
                key: const ValueKey('fof-settings'),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  _switch(
                    'findable-switch',
                    'Let friends’ friends find you',
                    _findable,
                    (v) => _findable = v,
                  ),
                  Opacity(
                    opacity: _findable ? 1 : 0.4,
                    child: IgnorePointer(
                      ignoring: !_findable,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          const Text(
                            'What you’re open for, in your words',
                            style: _soft,
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            key: const ValueKey('your-open-note'),
                            controller: _note,
                            minLines: 3,
                            maxLines: 6,
                            maxLength: 300,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 15,
                              height: 1.4,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'What you’d like to talk about, help with '
                                  'or find',
                              hintStyle: const TextStyle(
                                color: Color(0xFF8A8F98),
                              ),
                              counterStyle: _soft,
                              filled: true,
                              fillColor: const Color(0x0FFFFFFF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text('Open topics', style: _soft),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final t in _yourOpenTo)
                                _Chip(
                                  t,
                                  on: true,
                                  onTap: () => _set(() => _yourOpenTo.remove(t)),
                                ),
                              for (final t in _openToChoices)
                                if (!_yourOpenTo.contains(t))
                                  _Chip(
                                    '+ $t',
                                    onTap: () => _set(() => _yourOpenTo.add(t)),
                                  ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text('What they see', style: _soft),
                          for (final title in _spaceOpen.keys)
                            _pair(
                              title,
                              'Friends of friends',
                              'Friends only',
                              first: _spaceOpen[title]!,
                              on: (v) => _spaceOpen[title] = v,
                            ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Thoughts',
                                    style: TextStyle(
                                      color: _ink,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ),
                                Text('Friends only, always', style: _soft),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Reaching people through you',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _switch(
                    'carry-switch',
                    'Let my friends reach people through me',
                    _carryCards,
                    (v) => _carryCards = v,
                  ),
                  _pair(
                    'Carry cards for',
                    'All friends',
                    'Pick',
                    first: _carryForAll,
                    on: (v) => _carryForAll = v,
                    enabled: _carryCards,
                  ),
                  _pair(
                    'Pass them to',
                    'Close only',
                    'All friends',
                    first: _passToCloseOnly,
                    on: (v) => _passToCloseOnly = v,
                    enabled: _carryCards,
                  ),
                  if (_carryCards && carried.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'You carry cards for: ${carried.join(', ')}',
                        style: _soft,
                      ),
                    ),
                  _switch(
                    'weekly-switch',
                    'Weekly count of who reached out via you',
                    _weeklyCount,
                    (v) => _weeklyCount = v,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Every switch works at once. Turning one off tells nobody.',
                    style: _soft,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
