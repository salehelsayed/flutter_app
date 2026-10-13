part of 'orbit_depth_prototype_screen.dart';

// Their world: who someone is, as a calm scrolling page. For a friend, the
// thoughts they shared with you in the last 30 days and their Spaces. For a
// friend of a friend, only the Spaces they opened to friends of friends,
// how you can reach them, and nothing else.

/// [fromChat]: opened from your chat with [owner], so its Chat button goes
/// back there instead of opening a second one.
void _openWorld(BuildContext context, String owner, {bool fromChat = false}) {
  HapticFeedback.selectionClick();
  FocusScope.of(context).unfocus();
  Navigator.of(
    context,
  ).push(_diveRoute(_WorldPage(owner: owner, fromChat: fromChat)));
}

class _WorldPage extends StatelessWidget {
  final String owner;
  final bool fromChat;

  const _WorldPage({required this.owner, this.fromChat = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_chatTick, _ringTick]),
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DiveHeader(trail: [owner]),
              Expanded(
                child: ListView(
                  key: ValueKey('world-$owner'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: _isFriend(owner)
                      ? _friendWorld(context)
                      : _strangerWorld(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _top({required String subtitle, required List<Widget> actions}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _personPhoto(owner, 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      owner,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _chatSecondary,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
          const SizedBox(height: 24),
        ],
      );

  List<Widget> _friendWorld(BuildContext context) {
    final close = _closeNames.contains(owner);
    final thoughts = _thoughtsOf(owner);
    final spaces = _spacesFor(owner);
    final reach = _reachVia(owner);
    return [
      _top(
        subtitle: close ? 'Close friend' : 'Friend',
        actions: [
          FilledButton.icon(
            key: const ValueKey('world-chat'),
            onPressed: () => fromChat
                ? Navigator.of(context).maybePop()
                : _openDm(context, owner),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: const Color(0xFF04110A),
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text(
              'Chat',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (reach.isNotEmpty)
            TextButton(
              onPressed: () => _openReach(context, via: owner),
              style: TextButton.styleFrom(foregroundColor: _accent),
              child: Text('${_peopleVia(reach.length, owner)}  ›'),
            ),
        ],
      ),
      const _SectionTitle('Thoughts', 'Last 30 days, as shared with you'),
      if (thoughts.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: Text('Nothing shared lately.', style: _soft),
        ),
      for (var i = 0; i < thoughts.length; i++)
        _ThoughtRow(owner: owner, index: i, thought: thoughts[i]),
      if (spaces.isNotEmpty) ...[
        const SizedBox(height: 12),
        const _SectionTitle('Spaces', null),
        for (final space in spaces)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SpaceCard(
              owner: owner,
              space: space,
              onDive: () => _openSpace(context, owner, space.title),
            ),
          ),
      ],
    ];
  }

  List<Widget> _strangerWorld(BuildContext context) {
    final fof = _fofOf(owner);
    if (fof == null) return const [];
    final via = fof.via;
    final reachable =
        _reachable().contains(fof) || _dms.containsKey(owner);
    final spaces = _spacesFor(owner);
    final hidden = fof.friendsOnlySpaces;
    final label = _reachLabel(owner);
    if (!reachable) {
      return [
        _top(subtitle: 'via $via', actions: const []),
        Text(
          '$owner is no longer reachable through $via',
          key: const ValueKey('revoked'),
          style: _soft,
        ),
      ];
    }
    return [
      _top(
        subtitle: 'via ${_viaNames(_viasOf(fof))}',
        actions: [
          _KnockButton(name: owner),
          if (label == 'Knock')
            TextButton(
              key: ValueKey('ask-intro-$owner'),
              onPressed: () => _openIntroAsk(context, owner),
              style: TextButton.styleFrom(foregroundColor: _accent),
              child: Text('Ask $via to introduce'),
            ),
        ],
      ),
      const _SectionTitle('Open for', 'In their own words'),
      Text(
        fof.note,
        key: const ValueKey('open-for-note'),
        style: const TextStyle(color: _ink, fontSize: 15.5, height: 1.45),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final t in fof.openTo) _Chip(t)],
      ),
      const SizedBox(height: 24),
      if (spaces.isNotEmpty) const _SectionTitle('Spaces', null),
      for (final space in spaces)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _SpaceCard(
            owner: owner,
            space: space,
            onDive: () => _openSpace(context, owner, space.title),
          ),
        ),
      if (hidden > 0)
        Padding(
          key: const ValueKey('locked-spaces'),
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 15, color: _muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hidden == 1
                      ? '1 more space stays with $owner’s friends'
                      : '$hidden more spaces stay with $owner’s friends',
                  style: _soft,
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? caption;

  const _SectionTitle(this.title, this.caption);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(width: 10),
          Flexible(child: Text(caption!, style: _soft)),
        ],
      ],
    ),
  );
}

/// One thought on someone's world: what it said and when; tap to open it.
class _ThoughtRow extends StatelessWidget {
  final String owner;
  final int index;
  final _PastThought thought;

  const _ThoughtRow({
    required this.owner,
    required this.index,
    required this.thought,
  });

  @override
  Widget build(BuildContext context) {
    final t = thought;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _CardShell(
        onTap: () => _openThought(context, owner, index),
        child: Row(
          children: [
            Icon(
              switch (t.kind) {
                _ThoughtKind.voice => Icons.graphic_eq,
                _ThoughtKind.photo => Icons.image_outlined,
                _ThoughtKind.text => Icons.format_quote_rounded,
              },
              size: 18,
              color: t.live ? _accent : _muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _ink, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.live ? 'On the orbit now' : _ago(t.age),
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

/// Inside a Space: its things, one card each.
class _SpacePage extends StatelessWidget {
  final String owner;
  final _Space space;

  const _SpacePage({required this.owner, required this.space});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DiveHeader(
              trail: [owner == 'you' ? 'You' : owner, space.title],
            ),
            Expanded(
              child: ListView(
                key: ValueKey('space-${space.title}'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  for (final item in space.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ItemCard(
                        owner: owner,
                        item: item,
                        kind: space.kind,
                        onOpen: () =>
                            _openItemSheet(context, owner, item, space.kind),
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
