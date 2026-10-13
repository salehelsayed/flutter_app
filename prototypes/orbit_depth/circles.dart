part of 'orbit_depth_prototype_screen.dart';

// Friends of friends: trust travels through people. A friend's friend can be
// reached only when they chose to be found and the friend between you chose
// to carry them; both sides always see which friend connects you. On the
// orbit, a friend who carries anyone grows a short branch of dots; the front
// friend says "2 people via omar", which opens who. You can knock on them
// directly, or ask the friend to introduce you. Nothing opens until they
// say hi, and then it is a chat, not a place on each other's orbit.

/// Someone a friend of yours knows, who chose to be found.
class _Fof {
  final String name;

  /// The friend who carries them; shown to both sides.
  final String via;
  final _Hue hue;

  /// What they are happy to hear about from friends of friends, as topics
  /// a knock picks from.
  final List<String> openTo;

  /// What they are open for, in their own words. Someone who wrote nothing
  /// is not shown to friends of friends.
  final String note;

  /// Other friends of yours who carry them too.
  final List<String> alsoVia;

  /// Their answer when they say hi.
  final String reply;

  /// How many of their Spaces stay with their own friends.
  final int friendsOnlySpaces;

  const _Fof(
    this.name,
    this.via,
    this.hue, {
    required this.openTo,
    required this.note,
    required this.reply,
    this.alsoVia = const [],
    this.friendsOnlySpaces = 0,
  });
}

// In the order they hang off each friend.
const _fofs = <_Fof>[
  _Fof(
    'salim',
    'nour',
    _purple,
    openTo: ['film nights'],
    friendsOnlySpaces: 1,
    note: '',
    reply: 'always up for a film. nour said you liked Wadjda',
  ),
  _Fof(
    'ruba',
    'layla',
    _pink,
    openTo: ['running partners'],
    note:
        'Training for my first half marathon in March. We run Saturdays at 7 from the corniche, every pace welcome, and I’m happy to share the plan that got me from 5k to 15k.',
    alsoVia: ['nour'],
    reply: 'yes! we run saturdays at 7, join us',
  ),
  _Fof(
    'nabil',
    'tarek',
    _cyan,
    openTo: ['woodworking', 'lending tools'],
    friendsOnlySpaces: 1,
    note:
        'I build furniture on weekends and own more tools than I need. Starting a small project? I can lend a drill or a saw and show you how to use it.',
    reply: 'sure, I have a spare drill. tarek told me about the shelves',
  ),
  _Fof(
    'hisam',
    'omar',
    _blue,
    openTo: ['design feedback', 'coffee chats'],
    friendsOnlySpaces: 2,
    note:
        'Ten years designing app icons and signage. Happy to look at early work, give honest feedback, and talk about freelancing in Cairo over coffee.',
    alsoVia: ['layla'],
    reply: 'hey! any friend of omar’s. send me what you’re working on',
  ),
  _Fof(
    'idris',
    'omar',
    _green,
    openTo: ['hiking', 'photography'],
    friendsOnlySpaces: 1,
    note:
        'I lead a small hike once a month, usually 8 to 12 km, and take photos on the way. Beginners welcome, I’ll tell you what to bring.',
    alsoVia: ['tarek'],
    reply: 'omar and I hike every month. come on the next one',
  ),
  _Fof(
    'yazan',
    'layla',
    _yellow,
    openTo: ['books'],
    note:
        'Reading my way through Kahneman and anything on how people decide. Always looking for someone to argue about a chapter with.',
    reply: 'thanks for saying hi!',
  ),
  _Fof(
    'tala',
    'sara',
    _orange,
    openTo: ['dog walks'],
    note:
        'New dog, new neighbourhood. Looking for people to walk with in the mornings and swap tips on training a stubborn puppy.',
    reply: 'luna and my dog would get along. park on sunday?',
  ),
  _Fof(
    'munir',
    'maya',
    _red,
    openTo: ['career advice'],
    friendsOnlySpaces: 3,
    note:
        'Fifteen years in product teams, now mentoring. Starting a new job or thinking of switching? Glad to talk it through.',
    reply: 'happy to help. maya mentioned the new job',
  ),
  _Fof(
    'kenan',
    'dana',
    _green,
    openTo: ['cooking'],
    note:
        'I cook for crowds and love teaching it. Ask me about mansaf, bread, or feeding twenty people on a budget.',
    reply: 'dana’s mansaf is legendary. what are you making?',
  ),
];

/// Faces the prototype has for people who are not your friends.
const _photoAliases = <String, String>{
  'hisam': 'rami',
  'ruba': 'jana',
  'nabil': 'adam',
  'salim': 'sami',
  'tala': 'rita',
  'munir': 'nizar',
  'kenan': 'tamer',
  'yazan': 'majd',
  'idris': 'karim',
};

_Fof? _fofOf(String name) {
  for (final f in _fofs) {
    if (f.name == name) return f;
  }
  return null;
}

/// The friends of yours who carry [fof], leaving out any you paused.
List<String> _viasOf(_Fof fof) => [
  for (final v in [fof.via, ...fof.alsoVia])
    if (!_pausedBridges.contains(v)) v,
];

/// Everyone you can reach through a friend: they wrote what they are open
/// for, and you have not blocked them or paused every friend who carries
/// them. People more of your friends know come first.
List<_Fof> _reachable() {
  final people = [
    for (final f in _fofs)
      if (f.note.isNotEmpty &&
          !_blocked.contains(f.name) &&
          _viasOf(f).isNotEmpty)
        f,
  ];
  // A stable sort: the same order every time for the same count.
  return [
    for (final n in {for (final f in people) _viasOf(f).length}.toList()
      ..sort((a, b) => b.compareTo(a)))
      for (final f in people)
        if (_viasOf(f).length == n) f,
  ];
}

/// Who you can reach through [friend].
List<_Fof> _reachVia(String friend) =>
    [for (final f in _reachable()) if (_viasOf(f).contains(friend)) f];

/// "2 people via omar".
String _peopleVia(int n, String via) =>
    n == 1 ? '1 person via $via' : '$n people via $via';

/// The Spaces friends of friends opened to friends of friends.
const _fofSpaces = <String, List<_Space>>{
  'hisam': [
    _Space(
      'Design work',
      _SpaceKind.work,
      Icons.brush_outlined,
      Color(0xFF7FB8E8),
      unit: 'projects',
      items: [
        _SpaceItem(
          'Wayfinding for the old souq',
          'Signage · 2026',
          Color(0xFF1F3B4D),
          rating: 0,
          status: 'Shipped in May',
          note: 'every sign hand drawn first, then cut in brass',
          comments: 9,
        ),
        _SpaceItem(
          'A calmer banking app',
          'App design · 2025',
          Color(0xFF3B2F4D),
          rating: 0,
          status: 'Case study',
          note: 'took out 40% of the screens. nobody missed them',
          comments: 5,
        ),
        _SpaceItem(
          'Bookshop identity',
          'Branding · 2025',
          Color(0xFFD9C7A3),
          rating: 0,
          status: 'In progress',
          note: 'looking for honest eyes on the logo',
          comments: 3,
        ),
      ],
    ),
  ],
  'idris': [
    _Space(
      'Hikes',
      _SpaceKind.work,
      Icons.terrain_outlined,
      Color(0xFF1DB954),
      unit: 'hikes',
      items: [
        _SpaceItem(
          'Jebel Akhdar',
          'September · 8 km',
          Color(0xFF3F5B3A),
          rating: 0,
          status: 'Done',
          note: 'the terraces at sunrise. worth the 4am start',
          comments: 6,
        ),
        _SpaceItem(
          'Wadi Ghul',
          'August · 12 km',
          Color(0xFF6B4E2E),
          rating: 0,
          status: 'Done',
          note: 'the rim walk. bring twice the water you think',
          comments: 3,
        ),
      ],
    ),
  ],
  'nabil': [
    _Space(
      'Workshop',
      _SpaceKind.work,
      Icons.handyman_outlined,
      Color(0xFFE6B566),
      unit: 'projects',
      items: [
        _SpaceItem(
          'Walnut bookshelf',
          'Joinery · 2026',
          Color(0xFF5A3A2E),
          rating: 0,
          status: 'Finished in June',
          note: 'no screws, only dovetails',
          comments: 4,
        ),
        _SpaceItem(
          'Kids’ step stool',
          'Pine · 2025',
          Color(0xFFD9C7A3),
          rating: 0,
          status: 'Gave it away',
          note: 'built it twice, the first one wobbled',
          comments: 2,
        ),
      ],
    ),
  ],
  'yazan': [
    _Space(
      'Reading list',
      _SpaceKind.books,
      Icons.menu_book_outlined,
      Color(0xFFE6B566),
      items: [
        _SpaceItem(
          'Noise',
          'Kahneman, Sibony, Sunstein',
          Color(0xFF2E3A4F),
          rating: 0,
          status: 'Reading now',
          note: 'looking for someone to argue chapter 5 with',
          comments: 1,
        ),
      ],
    ),
  ],
  'ruba': [
    _Space(
      'Saturday runs',
      _SpaceKind.work,
      Icons.directions_run,
      Color(0xFF1DB954),
      unit: 'runs',
      items: [
        _SpaceItem(
          'Corniche loop',
          'Oct 4 · 9 runners · 6 km',
          Color(0xFF1F3B4D),
          rating: 0,
          status: 'Done',
          note: 'new people every week. all paces welcome',
          comments: 6,
        ),
      ],
    ),
  ],
  'tala': [
    _Space(
      'Dog walks',
      _SpaceKind.work,
      Icons.pets_outlined,
      Color(0xFFF2A65A),
      unit: 'walks',
      items: [
        _SpaceItem(
          'Park at the end of 7th',
          'Sundays · 9am',
          Color(0xFF3F5B3A),
          rating: 0,
          status: 'Every week',
          note: 'there is a fenced bit for the small ones',
          comments: 2,
        ),
      ],
    ),
  ],
  'munir': [
    _Space(
      'Notes for new managers',
      _SpaceKind.work,
      Icons.edit_note,
      Color(0xFFFF9E9E),
      unit: 'notes',
      items: [
        _SpaceItem(
          'Your first 30 days',
          'Note · 2026',
          Color(0xFF4D2E2E),
          rating: 0,
          status: 'Pinned',
          note: 'listen more than you change anything',
          comments: 11,
        ),
      ],
    ),
  ],
};

// ---------------------------------------------------------------------------
// Knocks and introductions you asked for.
// ---------------------------------------------------------------------------

enum _ReachState { waiting, introduced, accepted, noReply }

/// You reached out to [name] through [via]: a knock, or an ask for [via] to
/// introduce you.
class _Reach {
  final String name;
  final String via;
  final bool intro;
  final String topic;
  final String note;
  int daysLeft;
  _ReachState state;

  _Reach(
    this.name,
    this.via, {
    required this.topic,
    required this.note,
    this.intro = false,
    this.daysLeft = 14,
    this.state = _ReachState.waiting,
  });
}

/// Everyone you reached out to, by name.
final Map<String, _Reach> _reaches = _seedReaches();

Map<String, _Reach> _seedReaches() => {
  'tala': _Reach(
    'tala',
    'sara',
    topic: 'dog walks',
    note: 'we just adopted a puppy. could we join a walk?',
    daysLeft: 12,
  ),
  'nabil': _Reach(
    'nabil',
    'tarek',
    topic: 'lending tools',
    note: 'could I borrow a router for an afternoon?',
    daysLeft: 0,
    state: _ReachState.noReply,
  ),
};

/// At most this many knocks wait at once.
const _knockLimit = 3;

int get _openKnocks => _reaches.values
    .where((r) => !r.intro && r.state == _ReachState.waiting)
    .length;

/// Friends who already hold as many introduction asks as they take.
const _busyBridges = {'layla'};

/// You knock on [name]. In the prototype they say hi a few seconds later.
void _sendKnock(String name, String topic, String note) {
  final fof = _fofOf(name);
  if (fof == null) return;
  final reach = _Reach(name, fof.via, topic: topic, note: note);
  _reaches[name] = reach;
  _chatTick.value++;
  _friendTimers.add(
    Timer(const Duration(seconds: 5), () => _saidHi(reach, fof)),
  );
}

/// You ask [fof]'s friend to introduce you. A few seconds later they do,
/// and a few more later [fof] says hi.
void _askIntro(_Fof fof, String note) {
  final reach = _Reach(
    fof.name,
    fof.via,
    topic: fof.openTo.first,
    note: note,
    intro: true,
  );
  _reaches[fof.name] = reach;
  _chatTick.value++;
  _friendTimers
    ..add(
      Timer(const Duration(seconds: 4), () {
        reach.state = _ReachState.introduced;
        _chatTick.value++;
      }),
    )
    ..add(Timer(const Duration(seconds: 8), () => _saidHi(reach, fof)));
}

/// [fof] said hi: you are introduced, and a chat opens on both sides.
void _saidHi(_Reach reach, _Fof fof) {
  if (reach.state == _ReachState.accepted) return;
  reach.state = _ReachState.accepted;
  _dms[fof.name] = _Dm(
    [
      if (reach.note.isNotEmpty) _Msg('you', reach.note, '1 min'),
      _Msg(fof.name, fof.reply, 'now'),
    ],
    unread: 1,
    via: fof.via,
    bridgeLine: reach.intro ? 'a good friend, you two should talk' : null,
  );
  _chatTick.value++;
  _notify('${fof.name} said hi');
}

/// What the button on someone you can reach says.
String _reachLabel(String name) {
  if (_dms.containsKey(name)) return 'Chat';
  if (_requestFrom(name) != null) return 'Answer';
  return switch (_reaches[name]?.state) {
    null => 'Knock',
    _ReachState.waiting || _ReachState.introduced => 'Waiting',
    _ReachState.accepted => 'Chat',
    _ReachState.noReply => 'No reply',
  };
}

/// Knock on [name], or open your chat once they said hi.
void _knockOrChat(BuildContext context, String name) {
  final nav = Navigator.of(context);
  // A sheet never opens over a sheet: the one you are on steps aside.
  if (ModalRoute.of(context) is ModalBottomSheetRoute) nav.pop();
  final host = nav.context;
  switch (_reachLabel(name)) {
    case 'Chat':
      _openDm(host, name);
    case 'Answer':
      _openChats(host);
    case 'Knock':
      _openKnock(host, name);
  }
}

Future<T?> _openSheet<T>(BuildContext context, Widget child) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF15171C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => child,
  );
}

/// Everyone you can reach, or only those through [via].
void _openReach(BuildContext context, {String? via}) {
  HapticFeedback.selectionClick();
  Navigator.of(context).push(_diveRoute(_ReachPage(via: via)));
}

Future<void> _openKnock(BuildContext context, String name) =>
    _openSheet(context, _KnockSheet(fof: _fofOf(name)!));

Future<void> _openIntroAsk(BuildContext context, String name) =>
    _openSheet(context, _IntroAskSheet(fof: _fofOf(name)!));

// ---------------------------------------------------------------------------
// Pieces.
// ---------------------------------------------------------------------------

const _soft = TextStyle(color: Color(0xFFA9B1AC), fontSize: 12.5);

class _Chip extends StatelessWidget {
  final String text;
  final bool on;
  final VoidCallback? onTap;

  const _Chip(this.text, {super.key, this.on = false, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: on ? const Color(0x331DB954) : const Color(0x14F2F4F3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: on ? const Color(0x991DB954) : const Color(0x00000000),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: on ? _ink : const Color(0xFFDDE2DF),
          fontSize: 13,
          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    ),
  );
}

/// Knock, Waiting, Chat, No reply, or Answer when they already reached you.
class _KnockButton extends StatelessWidget {
  final String name;

  const _KnockButton({required this.name});

  @override
  Widget build(BuildContext context) {
    final label = _reachLabel(name);
    final live = label == 'Knock' || label == 'Chat' || label == 'Answer';
    return FilledButton.icon(
      key: ValueKey('knock-$name'),
      onPressed: live ? () => _knockOrChat(context, name) : null,
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: const Color(0xFF04110A),
        disabledBackgroundColor: const Color(0x331DB954),
        disabledForegroundColor: const Color(0xFFA9B1AC),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(
        label == 'Chat'
            ? Icons.chat_bubble_outline_rounded
            : Icons.waving_hand_outlined,
        size: 16,
      ),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

/// A primary button across the bottom of a sheet.
class _WideButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _WideButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 48,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: const Color(0xFF04110A),
        disabledBackgroundColor: const Color(0x331DB954),
        disabledForegroundColor: const Color(0xFF7D8781),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
  );
}

/// Padding for a sheet's content, clear of the keyboard and the home bar.
EdgeInsets _sheetPadding(BuildContext context) => EdgeInsets.fromLTRB(
  20,
  0,
  20,
  MediaQuery.viewInsetsOf(context).bottom +
      MediaQuery.paddingOf(context).bottom +
      16,
);

// ---------------------------------------------------------------------------
// "Through omar": who you can reach through one friend.
// ---------------------------------------------------------------------------

/// People you can reach through your friends, each in their own words:
/// what they are open for, the topics a knock picks from, and which of your
/// friends carry them. Narrow it to a topic, or to one friend.
class _ReachPage extends StatefulWidget {
  final String? via;

  const _ReachPage({this.via});

  @override
  State<_ReachPage> createState() => _ReachPageState();
}

class _ReachPageState extends State<_ReachPage> {
  late String? _via = widget.via;
  String? _topic;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('reach'),
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: _chatTick,
          builder: (context, _) {
            final everyone = [
              for (final f in _reachable())
                if (_via == null || _viasOf(f).contains(_via)) f,
            ];
            final topics = {for (final f in everyone) ...f.openTo}.toList()
              ..sort();
            final topic = topics.contains(_topic) ? _topic : null;
            final shown = [
              for (final f in everyone)
                if (topic == null || f.openTo.contains(topic)) f,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _DiveHeader(trail: ['People you can reach']),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      if (_via case final via?) ...[
                        _Chip(
                          'via $via  ×',
                          key: const ValueKey('reach-via'),
                          on: true,
                          onTap: () => setState(() => _via = null),
                        ),
                        const SizedBox(width: 6),
                      ],
                      _Chip(
                        'All',
                        key: const ValueKey('reach-topic-all'),
                        on: topic == null,
                        onTap: () => setState(() => _topic = null),
                      ),
                      for (final t in topics) ...[
                        const SizedBox(width: 6),
                        _Chip(
                          t,
                          key: ValueKey('reach-topic-$t'),
                          on: t == topic,
                          onTap: () => setState(() => _topic = t),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      for (final f in shown) _OpenForCard(fof: f),
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Only people who chose to be found appear here, '
                          'in their own words.',
                          style: _soft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One person you can reach: who, through which friends, what they are open
/// for in their own words, and the topics they listed.
class _OpenForCard extends StatelessWidget {
  final _Fof fof;

  const _OpenForCard({required this.fof});

  @override
  Widget build(BuildContext context) {
    final name = fof.name;
    return Container(
      key: ValueKey('open-for-$name'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      decoration: BoxDecoration(
        color: _chat.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _chat.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _openWorld(context, name),
                child: _personPhoto(name, 44),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('via ${_viaNames(_viasOf(fof))}', style: _soft),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            fof.note,
            style: const TextStyle(color: _ink, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final t in fof.openTo) _Chip(t)],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: ValueKey('world-link-$name'),
                    onPressed: () => _openWorld(context, name),
                    style: TextButton.styleFrom(
                      foregroundColor: _accent,
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      'See $name’s world  ›',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _KnockButton(name: name),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Knock: straight to them, through the friend you share.
// ---------------------------------------------------------------------------

class _KnockSheet extends StatefulWidget {
  final _Fof fof;

  const _KnockSheet({required this.fof});

  @override
  State<_KnockSheet> createState() => _KnockSheetState();
}

class _KnockSheetState extends State<_KnockSheet> {
  /// A topic is required; nothing is picked for you.
  String? _topic;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _send() {
    final topic = _topic;
    if (topic == null) return;
    HapticFeedback.lightImpact();
    _sendKnock(widget.fof.name, topic, _note.text.trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final fof = widget.fof;
    final full = _openKnocks >= _knockLimit;
    final topic = _topic;
    return Padding(
      padding: _sheetPadding(context),
      child: Column(
        key: const ValueKey('knock-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _personPhoto(fof.name, 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Knock on ${fof.name}',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _ViaChip(via: fof.via),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            fof.note,
            style: const TextStyle(
              color: _chatSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          const Text('About', style: _soft),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in fof.openTo)
                _Chip(
                  t,
                  key: ValueKey('topic-$t'),
                  on: t == topic,
                  onTap: () => setState(() => _topic = t),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            maxLength: 200,
            style: const TextStyle(color: _ink, fontSize: 15.5),
            decoration: InputDecoration(
              hintText: 'Say why you’re reaching out',
              hintStyle: const TextStyle(color: Color(0xFF8A8F98)),
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
          // What the other side sees, so nothing about a knock surprises.
          Text(
            topic == null
                ? '${fof.name} will see: You, via ${fof.via}, and what it is '
                      'about.'
                : '${fof.name} will see: You, via ${fof.via}, about $topic.',
            style: const TextStyle(color: _ink, fontSize: 13.5),
          ),
          const SizedBox(height: 4),
          Text(
            'No reply means nothing happens. We don’t tell ${fof.via}.',
            style: _soft,
          ),
          if (full) ...[
            const SizedBox(height: 10),
            const Text(
              '3 open knocks. Another can go once one is answered or '
              'expires.',
              key: ValueKey('knock-limit'),
              style: TextStyle(color: Color(0xFFE6B566), fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          _WideButton(
            key: const ValueKey('send-knock'),
            label: 'Knock',
            onPressed: topic == null || full ? null : _send,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ask the friend between you to introduce you.
// ---------------------------------------------------------------------------

class _IntroAskSheet extends StatefulWidget {
  final _Fof fof;

  const _IntroAskSheet({required this.fof});

  @override
  State<_IntroAskSheet> createState() => _IntroAskSheetState();
}

class _IntroAskSheetState extends State<_IntroAskSheet> {
  final TextEditingController _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _send() {
    HapticFeedback.lightImpact();
    _askIntro(widget.fof, _note.text.trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final fof = widget.fof;
    final via = fof.via;
    final busy = _busyBridges.contains(via);
    return Padding(
      padding: _sheetPadding(context),
      child: Column(
        key: const ValueKey('intro-ask-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _personPhoto(via, 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Ask $via to introduce you to ${fof.name}',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            maxLength: 200,
            enabled: !busy,
            style: const TextStyle(color: _ink, fontSize: 15.5),
            decoration: InputDecoration(
              hintText: 'A line for $via',
              hintStyle: const TextStyle(color: Color(0xFF8A8F98)),
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
          Text(
            busy
                ? '$via can’t take introductions right now.'
                : '$via decides. If $via skips it, nothing happens, and '
                      '${fof.name} never hears of it.',
            key: busy ? const ValueKey('bridge-busy') : null,
            style: busy
                ? const TextStyle(color: Color(0xFFE6B566), fontSize: 13)
                : _soft,
          ),
          const SizedBox(height: 16),
          _WideButton(
            key: const ValueKey('send-intro-ask'),
            label: 'Ask $via',
            onPressed: busy || _note.text.trim().isEmpty ? null : _send,
          ),
        ],
      ),
    );
  }
}
