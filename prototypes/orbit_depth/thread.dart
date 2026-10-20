part of 'orbit_depth_prototype_screen.dart';

// One thought, full screen: what the card on the orbit shows, with room for
// all of it. Replying sends a message to your chat with its author; nobody
// else sees it, and there is no thread under the thought.

/// Friends whose new thought you have seen: it loses its dot, and their face
/// steps back on the orbit.
final Set<String> _seenThoughts = {};

/// Ticks when a thought is seen.
final ValueNotifier<int> _seenTick = ValueNotifier(0);

/// Whether [friend]'s thought is new to you.
bool _isNew(_ProtoFriend friend) =>
    friend.fresh && !_seenThoughts.contains(friend.name);

/// Opens [owner]'s post [post] (0 is the newest; for 'you', the index in
/// your thoughts).
void _openThought(BuildContext context, String owner, int post) {
  HapticFeedback.selectionClick();
  if (owner != 'you' && post == 0 && _seenThoughts.add(owner)) {
    _seenTick.value++;
  }
  Navigator.of(
    context,
  ).push(_diveRoute(_ThoughtPage(owner: owner, post: post)));
}

/// [owner]'s posts, newest first: the live thought (with all its slides)
/// and then the older ones.
List<_Post> _threadOf(String owner) {
  final friend = _friendNamed(owner);
  final thoughts = _thoughtsOf(owner);
  return [
    for (var i = 0; i < thoughts.length; i++)
      if (i == 0 && thoughts[i].live && friend != null)
        _livePost(friend)
      else
        _pastPost(owner, thoughts[i]),
  ];
}

/// The colour someone is marked with.
Color _hueOf(String owner) =>
    _friendNamed(owner)?.hue.color ?? _fofOf(owner)?.hue.color ?? _accent;

/// The first line of [post], as a quote keeps it.
String _firstLine(_Post post) =>
    post.paragraphs.isEmpty ? '' : post.paragraphs.first;

class _ThoughtPage extends StatefulWidget {
  final String owner;
  final int post;

  const _ThoughtPage({required this.owner, required this.post});

  @override
  State<_ThoughtPage> createState() => _ThoughtPageState();
}

/// A short thought with nothing attached reads full screen as a quote:
/// large and centred, since no face above it holds its place.
bool _isQuote(_Post post) =>
    post.attachments.isEmpty &&
    post.space == null &&
    post.paragraphs.length == 1 &&
    post.paragraphs.first.length <= 90;

class _ThoughtPageState extends State<_ThoughtPage> {
  late final List<_Post> _posts = _threadOf(widget.owner);
  late final int _index = widget.post.clamp(0, _posts.length - 1);
  final TextEditingController _field = TextEditingController();

  bool get _mine => widget.owner == 'you';

  @override
  void initState() {
    super.initState();
    _chatTick.addListener(_onChat);
    _yourTick.addListener(_onChat);
  }

  @override
  void dispose() {
    _chatTick.removeListener(_onChat);
    _yourTick.removeListener(_onChat);
    _field.dispose();
    super.dispose();
  }

  void _onChat() {
    if (mounted) setState(() {});
  }

  void _send() {
    final text = _field.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    _sayDirect(
      widget.owner,
      text,
      about: _Quote(widget.owner, _index, _firstLine(_posts[_index])),
    );
    _field.clear();
    _notify('In your chat with ${widget.owner}');
  }

  @override
  Widget build(BuildContext context) {
    final post = _posts[_index];
    final owner = widget.owner;
    final pad = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Padding(
        padding: EdgeInsets.only(top: pad.top, bottom: keyboard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back, color: _ink),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  GestureDetector(
                    onTap: _mine ? null : () => _openWorld(context, owner),
                    child: _personPhoto(owner, 34),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_mine ? 'Your thought' : owner} · ${_ago(post.age)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isQuote(post))
              Expanded(
                child: Center(
                  key: ValueKey('thought-$owner-$_index'),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          onLongPressStart: _mine
                              ? null
                              : (d) => _reactAt(
                                  context,
                                  d.globalPosition,
                                  owner,
                                  _index,
                                ),
                          child: Text(
                            post.paragraphs.first,
                            key: ValueKey('quote-$owner-$_index'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _chat.textPrimary,
                              fontSize: 30,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_mine)
                          _YourThoughtStats(id: _yourThoughts[_index].id)
                        else if (_replyLine(owner, _index) != null)
                          _ReplyLine(owner: owner, post: _index, k: 1),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  key: ValueKey('thought-$owner-$_index'),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    _PostCard(
                      post: post,
                      maxHeight: 2000,
                      expand: 1,
                      k: OrbitDepthTuning.cardScale,
                      alpha: 1,
                      front: false,
                      onOpen: () {},
                      onReact: _mine
                          ? null
                          : (at) => _reactAt(context, at, owner, _index),
                      onSpace: post.space == null
                          ? null
                          : () => _openSpace(context, owner, post.space!),
                    ),
                    if (_mine)
                      _YourThoughtStats(id: _yourThoughts[_index].id)
                    else if (_replyLine(owner, _index) != null)
                      _ReplyLine(owner: owner, post: _index, k: 1),
                  ],
                ),
              ),
            if (!_mine)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  10,
                  0,
                  10,
                  keyboard > 0 ? 8 : pad.bottom + 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                      child: Row(
                        key: const ValueKey('private-reply'),
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            size: 13,
                            color: _accent,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'write to $owner · only they see it',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFC7CEC9),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Composer(
                      controller: _field,
                      hint: '→ @$owner',
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
