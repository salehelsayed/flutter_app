part of 'orbit_depth_prototype_screen.dart';

// Replies are private: a reply to someone's post starts a chat between you
// and its author about that post, and nobody else sees it. Someone else's
// post shows no counts, only a link to your own chat about it; your own post
// shows its reactions and every friend who wrote to you about it.

class _Msg {
  final String from;
  final String text;
  final String age;

  const _Msg(this.from, this.text, this.age);

  bool get mine => from == 'you';
}

class _PrivateChat {
  final List<_Msg> messages;

  /// Your reaction, on someone else's post.
  final String? reaction;
  bool unread;

  _PrivateChat(this.messages, {this.reaction, this.unread = false});
}

/// Chats keyed '$author#$post@$friend': the author and one friend, about one
/// of the author's posts (0 is the newest). They last while the prototype
/// runs.
final Map<String, _PrivateChat> _privateChats = {};

/// Sample conversations, so the prototype has something to show.
final Map<String, _PrivateChat Function()> _seedChats = {
  'layla#1@you': () => _PrivateChat(const [
    _Msg('you', 'me! saturday evening?', '2 h'),
    _Msg('layla', 'yes!! 7pm at the Vox?', '1 h'),
    _Msg('you', 'perfect, I’ll bring snacks', '40 min'),
  ], reaction: '😍'),
  'you#0@omar': () => _PrivateChat(const [
    _Msg('omar', 'that pace is great. sunday run?', '1 h'),
  ], unread: true),
  'you#0@nour': () => _PrivateChat(const [
    _Msg('nour', 'proud of you!!', '3 h'),
  ], unread: true),
  'you#0@tarek': () => _PrivateChat(const [
    _Msg('tarek', '28:55?! nice', '6 h'),
    _Msg('you', 'thanks man, see you there', '5 h'),
  ]),
  'you#1@layla': () => _PrivateChat(const [
    _Msg('layla', 'that chapter broke me too', '1 d'),
  ]),
};

_PrivateChat _privateChatFor(String author, int post, String friend) {
  final key = '$author#$post@$friend';
  return _privateChats.putIfAbsent(
    key,
    () => _seedChats[key]?.call() ?? _PrivateChat([]),
  );
}

/// Who reacted to your own posts, and with what.
const Map<int, Map<String, int>> _ownReactions = {
  0: {'😍': 5, '👏': 3, '🔥': 2},
  1: {'😂': 4, '🤯': 2},
};
const Map<int, List<String>> _ownReactors = {
  0: ['omar', 'nour', 'layla', 'tarek', 'sara'],
  1: ['layla', 'dana'],
};

/// Friends who wrote to you about your post [post], most recent first.
List<String> _repliersTo(int post) {
  final friends = <String>[];
  for (final key in {..._seedChats.keys, ..._privateChats.keys}) {
    if (!key.startsWith('you#$post@')) continue;
    final friend = key.split('@').last;
    if (friend == 'you' || friends.contains(friend)) continue;
    if (_privateChatFor('you', post, friend).messages.isNotEmpty) friends.add(friend);
  }
  return friends;
}

/// The one-line link under a post that opens its private side, or null when
/// there is nothing to open yet.
String? _privateLinkLabel(String owner, int post) {
  if (owner == 'you') {
    final reactions = _ownReactions[post] ?? const {};
    final repliers = _repliersTo(post);
    if (reactions.isEmpty && repliers.isEmpty) return null;
    final top = (reactions.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .map((e) => e.key)
        .join(' ');
    final total = reactions.values.fold(0, (a, b) => a + b);
    final replies = repliers.length == 1
        ? '1 reply'
        : '${repliers.length} replies';
    return reactions.isEmpty ? '$replies  ›' : '$top  $total  ·  $replies  ›';
  }
  final n = _privateChatFor(owner, post, 'you').messages.length;
  if (n == 0) return null;
  return n == 1
      ? '1 message with $owner  ›'
      : '$n messages with $owner  ›';
}

Future<void> _openPrivateChat(
  BuildContext context, {
  required String author,
  required int post,
  required String friend,
  required _Post about,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF15171C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _PrivateChatSheet(
      author: author,
      post: post,
      friend: friend,
      about: about,
    ),
  );
}

Future<void> _openActivity(BuildContext context, int post, _Post about) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF15171C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _ActivitySheet(post: post, about: about),
  );
}

/// The post a private sheet is about, quoted at its top.
class _QuotedPost extends StatelessWidget {
  final String author;
  final _Post about;

  const _QuotedPost({required this.author, required this.about});

  @override
  Widget build(BuildContext context) {
    final hue = author == 'you' ? _accent : _hueOf(author);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0x0DF2F4F3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: hue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          _personPhoto(author, 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${author == 'you' ? 'your post' : author} · ${about.age} ago',
                  style: TextStyle(
                    color: hue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  about.paragraphs.isEmpty ? '' : about.paragraphs.first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFDDE2DF), fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlyYouTwo extends StatelessWidget {
  final String other;

  const _OnlyYouTwo(this.other);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.lock_outline, size: 14, color: Color(0xFFA9B1AC)),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          'Only you and $other see this',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFFA9B1AC), fontSize: 13),
        ),
      ),
    ],
  );
}

/// Your private chat with one person about one post.
class _PrivateChatSheet extends StatefulWidget {
  final String author;
  final int post;
  final String friend;
  final _Post about;

  const _PrivateChatSheet({
    required this.author,
    required this.post,
    required this.friend,
    required this.about,
  });

  @override
  State<_PrivateChatSheet> createState() => _PrivateChatSheetState();
}

class _PrivateChatSheetState extends State<_PrivateChatSheet> {
  final TextEditingController _field = TextEditingController();
  late final _PrivateChat _thread = _privateChatFor(
    widget.author,
    widget.post,
    widget.friend,
  );

  /// The other person in this chat.
  String get _other =>
      widget.author == 'you' ? widget.friend : widget.author;

  @override
  void initState() {
    super.initState();
    _thread.unread = false;
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _send() {
    final text = _field.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _thread.messages.add(_Msg('you', text, 'now')));
    _field.clear();
  }

  @override
  Widget build(BuildContext context) {
    final reaction = _thread.reaction;
    final height = MediaQuery.sizeOf(context).height * 0.62;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        key: const ValueKey('private-chat'),
        height: height,
        child: Column(
          children: [
            _OnlyYouTwo(_other),
            const SizedBox(height: 12),
            _QuotedPost(author: widget.author, about: widget.about),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                children: [
                  if (reaction != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'You reacted $reaction',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF8A938E),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  for (final m in _thread.messages) _ChatBubble(m),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                10,
                0,
                10,
                MediaQuery.viewInsetsOf(context).bottom > 0
                    ? 8
                    : MediaQuery.paddingOf(context).bottom + 8,
              ),
              child: Container(
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
                        controller: _field,
                        style: const TextStyle(color: _ink, fontSize: 16),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Message $_other…',
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
                        tooltip: 'Send message',
                        style: IconButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: const Color(0xFF04110A),
                        ),
                        icon: const Icon(Icons.send_rounded, size: 20),
                        onPressed: _send,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
              message.age == 'now' ? 'now' : '${message.age} ago',
              style: const TextStyle(color: Color(0xFF8A938E), fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Your own post's reactions and the friends who wrote to you about it.
class _ActivitySheet extends StatefulWidget {
  final int post;
  final _Post about;

  const _ActivitySheet({required this.post, required this.about});

  @override
  State<_ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<_ActivitySheet> {
  Future<void> _openChat(String friend) async {
    await _openPrivateChat(
      context,
      author: 'you',
      post: widget.post,
      friend: friend,
      about: widget.about,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(
      color: Color(0xFFA9B1AC),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    final reactions = (_ownReactions[widget.post] ?? const {}).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final reactors = _ownReactors[widget.post] ?? const [];
    final total = reactions.fold(0, (a, e) => a + e.value);
    final repliers = _repliersTo(widget.post);
    return SizedBox(
      key: const ValueKey('post-activity'),
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          0,
          0,
          0,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        children: [
          _QuotedPost(author: 'you', about: widget.about),
          if (reactions.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Text('Reactions', style: label),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in reactions)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x12F2F4F3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${r.key} ',
                              style: const TextStyle(fontSize: 15),
                            ),
                            TextSpan(
                              text: '${r.value}',
                              style: const TextStyle(
                                color: Color(0xFFC9CFCB),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 24.0 + 20 * (math.min(reactors.length, 5) - 1),
                    height: 28,
                    child: Stack(
                      children: [
                        for (var i = 0; i < math.min(reactors.length, 5); i++)
                          Positioned(
                            left: 20.0 * i,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF15171C),
                                  width: 2,
                                ),
                              ),
                              child: _personPhoto(reactors[i], 24),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      reactors.length <= 2
                          ? reactors.join(' and ')
                          : '${reactors.take(2).join(', ')} and ${total - 2} others',
                      style: const TextStyle(
                        color: Color(0xFF8A938E),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Divider(height: 1, color: Color(0x14F2F4F3)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: Color(0xFFA9B1AC),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    repliers.isEmpty
                        ? 'No replies yet'
                        : 'Replies · each one is a private chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: label,
                  ),
                ),
              ],
            ),
          ),
          for (final friend in repliers) _replierRow(friend),
        ],
      ),
    );
  }

  Widget _replierRow(String friend) {
    final chat = _privateChatFor('you', widget.post, friend);
    final last = chat.messages.last;
    final unread = chat.unread;
    return InkWell(
      onTap: () => _openChat(friend),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _personPhoto(friend, 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    last.mine ? 'you: ${last.text}' : last.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unread
                          ? const Color(0xFFDDE2DF)
                          : const Color(0xFF8A938E),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              last.age == 'now' ? 'now' : last.age,
              style: const TextStyle(color: Color(0xFF8A938E), fontSize: 12.5),
            ),
            const SizedBox(width: 8),
            if (unread)
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                ),
              )
            else
              const SizedBox(width: 9),
          ],
        ),
      ),
    );
  }
}
