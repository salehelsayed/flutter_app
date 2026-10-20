part of 'orbit_depth_prototype_screen.dart';

// Spaces: the things people keep doing (books they read, movies they
// watched, work they made), shown on their world as calm scrolling pages.
// Fake data, like the rest of the prototype.

enum _SpaceKind { books, movies, work, add }

/// A thought kept in a Space by its #tag. A thought leaves the orbit after a
/// day and your Thoughts after 30 days; tagged into a Space, it stays.
class _KeptThought {
  final String text;

  /// The quiet divider it sits under on the shelf: "this week", "August".
  final String when;

  const _KeptThought(this.text, {required this.when});
}

class _Space {
  final String title;
  final _SpaceKind kind;
  final IconData icon;
  final Color hue;
  /// What it keeps, newest first.
  final List<_KeptThought> kept;

  /// What a work Space counts: projects, runs, hikes.
  final String unit;

  /// For your own Spaces: the #tag whose thoughts it keeps. A Space is a tag
  /// you chose to put in your world.
  final String? tag;

  const _Space(
    this.title,
    this.kind,
    this.icon,
    this.hue, {
    this.kept = const [],
    this.unit = 'entries',
    this.tag,
  });
}

const _laylaBooks = _Space(
  'Books',
  _SpaceKind.books,
  Icons.menu_book_outlined,
  Color(0xFFE6B566),
  tag: 'books',
  kept: [
    _KeptThought(
      'reading The Alchemist by Paulo Coelho. a third in. slow start but it is growing on me #books',
      when: 'this week',
    ),
    _KeptThought(
      'finished Men Without Women by Haruki Murakami. the last story stayed with me for days #books',
      when: 'September',
    ),
    _KeptThought(
      'finished Season of Migration to the North by Tayeb Salih. everyone should read this once. slowly. #books',
      when: 'August',
    ),
    _KeptThought(
      'finished Atomic Habits by James Clear. useful, could have been half the length #books',
      when: 'July',
    ),
    _KeptThought(
      'finished The Midnight Library by Matt Haig. read it in two nights #books',
      when: 'June',
    ),
    _KeptThought(
      'finished Sapiens by Yuval Noah Harari. changed how I think about money #books',
      when: 'May',
    ),
  ],
);

const _laylaMovies = _Space(
  'Movies',
  _SpaceKind.movies,
  Icons.movie_outlined,
  Color(0xFF8FB3E8),
  tag: 'movies',
  kept: [
    _KeptThought(
      'watched Past Lives last night. quiet and devastating. bring tissues #movies',
      when: 'this week',
    ),
    _KeptThought(
      'watched Perfect Days. I want to live like the main character #movies',
      when: 'September',
    ),
    _KeptThought(
      'watched Capernaum. hard to watch, impossible to forget #movies',
      when: 'August',
    ),
    _KeptThought(
      'watched Dune: Part Two. the sound in the cinema! #movies',
      when: 'March',
    ),
    _KeptThought(
      'watched Oppenheimer. too long for me #movies',
      when: 'July',
    ),
  ],
);

const _omarBooks = _Space(
  'Books',
  _SpaceKind.books,
  Icons.menu_book_outlined,
  Color(0xFFE6B566),
  tag: 'books',
  kept: [
    _KeptThought(
      'reading Deep Work by Cal Newport. phone in the other room. it actually works #books',
      when: 'this week',
    ),
    _KeptThought(
      'finished The Prophet by Kahlil Gibran. reread it every year #books',
      when: 'August',
    ),
    _KeptThought(
      "finished Can't Hurt Me by David Goggins. why I started the plank thing #books",
      when: 'June',
    ),
  ],
);

const _nourMovies = _Space(
  'Movies',
  _SpaceKind.movies,
  Icons.movie_outlined,
  Color(0xFF8FB3E8),
  tag: 'movies',
  kept: [
    _KeptThought(
      'watched Wadjda on Sunday. the bicycle scene got me #movies',
      when: 'this week',
    ),
    _KeptThought(
      'watched Inside Out 2. anxiety is too real #movies',
      when: 'July',
    ),
    _KeptThought(
      'watched Barbie. fun, the songs are stuck in my head #movies',
      when: 'last summer',
    ),
  ],
);

const _yourBooks = _Space(
  'Books',
  _SpaceKind.books,
  Icons.menu_book_outlined,
  Color(0xFFE6B566),
  tag: 'books',
  kept: [
    _KeptThought(
      'finished The Pragmatic Programmer by Hunt & Thomas. should have read this years ago #books',
      when: 'August',
    ),
  ],
);

const _yourRuns = _Space(
  'Runs',
  _SpaceKind.work,
  Icons.directions_run,
  Color(0xFF1DB954),
  unit: 'runs',
  tag: 'runs',
  kept: [
    _KeptThought(
      'first 10k without stopping. legs gone, head clear #runs',
      when: 'May',
    ),
    _KeptThought(
      '5k, first try, done. walked twice. not again #runs',
      when: 'earlier',
    ),
  ],
);

const _newSpace = _Space(
  'New space',
  _SpaceKind.add,
  Icons.add,
  Color(0xFF9AA59F),
);

const _laylaHikes = _Space(
  'Hikes',
  _SpaceKind.work,
  Icons.terrain_outlined,
  Color(0xFF7FB8A0),
  tag: 'hikes',
  kept: [
    _KeptThought(
      'weekend up north. still can\'t feel my legs, worth every step #hikes',
      when: 'this week',
    ),
    _KeptThought(
      'wadi mujib with the girls. waist deep in the river for an hour #hikes',
      when: 'September',
    ),
    _KeptThought(
      'first sunrise hike. the thermos was the best idea anyone ever had #hikes',
      when: 'June',
    ),
  ],
);

const _nourTravel = _Space(
  'Travel',
  _SpaceKind.work,
  Icons.flight_takeoff,
  Color(0xFFC7A6F0),
  tag: 'travel',
  kept: [
    _KeptThought(
      'airport at 6. lisbon for four days, finally #travel',
      when: 'this week',
    ),
    _KeptThought(
      'istanbul in the rain. ate my weight in simit #travel',
      when: 'August',
    ),
    _KeptThought(
      'the night train to aswan. would do it again tomorrow #travel',
      when: 'March',
    ),
  ],
);

const _tarekWorkshop = _Space(
  'Workshop',
  _SpaceKind.work,
  Icons.handyman_outlined,
  Color(0xFF7FD1F0),
  tag: 'workshop',
  kept: [
    _KeptThought(
      'shelves for the hallway, take two. the drill gave up halfway #workshop',
      when: 'this week',
    ),
    _KeptThought(
      'a stool for my niece. wobbles a bit, she loves it anyway #workshop',
      when: 'September',
    ),
    _KeptThought(
      'sanded the old door back to the wood. it was green underneath #workshop',
      when: 'July',
    ),
  ],
);

const _saraLuna = _Space(
  'Luna',
  _SpaceKind.work,
  Icons.pets_outlined,
  Color(0xFFF5B07A),
  tag: 'luna',
  kept: [
    _KeptThought(
      'we adopted her! meet luna. she already owns the sofa #luna',
      when: 'this week',
    ),
    _KeptThought(
      'luna met the sea today. she does not trust waves #luna',
      when: 'this week',
    ),
  ],
);

const _mayaWork = _Space(
  'Work',
  _SpaceKind.work,
  Icons.work_outline,
  Color(0xFFF5B07A),
  tag: 'work',
  kept: [
    _KeptThought(
      'new job starts monday. nervous in the good way #work',
      when: 'this week',
    ),
    _KeptThought(
      'last day at the studio. they made me a cake shaped like a deadline #work',
      when: 'September',
    ),
    _KeptThought(
      'portfolio finally done. forty drafts, one page #work',
      when: 'August',
    ),
  ],
);

const _danaCooking = _Space(
  'Cooking',
  _SpaceKind.work,
  Icons.restaurant_outlined,
  Color(0xFFF2A6C8),
  tag: 'cooking',
  kept: [
    _KeptThought(
      'cooking for 10 tonight. mansaf, too much as always #cooking',
      when: 'this week',
    ),
    _KeptThought(
      'my grandmother\'s maqluba, first time flipping it without disaster #cooking',
      when: 'September',
    ),
    _KeptThought(
      'sourdough attempt four. it is alive and it is angry #cooking',
      when: 'July',
    ),
  ],
);

const _wardGarden = _Space(
  'Garden',
  _SpaceKind.work,
  Icons.local_florist_outlined,
  Color(0xFFA3E07F),
  tag: 'garden',
  kept: [
    _KeptThought(
      'garden finally bloomed. three years for this #garden',
      when: 'this week',
    ),
    _KeptThought(
      'planted the jasmine by the window, for mornings #garden',
      when: 'May',
    ),
    _KeptThought(
      'lost the tomatoes to the heat. trying again next spring #garden',
      when: 'last summer',
    ),
  ],
);

const _miraBooks = _Space(
  'Books',
  _SpaceKind.work,
  Icons.menu_book_outlined,
  Color(0xFFE6B566),
  tag: 'books',
  kept: [
    _KeptThought(
      'finally finished the book. Pachinko by Min Jin Lee. I miss them already #books',
      when: 'this week',
    ),
    _KeptThought(
      'reading three books at once again. no regrets #books',
      when: 'September',
    ),
    _KeptThought(
      'A Thousand Splendid Suns on the bus. had to stop, people were staring #books',
      when: 'June',
    ),
  ],
);

const _linaFootball = _Space(
  'Football',
  _SpaceKind.work,
  Icons.sports_soccer,
  Color(0xFFF2A6C8),
  tag: 'football',
  kept: [
    _KeptThought(
      'anyone watching the match? I need someone to shout with #football',
      when: 'this week',
    ),
    _KeptThought(
      'five a side on thursday. scored once, fell twice #football',
      when: 'September',
    ),
  ],
);

const _hudaTravel = _Space(
  'Travel',
  _SpaceKind.work,
  Icons.flight_takeoff,
  Color(0xFFFF9E9E),
  tag: 'travel',
  kept: [
    _KeptThought(
      'back in town next week. bringing dates from medina #travel',
      when: 'this week',
    ),
    _KeptThought(
      'a month in kuala lumpur. the rain at four every day, like a clock #travel',
      when: 'August',
    ),
  ],
);

const _spacesByOwner = <String, List<_Space>>{
  'layla': [_laylaBooks, _laylaMovies, _laylaHikes],
  'omar': [_omarBooks],
  'nour': [_nourMovies, _nourTravel],
  'tarek': [_tarekWorkshop],
  'sara': [_saraLuna],
  'maya': [_mayaWork],
  'dana': [_danaCooking],
  'ward': [_wardGarden],
  'mira': [_miraBooks],
  'lina': [_linaFootball],
  'huda': [_hudaTravel],
};

/// Your Spaces: the tags you put in your world. They grow while the
/// prototype runs.
final List<_Space> _yourSpaces = [_yourBooks, _yourRuns];

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
List<_Space> _spacesFor(String owner) => owner == 'you'
    ? [..._yourSpaces, _newSpace]
    : _spacesByOwner[owner] ?? _fofSpaces[owner] ?? const [];

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

  String get _subtitle => space.kind == _SpaceKind.add
      ? 'Start something your friends can follow'
      : '#${space.tag}';

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
        final latest = space.kept.firstOrNull;
        if (latest == null) return const [];
        return [
          Text(
            _withoutTags(latest.text),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _ink, fontSize: 14.5, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            latest.when,
            style: _mono.copyWith(color: _faint, fontSize: 11.5),
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

void _openKeptSheet(BuildContext context, String owner, _KeptThought kept) {
  HapticFeedback.selectionClick();
  final page = context;
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
                  _personPhoto(owner, 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          _taggedSpan(
                            kept.text,
                            const TextStyle(
                              color: _ink,
                              fontSize: 16,
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          kept.when,
                          style: _mono.copyWith(color: _faint, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // A Space is kept, not performed: no comments under it, only
              // a word to its owner that stays between the two of you.
              if (owner != 'you') ...[
                const SizedBox(height: 20),
                GestureDetector(
                  key: ValueKey('space-write-$owner'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).pop();
                    _openDm(page, owner);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: _chat.surfaceSubtle,
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 14, color: _accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Write to $owner about this · only they see it',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFC7CEC9),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
