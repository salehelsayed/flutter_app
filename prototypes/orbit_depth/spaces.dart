part of 'orbit_depth_prototype_screen.dart';

// Spaces: the things people keep doing (books they read, movies they
// watched, work they made), shown on their world as calm scrolling pages.
// Fake data, like the rest of the prototype.

enum _SpaceKind { books, movies, work, add }

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

class _Space {
  final String title;
  final _SpaceKind kind;
  final IconData icon;
  final Color hue;
  final List<_SpaceItem> items;

  /// What a work Space counts: projects, runs, hikes.
  final String unit;

  const _Space(
    this.title,
    this.kind,
    this.icon,
    this.hue, {
    this.items = const [],
    this.unit = 'entries',
  });
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

const _yourRuns = _Space(
  'Runs',
  _SpaceKind.work,
  Icons.directions_run,
  Color(0xFF1DB954),
  unit: 'runs',
  items: [
    _SpaceItem(
      '5k along the corniche',
      'Wednesday · 28:55',
      Color(0xFF1F3B4D),
      rating: 0,
      status: 'New best',
      note: 'slowly getting there',
      comments: 6,
    ),
    _SpaceItem(
      '5k, first try',
      'Monday · 29:40',
      Color(0xFF3F5B3A),
      rating: 0,
      status: 'Done',
      note: 'walked twice. not again',
      comments: 4,
    ),
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
  'omar': [_omarBooks],
  'nour': [_nourMovies],
  'you': [_yourBooks, _yourRuns, _newSpace],
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
    _PastThought('Thursday was a good day. new personal best', age: '1 d'),
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
};

/// Everything someone shared: the live thought first, then older ones.
List<_PastThought> _thoughtsOf(String owner) {
  if (owner == 'you') return _yourPastThoughts();
  final thoughts = <_PastThought>[];
  final f = _friendNamed(owner);
  final thought = f?.thought;
  if (f != null && thought != null) {
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

/// A person's Spaces: yours, a friend's, or the ones a friend of a friend
/// opened to friends of friends.
List<_Space> _spacesFor(String owner) =>
    _spacesByOwner[owner] ?? _fofSpaces[owner] ?? const [];

void _openSpace(BuildContext context, String owner, String title) {
  for (final space in _spacesFor(owner)) {
    if (space.title == title) {
      HapticFeedback.selectionClick();
      Navigator.of(
        context,
      ).push(_diveRoute(_SpacePage(owner: owner, space: space)));
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
    pageBuilder: (context, animation, secondary) =>
        CosmicBackgroundMirrored(child: page),
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
    _SpaceKind.books => 'Reading list · ${space.items.length} books',
    _SpaceKind.movies => 'Watched · ${space.items.length} movies',
    _SpaceKind.work => '${space.items.length} ${space.unit}',
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
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _AccentButton(
                label: space.kind == _SpaceKind.add ? 'Create' : 'Open',
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
      case _SpaceKind.books:
      case _SpaceKind.movies:
      case _SpaceKind.work:
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
            style: const TextStyle(color: _chatSecondary, fontSize: 13),
          ),
        ];
      case _SpaceKind.add:
        return const [
          Text(
            'A reading list, movies you watched, anything you keep doing. '
            'Your friends see it on your world.',
            style: TextStyle(color: _chatSecondary, fontSize: 13),
          ),
        ];
    }
  }
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
          color: _chat.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _chat.border),
        ),
        child: child,
      ),
    );
  }
}

class _AccentButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AccentButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _accent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: const Color(0xFF03140A),
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
        color: now ? const Color(0xFF12301F) : _chat.surfaceSubtle,
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
    backgroundColor: _sheet,
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
                  fillColor: _chat.surfaceSubtle,
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
      Icons.edit_note,
      'Journal',
      'Free-form entries for anything else you keep doing.',
    ),
  ];
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: _sheet,
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
                      color: _chat.surfaceRaised,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _chat.border),
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
