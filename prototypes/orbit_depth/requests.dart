part of 'orbit_depth_prototype_screen.dart';

// Requests: people who reached you through a friend, and friends asking you
// to introduce them. They wait at the top of Chats until you decide.
// Saying hi opens a chat; Not now and Skip tell nobody.

enum _RequestKind { knock, introduction, introAsk }

class _Request {
  final _RequestKind kind;

  /// Who reached out (or, for an introduction ask, the friend asking).
  final String name;

  /// The friends who connect you; more than one when several carry them.
  final List<String> via;
  final String topic;
  final String note;
  final String age;

  /// An introduction: what the friend between you said about them.
  final String? bridgeLine;

  /// An introduction ask: who your friend wants to meet.
  final String? target;

  const _Request(
    this.kind,
    this.name, {
    this.via = const [],
    required this.topic,
    required this.note,
    required this.age,
    this.bridgeLine,
    this.target,
  });
}

/// Waiting for you, newest first.
final List<_Request> _requests = _seedRequests();

List<_Request> _seedRequests() => [
  const _Request(
    _RequestKind.knock,
    'yazan',
    via: ['layla', 'sami'],
    topic: 'books',
    note: 'layla says you’re the one to ask about Kahneman. coffee sometime?',
    age: '10 min',
  ),
  const _Request(
    _RequestKind.introduction,
    'munir',
    via: ['maya'],
    topic: 'career advice',
    note: 'maya mentioned the new job. happy to share what helped me.',
    age: '2 h',
    bridgeLine: 'my old manager, the best mentor I had',
  ),
  const _Request(
    _RequestKind.introAsk,
    'zein',
    topic: 'dog walks',
    note: 'adopting a dog soon. would love to ask about luna',
    age: '1 h',
    target: 'sara',
  ),
];

/// People you blocked: their messages hide, their knocks are refused and
/// their branches go.
final Set<String> _blocked = {};

/// Friends you no longer take requests through.
final Set<String> _pausedBridges = {};

/// The knock or introduction [name] sent you, while you have not answered.
_Request? _requestFrom(String name) {
  for (final r in _requests) {
    if (r.name == name && r.kind != _RequestKind.introAsk) return r;
  }
  return null;
}

/// "layla" or "layla and sami".
String _viaNames(List<String> via) => via.length < 2
    ? via.join()
    : '${via.sublist(0, via.length - 1).join(', ')} and ${via.last}';

void _sayHi(BuildContext context, _Request r) {
  HapticFeedback.lightImpact();
  _requests.remove(r);
  _dms[r.name] = _Dm(
    [_Msg(r.name, r.note, r.age)],
    via: r.via.first,
    bridgeLine: r.bridgeLine,
  );
  _chatTick.value++;
  _openDm(context, r.name);
}

void _dismiss(_Request r) {
  HapticFeedback.selectionClick();
  _requests.remove(r);
  _chatTick.value++;
}

/// Someone who reached you through a friend: who, through whom, about what,
/// and their line.
class _RequestCard extends StatelessWidget {
  final _Request request;

  const _RequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Container(
      key: ValueKey('request-${r.name}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 10),
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
              _personPhoto(r.name, 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  r.name,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('via ${_viaNames(r.via)}', style: _soft),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (r.bridgeLine case final line?) ...[
            Text(
              '${r.via.first} introduced you: “$line”',
              style: const TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text('About ${r.topic} · ${r.age}', style: _soft),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '“${r.note}”',
              style: const TextStyle(color: _ink, fontSize: 15, height: 1.35),
            ),
          ),
          GestureDetector(
            onTap: () => _openWorld(context, r.name),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'See ${r.name}’s world  ›',
                style: const TextStyle(
                  color: _accent,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Row(
            children: [
              OutlinedButton(
                key: ValueKey('not-now-${r.name}'),
                onPressed: () => _dismiss(r),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  side: const BorderSide(color: Color(0x33F2F4F3)),
                ),
                child: const Text('Not now'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: ValueKey('say-hi-${r.name}'),
                onPressed: () => _sayHi(context, r),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: const Color(0xFF04110A),
                ),
                child: const Text(
                  'Say hi',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              IconButton(
                key: ValueKey('request-more-${r.name}'),
                visualDensity: VisualDensity.compact,
                tooltip: 'More',
                icon: const Icon(Icons.more_horiz, color: _muted),
                onPressed: () => _openSheet(context, _RequestMore(request: r)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Block, pause requests through a friend, or tell that friend.
class _RequestMore extends StatelessWidget {
  final _Request request;

  const _RequestMore({required this.request});

  @override
  Widget build(BuildContext context) {
    final r = request;
    final via = r.via.first;
    Widget row(String key, IconData icon, String text, VoidCallback onTap) =>
        ListTile(
          key: ValueKey(key),
          leading: Icon(icon, color: _ink),
          title: Text(text, style: const TextStyle(color: _ink)),
          onTap: () {
            Navigator.of(context).pop();
            onTap();
          },
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row('block-${r.name}', Icons.block, 'Block ${r.name}', () {
            _blocked.add(r.name);
            _dismiss(r);
          }),
          row('pause-$via', Icons.pause_circle_outline,
              'Pause requests via $via', () {
            _pausedBridges.add(via);
            _requests.removeWhere(
              (q) => q.kind != _RequestKind.introAsk && q.via.contains(via),
            );
            _chatTick.value++;
          }),
          row('report-$via', Icons.flag_outlined, 'Report to $via', () {
            _dismiss(r);
            _notify('$via gets a private note naming ${r.name}');
          }),
        ],
      ),
    );
  }
}

/// A friend asks you to introduce them to another friend of yours. Skip is
/// silent; Introduce sends your friend a request carrying your line.
class _IntroAskCard extends StatefulWidget {
  final _Request request;

  const _IntroAskCard({required this.request});

  @override
  State<_IntroAskCard> createState() => _IntroAskCardState();
}

class _IntroAskCardState extends State<_IntroAskCard> {
  final TextEditingController _line = TextEditingController();

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final target = r.target!;
    return Container(
      key: ValueKey('intro-ask-${r.name}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
              _personPhoto(r.name, 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${r.name} asks for an introduction to $target',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('About ${r.topic} · ${r.age}', style: _soft),
          const SizedBox(height: 6),
          Text(
            '“${r.note}”',
            style: const TextStyle(color: _ink, fontSize: 15, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _line,
            maxLength: 120,
            style: const TextStyle(color: _ink, fontSize: 14.5),
            decoration: InputDecoration(
              labelText: 'Add a line for $target (optional)',
              labelStyle: _soft,
              hintText: 'e.g. my cousin, good person',
              hintStyle: const TextStyle(color: Color(0xFF6E7570)),
              counterStyle: _soft,
              filled: true,
              fillColor: const Color(0x0FFFFFFF),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: ValueKey('skip-${r.name}'),
                onPressed: () => _dismiss(r),
                style: TextButton.styleFrom(foregroundColor: _muted),
                child: const Text('Skip'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: ValueKey('introduce-${r.name}'),
                onPressed: () {
                  _dismiss(r);
                  _notify('Introduced. $target decides.');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: const Color(0xFF04110A),
                ),
                child: const Text(
                  'Introduce',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
