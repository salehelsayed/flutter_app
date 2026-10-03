part of 'orbit_depth_prototype_screen.dart';

// Spaces: the things people keep doing (books they read, a challenge they
// are on, movies they watched), each a small world you can dive into from a
// person, with the same tilted orbit, turning and front card as the main
// Orbit. Fake data, like the rest of the prototype.

enum _SpaceKind { thoughts, books, movies, challenge, add }

class _SpaceItem {
  final String title;
  final String byline;
  final Color color;
  final int rating;
  final String status;
  final String note;
  final int comments;

  const _SpaceItem(
    this.title,
    this.byline,
    this.color, {
    required this.rating,
    required this.status,
    required this.note,
    required this.comments,
  });
}

enum _DayState { done, missed, today, upcoming }

class _ChallengeDay {
  final String label;
  final _DayState state;
  final String detail;
  final int cheers;

  const _ChallengeDay(this.label, this.state, this.detail, {this.cheers = 0});
}

class _Space {
  final String title;
  final _SpaceKind kind;
  final IconData icon;
  final Color hue;
  final List<_SpaceItem> items;
  final String goal;
  final List<_ChallengeDay> days;
  final List<_PastThought> thoughts;

  const _Space(
    this.title,
    this.kind,
    this.icon,
    this.hue, {
    this.items = const [],
    this.goal = '',
    this.days = const [],
    this.thoughts = const [],
  });

  int get today => days.indexWhere((d) => d.state == _DayState.today);
  int get done => days.where((d) => d.state == _DayState.done).length;
}

const _laylaBooks = _Space(
  'Books',
  _SpaceKind.books,
  Icons.menu_book_outlined,
  Color(0xFFE6B566),
  items: [
    _SpaceItem(
      'The Alchemist',
      'Paulo Coelho',
      Color(0xFF8A3B2E),
      rating: 0,
      status: 'Reading now',
      note: 'a third in. slow start but it is growing on me',
      comments: 4,
    ),
    _SpaceItem(
      'Men Without Women',
      'Haruki Murakami',
      Color(0xFF2E4A6B),
      rating: 4,
      status: 'Finished in September',
      note: 'the last story stayed with me for days',
      comments: 6,
    ),
    _SpaceItem(
      'Season of Migration to the North',
      'Tayeb Salih',
      Color(0xFF3F5B3A),
      rating: 5,
      status: 'Finished in August',
      note: 'everyone should read this once. slowly.',
      comments: 12,
    ),
    _SpaceItem(
      'Atomic Habits',
      'James Clear',
      Color(0xFFC9B79C),
      rating: 3,
      status: 'Finished in July',
      note: 'useful, could have been half the length',
      comments: 9,
    ),
    _SpaceItem(
      'The Midnight Library',
      'Matt Haig',
      Color(0xFF1F2B4D),
      rating: 4,
      status: 'Finished in June',
      note: 'read it in two nights',
      comments: 3,
    ),
    _SpaceItem(
      'Sapiens',
      'Yuval Noah Harari',
      Color(0xFF9C3D3D),
      rating: 4,
      status: 'Finished in May',
      note: 'changed how I think about money',
      comments: 5,
    ),
  ],
);

const _laylaMovies = _Space(
  'Movies',
  _SpaceKind.movies,
  Icons.movie_outlined,
  Color(0xFF8FB3E8),
  items: [
    _SpaceItem(
      'Past Lives',
      '2023',
      Color(0xFF3A4E6B),
      rating: 5,
      status: 'Watched last night',
      note: 'quiet and devastating. bring tissues',
      comments: 7,
    ),
    _SpaceItem(
      'Perfect Days',
      '2023',
      Color(0xFF4F6B5A),
      rating: 5,
      status: 'Watched in September',
      note: 'I want to live like the main character',
      comments: 3,
    ),
    _SpaceItem(
      'Capernaum',
      '2018',
      Color(0xFF7A5A3A),
      rating: 5,
      status: 'Watched in August',
      note: 'hard to watch, impossible to forget',
      comments: 9,
    ),
    _SpaceItem(
      'Dune: Part Two',
      '2024',
      Color(0xFFB07A3C),
      rating: 4,
      status: 'Watched in March',
      note: 'the sound in the cinema!',
      comments: 11,
    ),
    _SpaceItem(
      'Oppenheimer',
      '2023',
      Color(0xFF3B3B3B),
      rating: 3,
      status: 'Watched in July',
      note: 'too long for me',
      comments: 4,
    ),
  ],
);

const _omarPlank = _Space(
  'Plank challenge',
  _SpaceKind.challenge,
  Icons.fitness_center,
  Color(0xFF1DB954),
  goal: 'Plank for 1 minute, every day for a week',
  days: [
    _ChallengeDay('Mon', _DayState.done, 'held 1:00', cheers: 3),
    _ChallengeDay('Tue', _DayState.done, 'held 1:04', cheers: 5),
    _ChallengeDay('Wed', _DayState.done, 'held 0:58 · so close', cheers: 2),
    _ChallengeDay('Thu', _DayState.done, 'held 1:10 · new best', cheers: 7),
    _ChallengeDay('Fri', _DayState.today, 'not yet today'),
    _ChallengeDay('Sat', _DayState.upcoming, 'coming up'),
    _ChallengeDay('Sun', _DayState.upcoming, 'coming up'),
  ],
);

const _omarBooks = _Space(
  'Books',
  _SpaceKind.books,
  Icons.menu_book_outlined,
  Color(0xFFE6B566),
  items: [
    _SpaceItem(
      'Deep Work',
      'Cal Newport',
      Color(0xFF263238),
      rating: 0,
      status: 'Reading now',
      note: 'phone in the other room. it actually works',
      comments: 2,
    ),
    _SpaceItem(
      'The Prophet',
      'Kahlil Gibran',
      Color(0xFF6B4E2E),
      rating: 5,
      status: 'Finished in August',
      note: 'reread it every year',
      comments: 6,
    ),
    _SpaceItem(
      "Can't Hurt Me",
      'David Goggins',
      Color(0xFF1C1C1C),
      rating: 4,
      status: 'Finished in June',
      note: 'why I started the plank thing',
      comments: 4,
    ),
  ],
);

const _nourMovies = _Space(
  'Movies',
  _SpaceKind.movies,
  Icons.movie_outlined,
  Color(0xFF8FB3E8),
  items: [
    _SpaceItem(
      'Wadjda',
      '2012',
      Color(0xFF2F6B5E),
      rating: 5,
      status: 'Watched on Sunday',
      note: 'the bicycle scene got me',
      comments: 5,
    ),
    _SpaceItem(
      'Inside Out 2',
      '2024',
      Color(0xFF6B3F8A),
      rating: 4,
      status: 'Watched in July',
      note: 'anxiety is too real',
      comments: 8,
    ),
    _SpaceItem(
      'Barbie',
      '2023',
      Color(0xFFC75B8E),
      rating: 3,
      status: 'Watched last summer',
      note: 'fun, the songs are stuck in my head',
      comments: 3,
    ),
  ],
);

const _yourBooks = _Space(
  'Books',
  _SpaceKind.books,
  Icons.menu_book_outlined,
  Color(0xFFE6B566),
  items: [
    _SpaceItem(
      'Thinking, Fast and Slow',
      'Daniel Kahneman',
      Color(0xFF2E3A4F),
      rating: 0,
      status: 'Reading now',
      note: 'chapter 12. my brain hurts in a good way',
      comments: 3,
    ),
    _SpaceItem(
      'The Pragmatic Programmer',
      'Hunt & Thomas',
      Color(0xFF5A3A2E),
      rating: 4,
      status: 'Finished in August',
      note: 'should have read this years ago',
      comments: 2,
    ),
  ],
);

const _yourRun = _Space(
  'Run 5k',
  _SpaceKind.challenge,
  Icons.directions_run,
  Color(0xFF1DB954),
  goal: 'Run 5k three times this week',
  days: [
    _ChallengeDay('Mon', _DayState.done, '5.1 km · 29:40', cheers: 4),
    _ChallengeDay('Wed', _DayState.done, '5.0 km · 28:55', cheers: 6),
    _ChallengeDay('Fri', _DayState.today, 'planned for tonight'),
  ],
);

const _newSpace = _Space(
  'New space',
  _SpaceKind.add,
  Icons.add,
  Color(0xFF9AA59F),
);

const _spacesByOwner = <String, List<_Space>>{
  'layla': [_laylaBooks, _laylaMovies],
  'omar': [_omarPlank, _omarBooks],
  'nour': [_nourMovies],
  'you': [_yourBooks, _yourRun, _newSpace],
};

/// A thought someone shared. The newest one is the one on the orbit right
/// now; older ones stay in their world. [space] links a thought that was
/// posted from one of their Spaces back to it.
class _PastThought {
  final String text;
  final _ThoughtKind kind;
  final String? more;
  final int seconds;
  final String? photo;
  final String age;
  final int comments;
  final String? space;
  final bool live;

  const _PastThought(
    this.text, {
    required this.age,
    this.kind = _ThoughtKind.text,
    this.more,
    this.seconds = 0,
    this.photo,
    this.comments = 0,
    this.space,
    this.live = false,
  });
}

const _olderThoughts = <String, List<_PastThought>>{
  'omar': [
    _PastThought(
      'Thursday plank: 1:10, new best',
      age: '1 d',
      comments: 7,
      space: 'Plank challenge',
    ),
    _PastThought(
      'the bus was 40 minutes late. again.',
      age: '3 d',
      kind: _ThoughtKind.voice,
      seconds: 18,
      comments: 4,
    ),
    _PastThought('anyone have notes for chapter 4?', age: '5 d', comments: 2),
    _PastThought(
      'rereading The Prophet. every year.',
      age: '2 w',
      comments: 6,
      space: 'Books',
    ),
  ],
  'layla': [
    _PastThought(
      'who wants to see Past Lives with me?',
      age: '4 d',
      comments: 5,
      space: 'Movies',
    ),
    _PastThought(
      'finished Men Without Women. that last story.',
      age: '3 w',
      comments: 6,
      space: 'Books',
    ),
  ],
  'nour': [
    _PastThought(
      'wadjda tonight, anyone?',
      age: '6 d',
      comments: 3,
      space: 'Movies',
    ),
  ],
  'you': [
    _PastThought(
      'ran 5k in 28:55. slowly getting there',
      age: '2 d',
      comments: 6,
      space: 'Run 5k',
    ),
    _PastThought(
      'chapter 12 of Thinking, Fast and Slow. my brain hurts',
      age: '4 d',
      comments: 3,
      space: 'Books',
    ),
  ],
};

/// Everything someone shared: the live thought first, then older ones.
List<_PastThought> _thoughtsOf(String owner) {
  final thoughts = <_PastThought>[];
  for (final f in _friends) {
    final thought = f.thought;
    if (f.name != owner || thought == null) continue;
    final d = _detailFor(f);
    thoughts.add(
      _PastThought(
        thought,
        age: d.age,
        kind: d.kind,
        more: d.more,
        seconds: d.seconds,
        photo: d.photo,
        comments: d.comments,
        live: true,
      ),
    );
  }
  thoughts.addAll(_olderThoughts[owner] ?? const []);
  return thoughts;
}

/// A person's Spaces, with their Thoughts always first.
List<_Space> _spacesFor(String owner) {
  final thoughts = _thoughtsOf(owner);
  return [
    if (thoughts.isNotEmpty)
      _Space(
        'Thoughts',
        _SpaceKind.thoughts,
        Icons.chat_bubble_outline,
        _accent,
        thoughts: thoughts,
      ),
    ...?_spacesByOwner[owner],
  ];
}

void _openSpace(BuildContext context, String owner, String title) {
  for (final space in _spacesFor(owner)) {
    if (space.title == title) {
      HapticFeedback.selectionClick();
      Navigator.of(
        context,
      ).push(_diveRoute(_SpaceScreen(owner: owner, space: space)));
      return;
    }
  }
}

/// Friends who comment on items, cycled to fill each thread.
const _commenters = [
  ('sara', 'adding this to my list'),
  ('omar', 'the ending though!'),
  ('nour', 'can I borrow it after you?'),
  ('tarek', 'not my thing but your notes make me want to try'),
  ('layla', 'agree with every word'),
];

/// A person's picture: their photo, or the app's default ring avatar.
Widget _personPhoto(String owner, double size) {
  final peerId = _ringAvatarPeers[owner];
  if (peerId != null) return RingAvatar(peerId: peerId, size: size);
  return ClipOval(
    child: Image(
      image: _photo(owner),
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    ),
  );
}

// ---------------------------------------------------------------------------
// Navigation: every level is entered by "diving" in and left by backing out.
// ---------------------------------------------------------------------------

/// The new level grows out of the distance; the level you leave rushes past
/// the camera and fades, so it feels like flying into it.
Route<void> _diveRoute(Widget page, {bool animateIn = true}) {
  return PageRouteBuilder<void>(
    transitionDuration: animateIn
        ? const Duration(milliseconds: 520)
        : Duration.zero,
    reverseTransitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (context, animation, secondary) => page,
    transitionsBuilder: (context, animation, secondary, child) {
      final arrive = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final leave = CurvedAnimation(
        parent: secondary,
        curve: Curves.easeInOutCubic,
      );
      return AnimatedBuilder(
        animation: Listenable.merge([arrive, leave]),
        child: child,
        builder: (context, child) {
          final a = arrive.value;
          final b = leave.value;
          return Opacity(
            opacity: (a * (1 - b)).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: _lerp(0.6, 1, a) * _lerp(1, 1.6, b),
              child: child,
            ),
          );
        },
      );
    },
  );
}

class _DiveHeader extends StatelessWidget {
  final List<String> trail;

  const _DiveHeader({required this.trail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: _ink),
          ),
          Expanded(
            child: Text(
              trail.join('  ›  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A person's world: their Spaces orbit them.
// ---------------------------------------------------------------------------

class _WorldScreen extends StatelessWidget {
  final String owner;

  const _WorldScreen({required this.owner});

  void _dive(BuildContext context, _Space space) {
    if (space.kind == _SpaceKind.add) {
      _openNewSpaceSheet(context);
      return;
    }
    HapticFeedback.selectionClick();
    Navigator.of(
      context,
    ).push(_diveRoute(_SpaceScreen(owner: owner, space: space)));
  }

  @override
  Widget build(BuildContext context) {
    final spaces = _spacesFor(owner);
    final title = owner == 'you' ? 'your world' : "$owner's world";
    return Scaffold(
      backgroundColor: _ground,
      body: SafeArea(
        child: Column(
          children: [
            _DiveHeader(trail: [title]),
            Expanded(
              child: spaces.isEmpty
                  ? _EmptyWorld(owner: owner)
                  : _DepthRing(
                      count: spaces.length,
                      itemBase: 58,
                      centerBuilder: (context, size) =>
                          _personPhoto(owner, size),
                      centerColor: _accent,
                      colorOf: (i) => spaces[i].hue,
                      itemBuilder: (context, i, size, highlight) =>
                          KeyedSubtree(
                            key: ValueKey('space-${spaces[i].title}'),
                            child: _SpaceTile(
                              space: spaces[i],
                              size: size,
                              highlight: highlight,
                            ),
                          ),
                      cardBuilder: (context, i, maxHeight) => _SpaceCard(
                        owner: owner,
                        space: spaces[i],
                        onDive: () => _dive(context, spaces[i]),
                      ),
                      onDive: (i) => _dive(context, spaces[i]),
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWorld extends StatelessWidget {
  final String owner;

  const _EmptyWorld({required this.owner});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).maybePop();
      },
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _personPhoto(owner, 96),
            const SizedBox(height: 18),
            Text(
              '$owner has not made a space yet',
              style: const TextStyle(color: _muted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpaceTile extends StatelessWidget {
  final _Space space;
  final double size;
  final double highlight;

  const _SpaceTile({
    required this.space,
    required this.size,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final add = space.kind == _SpaceKind.add;
    return Transform.scale(
      scale: 1 + 0.08 * highlight,
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF111714),
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(
            color: space.hue.withValues(
              alpha: add ? 0.35 : 0.3 + 0.4 * highlight,
            ),
          ),
          boxShadow: [
            const BoxShadow(
              color: Color(0x73000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
            if (highlight > 0.01)
              BoxShadow(
                color: space.hue.withValues(alpha: 0.35 * highlight),
                blurRadius: 22,
              ),
          ],
        ),
        child: Center(
          child: Icon(space.icon, color: space.hue, size: size * 0.44),
        ),
      ),
    );
  }
}

class _SpaceCard extends StatelessWidget {
  final String owner;
  final _Space space;
  final VoidCallback onDive;

  const _SpaceCard({
    required this.owner,
    required this.space,
    required this.onDive,
  });

  String get _subtitle => switch (space.kind) {
    _SpaceKind.thoughts =>
      'Thoughts · ${space.thoughts.length}, newest ${space.thoughts.first.age} ago',
    _SpaceKind.books => 'Reading list · ${space.items.length} books',
    _SpaceKind.movies => 'Watched · ${space.items.length} movies',
    _SpaceKind.challenge =>
      'Challenge · ${space.done} of ${space.days.length} done',
    _SpaceKind.add => 'Start something your friends can follow',
  };

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      onTap: onDive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(space.icon, color: space.hue, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  space.title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_subtitle, style: const TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 14),
          ..._preview(),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'or swipe up',
                  style: TextStyle(color: Color(0xFF66736C), fontSize: 12),
                ),
              ),
              _AccentButton(
                label: space.kind == _SpaceKind.add ? 'Create' : 'Dive in',
                onTap: onDive,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _preview() {
    switch (space.kind) {
      case _SpaceKind.thoughts:
        final latest = space.thoughts.first;
        return [
          Row(
            children: [
              Icon(
                switch (latest.kind) {
                  _ThoughtKind.voice => Icons.graphic_eq,
                  _ThoughtKind.photo => Icons.image_outlined,
                  _ThoughtKind.text => Icons.format_quote_rounded,
                },
                size: 18,
                color: _accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  latest.live ? 'On the orbit now' : '${latest.age} ago',
                  style: const TextStyle(color: _muted, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '“${latest.text}”',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _ink, fontSize: 15),
          ),
        ];
      case _SpaceKind.books:
      case _SpaceKind.movies:
        final latest = space.items.first;
        return [
          Row(
            children: [
              for (final item in space.items.take(4))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Cover(
                    item: item,
                    kind: space.kind,
                    width: 40,
                    height: 58,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            space.kind == _SpaceKind.books
                ? '${latest.status}: ${latest.title}'
                : '${latest.status}: ${latest.title}',
            style: const TextStyle(color: _ink, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            '“${latest.note}”',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFB4C0B9), fontSize: 13),
          ),
        ];
      case _SpaceKind.challenge:
        return [
          Text(space.goal, style: const TextStyle(color: _ink, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final day in space.days)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _DayDot(day: day, size: 22),
                ),
            ],
          ),
        ];
      case _SpaceKind.add:
        return const [
          Text(
            'A reading list, a challenge, movies you watched, anything you '
            'keep doing. Your friends dive in like this.',
            style: TextStyle(color: Color(0xFFB4C0B9), fontSize: 13),
          ),
        ];
    }
  }
}

// ---------------------------------------------------------------------------
// Inside a Space.
// ---------------------------------------------------------------------------

class _SpaceScreen extends StatelessWidget {
  final String owner;
  final _Space space;

  const _SpaceScreen({required this.owner, required this.space});

  @override
  Widget build(BuildContext context) {
    final world = owner == 'you' ? 'your world' : owner;
    return Scaffold(
      backgroundColor: _ground,
      body: SafeArea(
        child: Column(
          children: [
            _DiveHeader(trail: [world, space.title]),
            Expanded(
              child: switch (space.kind) {
                _SpaceKind.challenge => _challengeRing(context),
                _SpaceKind.thoughts => _thoughtsRing(context),
                _ => _collectionRing(context),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _collectionRing(BuildContext context) {
    final items = space.items;
    return _DepthRing(
      count: items.length,
      itemBase: 54,
      centerBuilder: (context, size) =>
          _SpaceTile(space: space, size: size * 0.8, highlight: 0),
      centerColor: space.hue,
      colorOf: (i) => items[i].color,
      itemBuilder: (context, i, size, highlight) => Align(
        alignment: Alignment.bottomCenter,
        child: Transform.scale(
          scale: 1 + 0.1 * highlight,
          alignment: Alignment.bottomCenter,
          child: _Cover(
            item: items[i],
            kind: space.kind,
            width: size * 0.72,
            height: size,
          ),
        ),
      ),
      cardBuilder: (context, i, maxHeight) => _ItemCard(
        owner: owner,
        item: items[i],
        kind: space.kind,
        onOpen: () => _openItemSheet(context, owner, items[i], space.kind),
      ),
      onDive: (i) => _openItemSheet(context, owner, items[i], space.kind),
      onBack: () => Navigator.of(context).maybePop(),
    );
  }

  Widget _thoughtsRing(BuildContext context) {
    final thoughts = space.thoughts;
    return _DepthRing(
      count: thoughts.length,
      itemBase: 50,
      centerBuilder: (context, size) => _personPhoto(owner, size),
      centerColor: _accent,
      colorOf: (i) => thoughts[i].live ? _accent : const Color(0xFF6B7A72),
      itemBuilder: (context, i, size, highlight) =>
          _ThoughtTile(thought: thoughts[i], size: size, highlight: highlight),
      cardBuilder: (context, i, maxHeight) => _PastThoughtCard(
        owner: owner,
        thought: thoughts[i],
        onOpenSpace: thoughts[i].space == null
            ? null
            : () => _openSpace(context, owner, thoughts[i].space!),
        onReply: () => _openReplySheet(context, owner, thoughts[i]),
      ),
      onDive: (i) => _openReplySheet(context, owner, thoughts[i]),
      onBack: () => Navigator.of(context).maybePop(),
    );
  }

  Widget _challengeRing(BuildContext context) {
    final days = space.days;
    return _DepthRing(
      count: days.length,
      initialIndex: math.max(0, space.today),
      itemBase: 46,
      centerBuilder: (context, size) =>
          _ChallengeProgress(space: space, size: size),
      centerColor: _accent,
      colorOf: (i) => switch (days[i].state) {
        _DayState.done => _accent,
        _DayState.today => const Color(0xFFE6B566),
        _ => const Color(0xFF3A4741),
      },
      itemBuilder: (context, i, size, highlight) => Transform.scale(
        scale: 1 + 0.08 * highlight,
        alignment: Alignment.bottomCenter,
        child: _DayDot(day: days[i], size: size),
      ),
      cardBuilder: (context, i, maxHeight) =>
          _DayCard(owner: owner, space: space, day: days[i], index: i),
      onBack: () => Navigator.of(context).maybePop(),
    );
  }
}

/// One thought on the Thoughts ring: its photo, or a mark for voice / text.
class _ThoughtTile extends StatelessWidget {
  final _PastThought thought;
  final double size;
  final double highlight;

  const _ThoughtTile({
    required this.thought,
    required this.size,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final photo = thought.photo;
    final color = thought.live ? _accent : const Color(0xFF6B7A72);
    return Transform.scale(
      scale: 1 + 0.08 * highlight,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111714),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.5)),
          boxShadow: [
            const BoxShadow(
              color: Color(0x73000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
            if (highlight > 0.01)
              BoxShadow(
                color: color.withValues(alpha: 0.35 * highlight),
                blurRadius: 22,
              ),
          ],
        ),
        child: photo != null
            ? ClipOval(
                child: Image(
                  image: _photo(photo),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              )
            : Icon(
                thought.kind == _ThoughtKind.voice
                    ? Icons.graphic_eq
                    : Icons.format_quote_rounded,
                color: color,
                size: size * 0.42,
              ),
      ),
    );
  }
}

class _PastThoughtCard extends StatelessWidget {
  final String owner;
  final _PastThought thought;
  final VoidCallback? onOpenSpace;
  final VoidCallback onReply;

  const _PastThoughtCard({
    required this.owner,
    required this.thought,
    required this.onReply,
    this.onOpenSpace,
  });

  @override
  Widget build(BuildContext context) {
    final more = thought.more;
    final photo = thought.photo;
    final space = thought.space;
    final openSpace = onOpenSpace;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            thought.live
                ? '${thought.age} ago · on the orbit now'
                : '${thought.age} ago',
            style: const TextStyle(color: _muted, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Text(
            thought.text,
            style: const TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (more != null) ...[
            const SizedBox(height: 6),
            Text(
              more,
              style: const TextStyle(
                color: Color(0xFFB4C0B9),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
          if (photo != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 130,
                width: double.infinity,
                child: Image(image: _photo(photo), fit: BoxFit.cover),
              ),
            ),
          ],
          if (thought.kind == _ThoughtKind.voice) ...[
            const SizedBox(height: 10),
            _VoicePlayer(seconds: thought.seconds, k: 1),
          ],
          if (space != null && openSpace != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: openSpace,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF161D1A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'from $space  ›',
                  style: const TextStyle(
                    color: Color(0xFFB4C0B9),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.chat_bubble_outline, size: 15, color: _muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${thought.comments} comments',
                  style: const TextStyle(color: _muted, fontSize: 12.5),
                ),
              ),
              _AccentButton(label: 'Reply', onTap: onReply),
            ],
          ),
        ],
      ),
    );
  }
}

void _openReplySheet(BuildContext context, String owner, _PastThought thought) {
  HapticFeedback.selectionClick();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF0B100E),
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _personPhoto(owner, 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '“${thought.text}”',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                style: const TextStyle(color: _ink),
                decoration: InputDecoration(
                  hintText: 'Reply to $owner',
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
          ),
        ),
      ),
    ),
  );
}

/// A book or movie cover, set in type like a real edition.
class _Cover extends StatelessWidget {
  final _SpaceItem item;
  final _SpaceKind kind;
  final double width;
  final double height;

  const _Cover({
    required this.item,
    required this.kind,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final movie = kind == _SpaceKind.movies;
    final light = item.color.computeLuminance() > 0.35;
    final ink = light ? const Color(0xFF2A2420) : const Color(0xFFF5EFE3);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.06),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: movie
              ? [item.color, Color.lerp(item.color, Colors.black, 0.75)!]
              : [
                  Color.lerp(item.color, Colors.white, 0.06)!,
                  Color.lerp(item.color, Colors.black, 0.12)!,
                ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(width * 0.09),
      child: Column(
        mainAxisAlignment: movie
            ? MainAxisAlignment.end
            : MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!movie) Container(height: 0.6, color: ink.withValues(alpha: 0.4)),
          Text(
            item.title,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: ink,
              fontFamily: 'Georgia',
              fontFamilyFallback: const ['Times New Roman', 'serif'],
              fontSize: width * (movie ? 0.15 : 0.13),
              fontWeight: movie ? FontWeight.w700 : FontWeight.w500,
              height: 1.1,
            ),
          ),
          SizedBox(height: movie ? width * 0.05 : 0),
          Text(
            item.byline.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: ink.withValues(alpha: 0.75),
              fontSize: width * 0.065,
              letterSpacing: width * 0.006,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final String owner;
  final _SpaceItem item;
  final _SpaceKind kind;
  final VoidCallback onOpen;

  const _ItemCard({
    required this.owner,
    required this.item,
    required this.kind,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.title,
            style: const TextStyle(
              color: _ink,
              fontFamily: 'Georgia',
              fontFamilyFallback: ['Times New Roman', 'serif'],
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.byline,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatusChip(text: item.status),
              const SizedBox(width: 10),
              if (item.rating > 0) _Stars(rating: item.rating),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _personPhoto(owner, 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '“${item.note}”',
                  style: const TextStyle(
                    color: Color(0xFFDDE3DF),
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.chat_bubble_outline, size: 15, color: _muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${item.comments} comments',
                  style: const TextStyle(color: _muted, fontSize: 12.5),
                ),
              ),
              _AccentButton(label: 'Open', onTap: onOpen),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChallengeProgress extends StatelessWidget {
  final _Space space;
  final double size;

  const _ChallengeProgress({required this.space, required this.size});

  @override
  Widget build(BuildContext context) {
    final progress = space.done / space.days.length;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ProgressPainter(progress),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(space.icon, color: _accent, size: size * 0.24),
              Text(
                '${space.done}/${space.days.length}',
                style: TextStyle(
                  color: _ink,
                  fontSize: size * 0.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  final double progress;

  _ProgressPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(size.width * 0.05);
    canvas.drawOval(rect, Paint()..color = const Color(0xFF0E1311));
    final track = Paint()
      ..color = const Color(0xFF24302B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      track
        ..color = _accent
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) => old.progress != progress;
}

class _DayDot extends StatelessWidget {
  final _ChallengeDay day;
  final double size;

  const _DayDot({required this.day, required this.size});

  @override
  Widget build(BuildContext context) {
    final (fill, border, child) = switch (day.state) {
      _DayState.done => (
        _accent,
        _accent,
        Icon(Icons.check, size: size * 0.55, color: const Color(0xFF03140A)),
      ),
      _DayState.today => (
        const Color(0xFF1C1A10),
        const Color(0xFFE6B566),
        _dayLabel(const Color(0xFFE6B566)),
      ),
      _DayState.missed => (
        const Color(0xFF1A1414),
        const Color(0xFF5A3A3A),
        _dayLabel(const Color(0xFF9A7A7A)),
      ),
      _DayState.upcoming => (
        const Color(0xFF101513),
        const Color(0xFF2E3B35),
        _dayLabel(const Color(0xFF66736C)),
      ),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: size > 30 ? 1.5 : 1),
      ),
      child: Center(child: child),
    );
  }

  Widget _dayLabel(Color color) => Text(
    size > 30 ? day.label : day.label.characters.first,
    style: TextStyle(
      color: color,
      fontSize: size * (size > 30 ? 0.28 : 0.45),
      fontWeight: FontWeight.w600,
    ),
  );
}

class _DayCard extends StatefulWidget {
  final String owner;
  final _Space space;
  final _ChallengeDay day;
  final int index;

  const _DayCard({
    required this.owner,
    required this.space,
    required this.day,
    required this.index,
  });

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _cheered = false;

  @override
  void didUpdateWidget(_DayCard old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _cheered = false;
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final cheers = day.cheers + (_cheered ? 1 : 0);
    final status = switch (day.state) {
      _DayState.done => 'Done',
      _DayState.today => 'Today',
      _DayState.missed => 'Missed',
      _DayState.upcoming => 'Coming up',
    };
    final canCheer =
        day.state == _DayState.done || day.state == _DayState.today;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Day ${widget.index + 1} · ${day.label}',
            style: const TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$status · ${day.detail}',
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Text(
            widget.space.goal,
            style: const TextStyle(color: Color(0xFFB4C0B9), fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (cheers > 0) ...[
                SizedBox(
                  width: 26.0 + 16 * (math.min(cheers, 3) - 1),
                  height: 26,
                  child: Stack(
                    children: [
                      for (var i = 0; i < math.min(cheers, 3); i++)
                        Positioned(
                          left: i * 16.0,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _ground, width: 2),
                            ),
                            child: _personPhoto(
                              const ['sara', 'nour', 'tarek'][i],
                              22,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  cheers == 0
                      ? 'No cheers yet'
                      : cheers == 1
                      ? '1 cheer'
                      : '$cheers cheers',
                  style: const TextStyle(color: _muted, fontSize: 12.5),
                ),
              ),
              if (canCheer)
                _AccentButton(
                  label: _cheered ? 'Cheered' : 'Cheer',
                  filled: !_cheered,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _cheered = !_cheered);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces.
// ---------------------------------------------------------------------------

class _CardShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _CardShell({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1311),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1F2A25)),
        ),
        child: child,
      ),
    );
  }
}

class _AccentButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const _AccentButton({
    required this.label,
    required this.onTap,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? _accent : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _accent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? const Color(0xFF03140A) : _accent,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;

  const _StatusChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final now = text.startsWith('Reading') || text.startsWith('Watched last');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: now ? const Color(0xFF12301F) : const Color(0xFF161D1A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: now ? const Color(0xFF5BE38A) : _muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  final int rating;

  const _Stars({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 15,
            color: i < rating
                ? const Color(0xFFE6B566)
                : const Color(0xFF3A4741),
          ),
      ],
    );
  }
}

void _openItemSheet(
  BuildContext context,
  String owner,
  _SpaceItem item,
  _SpaceKind kind,
) {
  HapticFeedback.selectionClick();
  final thread = [
    for (var i = 0; i < math.min(item.comments, 4); i++)
      _commenters[(item.title.length + i) % _commenters.length],
  ].where((c) => c.$1 != owner).toList();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF0B100E),
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Cover(item: item, kind: kind, width: 78, height: 112),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: _ink,
                            fontFamily: 'Georgia',
                            fontFamilyFallback: ['Times New Roman', 'serif'],
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.byline,
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        _StatusChip(text: item.status),
                        if (item.rating > 0) ...[
                          const SizedBox(height: 8),
                          _Stars(rating: item.rating),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _personPhoto(owner, 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '“${item.note}”',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                '${item.comments} comments',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 10),
              for (final (name, text) in thread)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _personPhoto(name, 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '$name  ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(text: text),
                            ],
                          ),
                          style: const TextStyle(
                            color: Color(0xFFDDE3DF),
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              TextField(
                style: const TextStyle(color: _ink),
                decoration: InputDecoration(
                  hintText: 'Say something about ${item.title}',
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
          ),
        ),
      ),
    ),
  );
}

void _openNewSpaceSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  const templates = [
    (
      Icons.collections_bookmark_outlined,
      'Collection',
      'Books, movies, places, recipes. Things you add over time.',
    ),
    (
      Icons.flag_outlined,
      'Challenge',
      'A goal with a schedule. Friends see your progress and cheer.',
    ),
    (
      Icons.edit_note,
      'Journal',
      'Free-form entries for anything else you keep doing.',
    ),
  ];
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF0B100E),
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New space',
              style: TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            for (final (icon, title, description) in templates)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1311),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1F2A25)),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: _accent, size: 24),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                description,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// The shared 3D ring: the same tilted orbit, turning, snapping, platforms and
// front card as the main Orbit, for any set of things.
// ---------------------------------------------------------------------------

class _RingSeat {
  final int index;
  final Offset ringPoint;
  final Offset center;
  final double size;
  final double depth;
  final double opacity;
  final Size platform;

  const _RingSeat(
    this.index,
    this.ringPoint,
    this.center,
    this.size,
    this.depth,
    this.opacity,
    this.platform,
  );
}

class _DepthRing extends StatefulWidget {
  final int count;
  final int initialIndex;
  final double itemBase;
  final Widget Function(BuildContext context, double size) centerBuilder;
  final Color centerColor;
  final Widget Function(
    BuildContext context,
    int index,
    double size,
    double highlight,
  )
  itemBuilder;
  final Widget Function(BuildContext context, int index, double maxHeight)
  cardBuilder;
  final Color Function(int index) colorOf;
  final ValueChanged<int>? onDive;
  final VoidCallback onBack;

  const _DepthRing({
    required this.count,
    required this.itemBase,
    required this.centerBuilder,
    required this.centerColor,
    required this.itemBuilder,
    required this.cardBuilder,
    required this.colorOf,
    required this.onBack,
    this.onDive,
    this.initialIndex = 0,
  });

  @override
  State<_DepthRing> createState() => _DepthRingState();
}

class _DepthRingState extends State<_DepthRing> with TickerProviderStateMixin {
  static const _rotSpring = SpringDescription(
    mass: 1,
    stiffness: 90,
    damping: 15,
  );
  static const _pullSpring = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 26,
  );

  late final AnimationController _rot = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _duck = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 260),
  );

  /// Vertical pull in pixels while dragging (up is positive): the ring leans
  /// in as you pull up towards diving, and back as you pull down to leave.
  late final AnimationController _pull = AnimationController.unbounded(
    vsync: this,
  );

  bool _reduceMotion = false;
  _Axis? _axis;
  Offset _travel = Offset.zero;
  double _rotAtStart = 0;
  double _k = 1;

  double get _step => 2 * math.pi / widget.count;
  double _angle(int i) => -math.pi / 2 + i * _step;

  @override
  void initState() {
    super.initState();
    _rot.value = math.pi / 2 - _angle(widget.initialIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    _rot.dispose();
    _duck.dispose();
    _pull.dispose();
    super.dispose();
  }

  int get _front {
    var best = 0;
    var bestDepth = -2.0;
    for (var i = 0; i < widget.count; i++) {
      final d = math.sin(_angle(i) + _rot.value);
      if (d > bestDepth) {
        bestDepth = d;
        best = i;
      }
    }
    return best;
  }

  double _snap(double predicted) {
    var best = predicted;
    var gap = double.infinity;
    for (var i = 0; i < widget.count; i++) {
      final base = math.pi / 2 - _angle(i);
      final turns = ((predicted - base) / (2 * math.pi)).round();
      final candidate = base + turns * 2 * math.pi;
      if ((candidate - predicted).abs() < gap) {
        gap = (candidate - predicted).abs();
        best = candidate;
      }
    }
    return best;
  }

  void _setTurning(bool turning) {
    if (_reduceMotion) {
      _duck.value = turning ? 1 : 0;
    } else if (turning) {
      _duck.forward();
    } else {
      _duck.reverse();
    }
  }

  void _springTo(
    AnimationController c,
    double target,
    double velocity,
    SpringDescription spring,
  ) {
    if (_reduceMotion) {
      c.value = target;
    } else {
      c.animateWith(SpringSimulation(spring, c.value, target, velocity));
    }
  }

  void _onPanStart(DragStartDetails details) {
    _axis = null;
    _travel = Offset.zero;
    _rotAtStart = _rot.value;
    _rot.stop();
    _pull.stop();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_axis == null) {
      _travel += details.delta;
      if (_travel.distance < 4) return;
      _axis = _travel.dx.abs() > _travel.dy.abs()
          ? _Axis.horizontal
          : _Axis.vertical;
    }
    if (_axis == _Axis.horizontal) {
      _setTurning(true);
      _rot.value -= details.delta.dx / (128 * _k);
    } else {
      _pull.value = (_pull.value - details.delta.dy).clamp(-220.0, 220.0);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    _axis ??= velocity.dx.abs() > velocity.dy.abs()
        ? _Axis.horizontal
        : _Axis.vertical;
    if (_axis == _Axis.horizontal) {
      _setTurning(false);
      final spin = _reduceMotion ? 0.0 : -velocity.dx / (128 * _k);
      var target = _snap(_rot.value + (spin * 0.25).clamp(-math.pi, math.pi));
      final from = _snap(_rotAtStart);
      final dragged = _rot.value - _rotAtStart;
      if ((target - from).abs() < 1e-6 && dragged.abs() > _step * 0.2) {
        target = _snap(from + dragged.sign * _step);
      }
      _springTo(_rot, target, spin, _rotSpring);
      return;
    }
    final up = -velocity.dy;
    final pull = _pull.value;
    _springTo(_pull, 0, 0, _pullSpring);
    final dive = widget.onDive;
    if ((pull > 70 || up > 600) && dive != null) {
      HapticFeedback.selectionClick();
      dive(_front);
    } else if (pull < -70 || up < -600) {
      HapticFeedback.selectionClick();
      widget.onBack();
    }
  }

  void _onPanCancel() {
    _setTurning(false);
    _springTo(_pull, 0, 0, _pullSpring);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onPanCancel: _onPanCancel,
      child: LayoutBuilder(
        builder: (context, box) {
          _k = math.min(box.maxWidth / 390, box.maxHeight / 640);
          return AnimatedBuilder(
            animation: Listenable.merge([_rot, _duck, _pull]),
            builder: (context, _) => _stage(context, box.biggest),
          );
        },
      ),
    );
  }

  Widget _stage(BuildContext context, Size size) {
    final k = _k;
    final cx = size.width / 2;
    final cy = size.height * 0.34;
    const tilt = 52 * math.pi / 180;
    final c = math.cos(tilt);
    final s = math.sin(tilt);
    final radius = 150 * k;
    final pull = _pull.value;

    final seats = <_RingSeat>[];
    for (var i = 0; i < widget.count; i++) {
      final theta = _angle(i) + _rot.value;
      final d = math.sin(theta);
      final ring = Offset(
        cx + radius * math.cos(theta),
        cy + radius * math.sin(theta) * c,
      );
      final itemSize = widget.itemBase * k * (1 + 0.3 * d * s);
      final platformW = itemSize * 1.35;
      seats.add(
        _RingSeat(
          i,
          ring,
          ring.translate(0, -(itemSize / 2 + 2 * k)),
          itemSize,
          d,
          (1 - 0.45 * ((1 - d) / 2) * s).clamp(0.0, 1.0),
          Size(platformW, math.max(4 * k, platformW * c * 0.42)),
        ),
      );
    }
    seats.sort((a, b) => a.ringPoint.dy.compareTo(b.ringPoint.dy));
    final front = seats.reduce((a, b) => a.depth >= b.depth ? a : b);
    final highlight = _smoothstep(0.88, 0.995, front.depth);
    final focus =
        highlight *
        (1 - _duck.value) *
        (1 - (pull.abs() / 120).clamp(0.0, 1.0));

    final centerSize = 84 * k;
    final centerRing = Offset(cx, cy);
    final centerAt = centerRing.translate(0, -(centerSize / 2 + 4 * k));

    Widget place(Offset center, double side, Widget child) => Positioned(
      left: center.dx - side / 2,
      top: center.dy - side / 2,
      width: side,
      height: side,
      child: child,
    );

    final children = <Widget>[
      Positioned.fill(
        child: CustomPaint(
          painter: _RingPainter(
            k: k,
            center: centerRing,
            radius: radius,
            squash: c,
            seats: seats,
            colorOf: widget.colorOf,
            centerColor: widget.centerColor,
            centerPlatform: Size(
              centerSize * 1.5,
              math.max(4 * k, centerSize * 1.5 * c * 0.42),
            ),
            front: front.index,
            highlight: highlight,
          ),
        ),
      ),
    ];
    var centerPlaced = false;
    void placeCenter() {
      children.add(
        place(
          centerAt,
          centerSize,
          IgnorePointer(child: widget.centerBuilder(context, centerSize)),
        ),
      );
      centerPlaced = true;
    }

    for (final seat in seats) {
      if (!centerPlaced && seat.ringPoint.dy > centerRing.dy) placeCenter();
      final h = seat.index == front.index ? highlight : 0.0;
      children.add(
        place(
          seat.center,
          seat.size,
          GestureDetector(
            onTap: () {
              if (seat.index == front.index) {
                widget.onDive?.call(seat.index);
              } else {
                HapticFeedback.selectionClick();
                final base = math.pi / 2 - _angle(seat.index);
                final turns = ((_rot.value - base) / (2 * math.pi)).round();
                _springTo(_rot, base + turns * 2 * math.pi, 0, _rotSpring);
              }
            },
            child: Opacity(
              opacity: seat.opacity,
              child: widget.itemBuilder(context, seat.index, seat.size, h),
            ),
          ),
        ),
      );
    }
    if (!centerPlaced) placeCenter();

    if (focus > 0.01) {
      final top = front.ringPoint.dy + front.platform.height * 0.55 + 14 * k;
      final maxHeight = math.max(0.0, size.height - top - 10 * k);
      children.add(
        Positioned(
          left: 14 * k,
          right: 14 * k,
          top: top,
          child: IgnorePointer(
            ignoring: focus < 0.5,
            child: Opacity(
              opacity: focus,
              child: Transform.translate(
                offset: Offset(0, (1 - focus) * 18 * k),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: KeyedSubtree(
                      key: ValueKey('ring-card-${front.index}'),
                      child: widget.cardBuilder(
                        context,
                        front.index,
                        maxHeight,
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

    // Pulling up leans in towards diving; pulling down leans back.
    final zoom = (1 + pull * 0.0012).clamp(0.82, 1.25);
    return Transform.scale(
      scale: zoom,
      alignment: Alignment(0, (cy / size.height) * 2 - 1),
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double k;
  final Offset center;
  final double radius;
  final double squash;
  final List<_RingSeat> seats;
  final Color Function(int index) colorOf;
  final Color centerColor;
  final Size centerPlatform;
  final int front;
  final double highlight;

  _RingPainter({
    required this.k,
    required this.center,
    required this.radius,
    required this.squash,
    required this.seats,
    required this.colorOf,
    required this.centerColor,
    required this.centerPlatform,
    required this.front,
    required this.highlight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final starCenter = Offset(size.width / 2, size.height * 0.45);
    final reach = size.longestSide * 0.75;
    for (final star in _stars) {
      final z = star.z == 0 ? 0.5 : star.z;
      final distance = star.spread * reach * (0.3 / (z + 0.3));
      final p =
          starCenter +
          Offset(math.cos(star.angle), math.sin(star.angle)) * distance;
      canvas.drawCircle(
        p,
        (0.6 + (1 - z) * 1.2) * k,
        Paint()
          ..color = const Color(
            0xFF9AA59F,
          ).withValues(alpha: ((1 - z) * 0.5).clamp(0.0, 1.0)),
      );
    }

    final rect = Rect.fromCenter(
      center: center,
      width: radius * 2,
      height: radius * 2 * squash,
    );
    final dash = Paint()
      ..color = const Color(0xFF2E3B35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in (Path()..addOval(rect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6 * k), dash);
        d += 12 * k;
      }
    }

    _platform(canvas, center, centerPlatform, centerColor, 1, 0.4);
    for (final seat in seats) {
      _platform(
        canvas,
        seat.ringPoint,
        seat.platform,
        colorOf(seat.index),
        seat.opacity,
        seat.index == front ? highlight : 0,
      );
    }
  }

  void _platform(
    Canvas canvas,
    Offset at,
    Size platform,
    Color color,
    double strength,
    double glow,
  ) {
    final rect = Rect.fromCenter(
      center: at,
      width: platform.width,
      height: platform.height,
    );
    double a(double v) => (v * strength).clamp(0.0, 1.0);
    canvas.drawOval(
      rect.inflate(4 * k),
      Paint()
        ..color = color.withValues(alpha: a(0.14 + 0.18 * glow))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, (10 + 6 * glow) * k),
    );
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
    canvas.drawOval(
      rect,
      Paint()
        ..color = color.withValues(alpha: a(0.28 + 0.2 * glow))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => true;
}
