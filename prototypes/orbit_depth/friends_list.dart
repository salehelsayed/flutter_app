part of 'orbit_depth_prototype_screen.dart';

// The 2D layout: the same people as the orbit, as a list. It opens from the
// "+N" slot and from New chat, and replaces the orbit when Reduce Motion is
// on. Close is a row of faces at the top; Friends is a searchable list with
// each person's thought and who you can reach through them.

void _openFriendsList(
  BuildContext context, {
  String title = 'Friends',
  ValueChanged<String>? onPick,
}) {
  HapticFeedback.selectionClick();
  Navigator.of(
    context,
  ).push(_diveRoute(_FriendsListPage(title: title, onPick: onPick)));
}

class _FriendsListPage extends StatefulWidget {
  final String title;

  /// Picking someone (New chat); null opens your chat with them.
  final ValueChanged<String>? onPick;

  const _FriendsListPage({
    this.title = 'Friends',
    this.onPick,
  });

  @override
  State<_FriendsListPage> createState() => _FriendsListPageState();
}

class _FriendsListPageState extends State<_FriendsListPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pick(String name) {
    final onPick = widget.onPick;
    if (onPick == null) {
      _openDm(context, name);
      return;
    }
    Navigator.of(context).pop();
    onPick(name);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: Listenable.merge([_seenTick, _ringTick, _chatTick]),
          builder: (context, _) {
            final close = [
              for (final f in _everyone)
                if (f.layer == 0) f,
            ];
            // Unseen thoughts first, then everyone in the order you talk.
            final friends = [
              for (final f in _everyone)
                if (_isNew(f) && (query.isNotEmpty || f.layer == 1)) f,
              for (final f in _everyone)
                if (!_isNew(f) && (query.isNotEmpty || f.layer == 1)) f,
            ].where((f) => f.name.contains(query)).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DiveHeader(trail: [widget.title]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    key: const ValueKey('friends-search'),
                    controller: _search,
                    style: const TextStyle(color: _ink, fontSize: 15.5),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: const TextStyle(color: Color(0xFF8A8F98)),
                      prefixIcon: const Icon(Icons.search, color: _muted),
                      filled: true,
                      fillColor: const Color(0x14FFFFFF),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (query.isEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                          child: Text('Close', style: _soft),
                        ),
                        SizedBox(
                          height: 86,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            children: [
                              for (final f in close)
                                _CloseFace(friend: f, onTap: () => _pick(f.name)),
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                          child: Text('Friends', style: _soft),
                        ),
                      ],
                      for (final f in friends)
                        _FriendRow(friend: f, onTap: () => _pick(f.name)),
                      if (friends.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No one by that name.',
                            textAlign: TextAlign.center,
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

class _CloseFace extends StatelessWidget {
  final _ProtoFriend friend;
  final VoidCallback onTap;

  const _CloseFace({required this.friend, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: ValueKey('close-face-${friend.name}'),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _personPhoto(friend.name, 56),
              if (_isNew(friend))
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: _ground, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(friend.name, style: const TextStyle(color: _ink, fontSize: 12)),
        ],
      ),
    ),
  );
}

/// A friend in the list: their thought, and who you can reach through them.
class _FriendRow extends StatelessWidget {
  final _ProtoFriend friend;
  final VoidCallback onTap;

  const _FriendRow({required this.friend, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final f = friend;
    final thought = f.thought;
    final reach = _reachVia(f.name);
    return InkWell(
      key: ValueKey('friend-row-${f.name}'),
      onTap: onTap,
      onLongPress: () => _openFriendMenu(context, f),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _personPhoto(f.name, 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.name,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (thought != null)
                    GestureDetector(
                      onTap: () => _openThought(context, f.name, 0),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            if (_isNew(f)) ...[
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: _accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                thought,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _isNew(f) ? _ink : _chatSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (reach.isNotEmpty)
                    GestureDetector(
                      onTap: () => _openReach(context, via: f.name),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '${_peopleVia(reach.length, f.name)}  ›',
                          style: const TextStyle(
                            color: _accent,
                            fontSize: 12.5,
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
    );
  }
}

/// Holding a face: move them between your rings, their world, or a chat.
Future<void> _openFriendMenu(BuildContext context, _ProtoFriend friend) {
  final name = friend.name;
  final close = _closeNames.contains(name);
  final full = !close && _closeNames.length >= _closeLimit;
  return _openSheet(
    context,
    Builder(
      builder: (sheet) {
        Widget row(String key, IconData icon, String text, VoidCallback? on) =>
            ListTile(
              key: ValueKey(key),
              enabled: on != null,
              leading: Icon(icon, color: on == null ? _muted : _ink),
              title: Text(
                text,
                style: TextStyle(color: on == null ? _muted : _ink),
              ),
              onTap: on == null
                  ? null
                  : () {
                      Navigator.of(sheet).pop();
                      on();
                    },
            );
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(sheet).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _personPhoto(name, 32),
                    const SizedBox(width: 10),
                    Text(
                      name,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              row(
                'menu-close',
                close ? Icons.remove_circle_outline : Icons.star_outline,
                close
                    ? 'Move to Friends'
                    : full
                    ? 'Close is full ($_closeLimit)'
                    : 'Move to Close',
                full ? null : () => _setClose(name, !close),
              ),
              row(
                'menu-world',
                Icons.public,
                'Their world',
                () => _openWorld(context, name),
              ),
              row(
                'menu-chat',
                Icons.chat_bubble_outline,
                'Chat',
                () => _openDm(context, name),
              ),
            ],
          ),
        );
      },
    ),
  );
}
