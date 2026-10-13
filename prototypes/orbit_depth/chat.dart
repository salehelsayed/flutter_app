part of 'orbit_depth_prototype_screen.dart';

// Chats: every conversation. A reply to a thought is an ordinary message in
// your 1:1 chat with its author; the first reply carries a small quote of
// the thought, which still reads once the thought has left the orbit.
// Replies count as unread and move the chat up like any message. People who
// reached you through a friend wait in Requests, at the top.

/// The thought a reply answers, kept with the message.
class _Quote {
  final String author;

  /// Which of the author's posts: 0 is their live thought (for yours, the
  /// thought's id). Negative is a thought that is gone.
  final int post;
  final String text;

  const _Quote(this.author, this.post, this.text);

  bool get gone => post < 0;

  bool same(_Quote? other) =>
      other != null &&
      other.author == author &&
      other.post == post &&
      other.text == text;
}

class _Msg {
  final String from;
  final String text;
  final String age;

  /// The thought this message answers, if it is a reply to one.
  final _Quote? about;

  const _Msg(this.from, this.text, this.age, {this.about});

  bool get mine => from == 'you';
}

/// Your chat with one person.
class _Dm {
  final List<_Msg> messages;
  int unread;

  /// For someone who is not your friend: the friend who connects you.
  final String? via;

  /// What that friend said when introducing you, if they did.
  final String? bridgeLine;

  /// Copies [messages], so the const samples can still take new ones.
  _Dm(List<_Msg> messages, {this.unread = 0, this.via, this.bridgeLine})
    : messages = [...messages];
}

const _nourLive = _Quote('nour', 0, 'airport at 6. taxi anyone?');
const _nourGone = _Quote('nour', -1, 'concert tickets for thursday, who’s in?');
const _laylaPastLives = _Quote('layla', 1, 'who wants to see Past Lives with me?');
const _yourRunQuote = _Quote('you', 0, 'ran 5k in 28:55. slowly getting there');
const _yourBookQuote = _Quote(
  'you',
  1,
  'chapter 12 of Thinking, Fast and Slow. my brain hurts',
);
const _yourRamen = _Quote(
  'you',
  -1,
  'looking for a good ramen place downtown',
);

/// Your chats, oldest message first. They last while the prototype runs.
final Map<String, _Dm> _dms = _seedDms();

Map<String, _Dm> _seedDms() => {
  'nour': _Dm(const [
    _Msg('nour', 'did you see the new trailer?', '6 d'),
    _Msg('you', 'not yet! send it', '6 d'),
    _Msg('you', 'me!! how much?', '5 d', about: _nourGone),
    _Msg('nour', '25. I’ll get yours too', '5 d'),
    _Msg('you', 'deal 🎶', '5 d'),
    _Msg('nour', 'proud of you!!', '1 d', about: _yourRunQuote),
    _Msg('you', 'I land at 6 too!', '15 min', about: _nourLive),
    _Msg('nour', 'perfect, let’s share one', '12 min'),
    _Msg('you', 'see you at 6 then', '10 min'),
  ]),
  'omar': _Dm(const [
    _Msg('omar', 'that pace is great. sunday run?', '1 h', about: _yourRunQuote),
  ], unread: 1),
  'layla': _Dm(const [
    _Msg('layla', 'are you around this weekend?', '1 w'),
    _Msg('you', 'sunday works!', '1 w'),
    _Msg('layla', 'Menya on 5th street. trust me', '6 d', about: _yourRamen),
    _Msg('you', 'going tonight!', '6 d'),
    _Msg('you', 'me! saturday evening?', '4 d', about: _laylaPastLives),
    _Msg('layla', 'yes!! 7pm at the Vox?', '4 d'),
    _Msg('you', 'perfect, I’ll bring snacks', '4 d'),
    _Msg('layla', 'that chapter broke me too', '2 d', about: _yourBookQuote),
  ]),
  'tarek': _Dm(const [
    _Msg('tarek', '28:55?! nice', '6 h', about: _yourRunQuote),
    _Msg('you', 'thanks! see you there', '5 h'),
  ]),
  'sara': _Dm(const [
    _Msg('sara', 'luna says hi 🐶', '2 d'),
    _Msg('you', 'so cute. bring luna on sunday', '2 d'),
  ]),
  'dana': _Dm(const [
    _Msg('dana', 'saturday still on?', '3 d'),
    _Msg('you', 'yes! bringing dessert', '3 d'),
  ]),
};

/// Your quiet reactions to other people's posts, by '$author#$post'. Only
/// the author sees them, as a count; they are not messages.
final Map<String, String> _myReactions = {'layla#1': '😍'};

/// Ticks whenever a chat changes, so the orbit, Chats and the tab badge
/// follow.
final ValueNotifier<int> _chatTick = ValueNotifier(0);

/// Shows the short notes that something arrived: someone said hi, a reply
/// came.
final GlobalKey<ScaffoldMessengerState> _messenger = GlobalKey();

void _notify(String text) {
  final messenger = _messenger.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xF2252830),
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text(
          text,
          key: const ValueKey('notice'),
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
}

/// How each friend answers in the prototype, a few seconds after you write.
const _answers = <String, String>{
  'nour': 'haha you have to come next time',
  'layla': 'right?? my legs are still dead',
  'omar': 'thank you!! 🙏',
  'tarek': 'yes! saturday?',
  'sara': 'luna says hi 🐶',
  'maya': 'thanks, a bit nervous honestly',
  'dana': 'come at 8!',
};

/// Chats with an answer on its way, so one burst of messages gets one.
final Set<String> _answering = {};

/// Chats with something you have not read.
int _unreadChats() => _dms.values.where((d) => d.unread > 0).length;

/// You write [text] to [name]; [about] is the thought it answers, if any.
/// They answer a little later.
void _sayDirect(String name, String text, {_Quote? about}) {
  final dm = _dms.putIfAbsent(name, () => _Dm([]));
  dm.messages.add(_Msg('you', text, 'now', about: about));
  _chatTick.value++;
  if (!_answering.add(name)) return;
  _friendTimers.add(
    Timer(const Duration(seconds: 4), () {
      _answering.remove(name);
      dm.messages.add(_Msg(name, _answers[name] ?? 'sounds good 🙂', 'now'));
      dm.unread++;
      _chatTick.value++;
    }),
  );
}

/// What the line under [owner]'s post [post] shows: the newest message of
/// your chat with them, from your first reply to that post on, and your
/// reaction to it. Null until you replied or reacted.
(_Msg?, String?)? _replyLine(String owner, int post) {
  _Msg? last;
  final dm = _dms[owner];
  if (dm != null &&
      dm.messages.any(
        (m) => m.about?.author == owner && m.about?.post == post,
      )) {
    last = dm.messages.last;
  }
  final reaction = _myReactions['$owner#$post'];
  if (last == null && reaction == null) return null;
  return (last, reaction);
}

/// '40 min', '2 h', '1 d', '1 w' or 'now' as minutes, to put chats in order.
int _minutesAgo(String age) {
  if (age == 'now') return 0;
  final parts = age.split(' ');
  final n = int.tryParse(parts.first) ?? 0;
  return switch (parts.length > 1 ? parts[1] : '') {
    'min' => n,
    'h' => n * 60,
    'd' => n * 60 * 24,
    'w' => n * 60 * 24 * 7,
    _ => 0,
  };
}

/// Opens your chat with [name]. [quote] is a thought of theirs your next
/// message answers, until you drop it.
void _openDm(BuildContext context, String name, {_Quote? quote}) {
  HapticFeedback.selectionClick();
  FocusScope.of(context).unfocus();
  Navigator.of(context).push(_diveRoute(_DmScreen(name: name, quote: quote)));
}

/// [friend]'s new thought, as a reply to it would quote it; null when they
/// have nothing new. Opening it to answer means you have seen it.
_Quote? _freshQuote(_ProtoFriend friend) {
  if (!_isNew(friend)) return null;
  final posts = _threadOf(friend.name);
  if (posts.isEmpty) return null;
  _seenThoughts.add(friend.name);
  _seenTick.value++;
  return _Quote(friend.name, 0, _firstLine(posts.first));
}

void _openChats(BuildContext context) {
  HapticFeedback.selectionClick();
  Navigator.of(context).push(_diveRoute(const _ChatsPage()));
}

// ---------------------------------------------------------------------------
// Chats: what people sent you and what you are waiting for.
// ---------------------------------------------------------------------------

/// One row of requests from people who reached you through a friend on top,
/// opened and answered in place; then every conversation; then knocks you
/// sent that wait.
class _ChatsPage extends StatefulWidget {
  const _ChatsPage();

  @override
  State<_ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<_ChatsPage> {
  bool _requestsOpen = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _chatTick,
      builder: (context, _) {
        final names = [
          for (final e in _dms.entries)
            if (e.value.messages.isNotEmpty) e.key,
        ]..sort(
            (a, b) => _minutesAgo(
              _dms[a]!.messages.last.age,
            ).compareTo(_minutesAgo(_dms[b]!.messages.last.age)),
          );
        final waiting = [
          for (final r in _reaches.values)
            if (r.state != _ReachState.accepted) r,
        ];
        final empty = names.isEmpty && waiting.isEmpty && _requests.isEmpty;
        return Scaffold(
          key: const ValueKey('chats'),
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: _DiveHeader(trail: ['Chats'])),
                    IconButton(
                      key: const ValueKey('new-chat'),
                      tooltip: 'New chat',
                      icon: const Icon(Icons.edit_outlined, color: _ink),
                      onPressed: () => _openFriendsList(
                        context,
                        title: 'New chat',
                        onPick: (name) => _openDm(context, name),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                Expanded(
                  child: empty
                      ? const Center(
                          child: Text(
                            'Start from a friend on your orbit.',
                            style: TextStyle(color: _muted, fontSize: 14),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 16),
                          children: [
                            if (_requests.isNotEmpty)
                              _RequestsRow(
                                open: _requestsOpen,
                                onTap: () => setState(
                                  () => _requestsOpen = !_requestsOpen,
                                ),
                              ),
                            if (_requests.isNotEmpty && _requestsOpen) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Column(
                                  children: [
                                    for (final r in _requests)
                                      r.kind == _RequestKind.introAsk
                                          ? _IntroAskCard(request: r)
                                          : _RequestCard(request: r),
                                  ],
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Text(
                                  'Saying hi opens a chat. They won’t join '
                                  'your orbit or see your thoughts. Not now '
                                  'tells nobody.',
                                  style: _soft,
                                ),
                              ),
                            ],
                            for (final name in names) _ChatRow(name: name),
                            if (waiting.isNotEmpty) const _ListTitle('Waiting'),
                            for (final r in waiting) _WaitingRow(reach: r),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "3 requests": people who reached you through a friend. Tap to open them
/// here; hidden when there are none.
class _RequestsRow extends StatelessWidget {
  final bool open;
  final VoidCallback onTap;

  const _RequestsRow({required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final n = _requests.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: const Color(0xFF12301F),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const ValueKey('requests-row'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                const Icon(Icons.waving_hand_outlined, color: _accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    n == 1 ? '1 request' : '$n requests',
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  color: _muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small heading between the parts of Chats.
class _ListTitle extends StatelessWidget {
  final String text;

  const _ListTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: _muted,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    ),
  );
}

class _ChatRow extends StatelessWidget {
  final String name;

  const _ChatRow({required this.name});

  @override
  Widget build(BuildContext context) {
    final dm = _dms[name]!;
    final last = dm.messages.last;
    final unread = dm.unread > 0;
    final line = '${last.mine ? 'You: ' : ''}${last.text}';
    final color = unread ? _ink : _muted;
    return InkWell(
      key: ValueKey('chat-row-$name'),
      onTap: () => _openDm(context, name),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            _personPhoto(name, 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (dm.via != null) ...[
                        const SizedBox(width: 6),
                        _ViaChip(via: dm.via!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // A reply to a thought.
                      if (last.about != null) ...[
                        Icon(Icons.reply, size: 15, color: color),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 14,
                            fontWeight: unread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  last.age,
                  style: TextStyle(
                    color: unread ? _accent : _muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                if (unread)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${dm.unread}',
                      style: const TextStyle(
                        color: Color(0xFF03140A),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A knock you sent or an introduction you asked for, while nothing has
/// opened: how many days it has left, then "No reply".
class _WaitingRow extends StatelessWidget {
  final _Reach reach;

  const _WaitingRow({required this.reach});

  @override
  Widget build(BuildContext context) {
    final r = reach;
    final status = switch (r.state) {
      _ReachState.noReply => 'No reply',
      _ReachState.introduced =>
        '${r.via} introduced you · waiting for ${r.name}',
      _ when r.intro => 'Asked ${r.via} · ${_daysLeft(r.daysLeft)}',
      _ => 'Waiting for ${r.name} · ${_daysLeft(r.daysLeft)}',
    };
    return InkWell(
      key: ValueKey('waiting-${r.name}'),
      onTap: () => _openWorld(context, r.name),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Opacity(opacity: 0.55, child: _personPhoto(r.name, 48)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        r.name,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _ViaChip(via: r.via),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 14),
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

String _daysLeft(int days) => days == 1 ? '1 day left' : '$days days left';

/// "via omar": the friend who connects you with someone who is not your
/// friend.
class _ViaChip extends StatelessWidget {
  final String via;

  const _ViaChip({required this.via});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0x1AF2F4F3),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      'via $via',
      style: const TextStyle(
        color: Color(0xFFC9D1CC),
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// One chat.
// ---------------------------------------------------------------------------

class _DmScreen extends StatefulWidget {
  final String name;

  /// A thought of theirs the next message answers.
  final _Quote? quote;

  const _DmScreen({required this.name, this.quote});

  @override
  State<_DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends State<_DmScreen> {
  final TextEditingController _field = TextEditingController();
  late _Quote? _about = widget.quote;

  _Dm get _dm => _dms.putIfAbsent(widget.name, () => _Dm([]));

  @override
  void initState() {
    super.initState();
    _chatTick.addListener(_onChat);
    _markRead();
  }

  @override
  void dispose() {
    _chatTick.removeListener(_onChat);
    _field.dispose();
    super.dispose();
  }

  void _onChat() {
    if (!mounted) return;
    setState(() {});
    _markRead();
  }

  // Whatever arrives while the chat is open is read.
  void _markRead() {
    if (_dm.unread == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dm.unread == 0) return;
      _dm.unread = 0;
      _chatTick.value++;
    });
  }

  void _send() {
    final text = _field.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    _sayDirect(widget.name, text, about: _about);
    _field.clear();
    if (_about != null) setState(() => _about = null);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final dm = _dm;
    final via = dm.via;
    final messages = dm.messages;
    // A quote heads only the first reply to its thought.
    final items = <Widget>[
      if (via != null)
        _IntroducedNote(name: widget.name, via: via, line: dm.bridgeLine),
      for (var i = 0; i < messages.length; i++) ...[
        if (messages[i].about case final q?
            when !messages.take(i).any((m) => q.same(m.about)))
          _QuoteHeader(quote: q, mine: messages[i].mine),
        _ChatBubble(messages[i]),
      ],
    ];
    return Scaffold(
      backgroundColor: const Color(0xE60C0E14),
      body: Padding(
        padding: EdgeInsets.only(top: pad.top, bottom: keyboard),
        child: Column(
          children: [
            _ChatHeader(widget.name, via: via),
            Expanded(
              child: ListView(
                key: ValueKey('dm-${widget.name}'),
                reverse: true,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                children: items.reversed.toList(),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                10,
                0,
                10,
                keyboard > 0 ? 8 : pad.bottom + 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_about case final q?)
                    _QuoteChip(
                      quote: q,
                      onDrop: () => setState(() => _about = null),
                    ),
                  _Composer(
                    controller: _field,
                    hint: _about == null
                        ? 'Message ${widget.name}…'
                        : 'Reply to ${widget.name}…',
                    onSend: _send,
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

/// The thought your next message answers, over the field; × sends a plain
/// message instead.
class _QuoteChip extends StatelessWidget {
  final _Quote quote;
  final VoidCallback onDrop;

  const _QuoteChip({required this.quote, required this.onDrop});

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('quote-chip'),
    margin: const EdgeInsets.fromLTRB(6, 0, 6, 8),
    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
    decoration: BoxDecoration(
      color: const Color(0xFF1E2026),
      borderRadius: BorderRadius.circular(14),
      border: Border(left: BorderSide(color: _hueOf(quote.author), width: 3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.reply, size: 16, color: _muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            quote.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _ink, fontSize: 13.5),
          ),
        ),
        IconButton(
          key: const ValueKey('drop-quote'),
          tooltip: 'Send without the thought',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 18, color: _muted),
          onPressed: onDrop,
        ),
      ],
    ),
  );
}

/// A rounded text field with a send button, as at the bottom of a chat.
class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.hint,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2026),
        borderRadius: BorderRadius.circular(29),
        border: Border.all(color: const Color(0x1FF2F4F3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: _ink, fontSize: 16),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF8A8F98)),
                filled: true,
                fillColor: const Color(0x0FFFFFFF),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton.filled(
              key: const ValueKey('send'),
              tooltip: 'Send',
              style: IconButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF04110A),
              ),
              icon: const Icon(Icons.send_rounded, size: 20),
              onPressed: onSend,
            ),
          ),
        ],
      ),
    );
  }
}

/// The top of a chat: back, who it is with, and that nobody else sees it.
class _ChatHeader extends StatelessWidget {
  final String other;

  /// For someone who is not your friend: the friend who connects you.
  final String? via;

  const _ChatHeader(this.other, {this.via});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back, color: _ink),
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).maybePop();
          },
        ),
        GestureDetector(
          onTap: () => _openWorld(context, other, fromChat: true),
          child: _personPhoto(other, 34),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      other,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (via != null) ...[
                    const SizedBox(width: 6),
                    _ViaChip(via: via!),
                  ],
                ],
              ),
              Row(
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 12,
                    color: Color(0xFFA9B1AC),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Only you and $other see this',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFA9B1AC),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// At the top of a chat with someone you met through a friend: how you met,
/// and what it does not open.
class _IntroducedNote extends StatelessWidget {
  final String name;
  final String via;
  final String? line;

  const _IntroducedNote({required this.name, required this.via, this.line});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('introduced-note'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0x0DF2F4F3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            line != null
                ? '$via introduced you: “$line”'
                : 'You and $name reached each other via $via.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 13.5, height: 1.35),
          ),
          const SizedBox(height: 6),
          const Text(
            'A chat only. Neither of you joins the other’s orbit or sees '
            'the other’s thoughts.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12.5, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// The compact quote on the first reply to a thought. While the thought is
/// live it opens it; once gone it says so and keeps the words.
class _QuoteHeader extends StatelessWidget {
  final _Quote quote;

  /// Sits over your own message (right) or theirs (left).
  final bool mine;

  const _QuoteHeader({required this.quote, required this.mine});

  @override
  Widget build(BuildContext context) {
    final q = quote;
    final hue = q.author == 'you' ? _accent : _hueOf(q.author);
    final whose = q.author == 'you' ? 'Your thought' : '${q.author}’s thought';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        key: ValueKey('quote-${q.author}${q.post}'),
        onTap: q.gone ? null : () => _openQuoted(context, q),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 270),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 8),
          decoration: BoxDecoration(
            color: const Color(0x0FF2F4F3),
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: hue, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.reply, size: 14, color: hue),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '$whose${q.gone ? ' · gone' : ''}',
                      style: TextStyle(
                        color: hue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                q.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFC9D1CC),
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the thought a quote points at, if it is still there.
void _openQuoted(BuildContext context, _Quote q) {
  if (q.author == 'you') {
    final i = _yourThoughts.indexWhere((t) => t.id == q.post);
    if (i >= 0) _openThought(context, 'you', i);
    return;
  }
  _openThought(context, q.author, q.post);
}

class _ChatBubble extends StatelessWidget {
  final _Msg message;

  const _ChatBubble(this.message);

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 270),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: mine ? const Color(0xFF1E3A2B) : const Color(0xFF24262C),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 6),
                  bottomRight: Radius.circular(mine ? 6 : 18),
                ),
              ),
              child: Text(
                message.text,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15.5,
                  height: 1.35,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 3, 4, 0),
            child: Text(
              _ago(message.age),
              style: const TextStyle(color: Color(0xFF8A938E), fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line under a post: your own chat with its author, never anyone
/// else's. Tap to open that chat.
class _ReplyLine extends StatelessWidget {
  static const double height = 34;

  final String owner;
  final int post;
  final double k;

  const _ReplyLine({required this.owner, required this.post, required this.k});

  @override
  Widget build(BuildContext context) {
    final line = _replyLine(owner, post);
    if (line == null) return SizedBox(height: height * k);
    final (msg, reaction) = line;
    final text = msg == null
        ? 'You reacted $reaction'
        : '${msg.mine ? 'You' : owner}: ${msg.text}';
    const lift = [Shadow(color: Color(0xB3000000), blurRadius: 10)];
    return GestureDetector(
      key: ValueKey('reply-line-$owner'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDm(context, owner),
      child: SizedBox(
        height: height * k,
        child: Row(
          children: [
            Icon(Icons.reply, size: 15 * k, color: const Color(0xFFA9B1AC)),
            SizedBox(width: 6 * k),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFFC9D1CC),
                  fontSize: 13 * k,
                  shadows: lift,
                ),
              ),
            ),
            if (msg != null && reaction != null) ...[
              SizedBox(width: 6 * k),
              Text(reaction, style: TextStyle(fontSize: 13 * k)),
            ],
            Icon(Icons.chevron_right, size: 18 * k, color: _muted),
          ],
        ),
      ),
    );
  }
}
