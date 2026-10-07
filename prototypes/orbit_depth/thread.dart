part of 'orbit_depth_prototype_screen.dart';

// A friend's posts as one thread on the night sky, read like a chat: the
// oldest at the top, the newest just above the reply field. The post nearest
// the field is the one a reply goes to; scroll another down to it, or tap it.

/// Friends whose thread you opened while the prototype runs: their thought
/// is no longer new, so it loses its green dot.
final Set<String> _seenThoughts = {};

/// Ticks when a thread closes, so the orbit drops the dot it just read.
final ValueNotifier<int> _seenTick = ValueNotifier(0);

/// Whether [friend]'s thought is new to you: fresh, and their thread not yet
/// opened.
bool _isNew(_ProtoFriend friend) =>
    friend.fresh && !_seenThoughts.contains(friend.name);

/// Opens [owner]'s thread; [target] picks a post (0 is the newest).
void _openThread(BuildContext context, String owner, {int target = 0}) {
  HapticFeedback.selectionClick();
  _seenThoughts.add(owner);
  Navigator.of(context)
      .push(_diveRoute(_ThreadScreen(owner: owner, initialTarget: target)))
      .then((_) => _seenTick.value++);
}

/// [owner]'s posts, newest first: the live thought (with all its slides)
/// and then the older ones.
List<_Post> _threadOf(String owner) {
  _ProtoFriend? friend;
  for (final f in _friends) {
    if (f.name == owner) friend = f;
  }
  final thoughts = _thoughtsOf(owner);
  return [
    for (var i = 0; i < thoughts.length; i++)
      if (i == 0 && thoughts[i].live && friend != null)
        _livePost(friend)
      else
        _pastPost(owner, thoughts[i]),
  ];
}

/// The colour a friend's thread is marked with.
Color _hueOf(String owner) {
  for (final f in _friends) {
    if (f.name == owner) return f.hue.color;
  }
  return _accent;
}

/// The first line of [post], short enough for the reply field.
String _shortLine(_Post post) {
  final line = post.paragraphs.isEmpty ? '' : post.paragraphs.first;
  return line.length <= 28 ? line : '${line.substring(0, 26).trimRight()}…';
}

class _ThreadScreen extends StatefulWidget {
  final String owner;
  final int initialTarget;

  const _ThreadScreen({required this.owner, this.initialTarget = 0});

  @override
  State<_ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<_ThreadScreen> {
  late final List<_Post> _posts = _threadOf(widget.owner);
  late final List<GlobalKey> _keys = [
    for (var i = 0; i < _posts.length; i++) GlobalKey(),
  ];
  late int _target = widget.initialTarget.clamp(0, _posts.length - 1);

  /// Chosen by a tap; the next drag hands the choice back to the scroll.
  late bool _picked = widget.initialTarget > 0;
  bool _dragging = false;

  final GlobalKey _fieldKey = GlobalKey();
  final TextEditingController _field = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _field.addListener(_onTyping);
    _fieldFocus.addListener(_onFieldFocus);
    if (_target > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _keys[_target].currentContext;
        if (context != null && mounted) {
          Scrollable.ensureVisible(context, alignment: 0.5);
        }
      });
    }
  }

  @override
  void dispose() {
    _field.removeListener(_onTyping);
    _field.dispose();
    _fieldFocus.removeListener(_onFieldFocus);
    _fieldFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTyping() => setState(() {});

  /// When the keyboard comes up, keep the post being answered in sight,
  /// just above the reply field.
  void _onFieldFocus() {
    if (!_fieldFocus.hasFocus) return;
    Future<void>.delayed(const Duration(milliseconds: 380), () {
      if (mounted && _fieldFocus.hasFocus) _reveal(_target);
    });
  }

  void _reveal(int i) {
    final context = _keys[i].currentContext;
    final post = context?.findRenderObject();
    final field = _fieldKey.currentContext?.findRenderObject();
    if (context == null || post is! RenderBox || field is! RenderBox) return;
    if (!_scroll.hasClients) return;
    // In this upside-down list 0 puts the post at the bottom edge; lift it
    // by the height of the field.
    final room = _scroll.position.viewportDimension - post.size.height;
    final alignment = room <= 0
        ? 0.0
        : ((field.size.height + 28) / room).clamp(0.0, 1.0);
    Scrollable.ensureVisible(
      context,
      alignment: alignment,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _dragging = true;
      _picked = false;
    } else if (n is ScrollEndNotification) {
      _dragging = false;
    }
    if (!_picked && (_dragging || n is ScrollEndNotification)) _follow();
    return false;
  }

  /// Makes the post nearest the reply field the target.
  void _follow() {
    final field = _fieldKey.currentContext?.findRenderObject();
    if (field is! RenderBox || !field.attached) return;
    final fieldTop = field.localToGlobal(Offset.zero).dy;
    var best = _target;
    var bestGap = double.infinity;
    for (var i = 0; i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      // Only posts mostly above the field are in the running.
      if (top + box.size.height / 2 > fieldTop) continue;
      final gap = (fieldTop - bottom).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = i;
      }
    }
    if (best != _target) setState(() => _target = best);
  }

  /// The private side of post [i]: your chat with its author, or, on your
  /// own post, its reactions and who wrote to you.
  Future<void> _openPrivate(int i) async {
    FocusScope.of(context).unfocus();
    if (widget.owner == 'you') {
      await _openActivity(context, i, _posts[i]);
    } else {
      await _openPrivateChat(
        context,
        author: widget.owner,
        post: i,
        friend: 'you',
        about: _posts[i],
      );
    }
    if (mounted) setState(() {});
  }

  void _pick(int i) {
    HapticFeedback.selectionClick();
    setState(() {
      _target = i;
      _picked = true;
    });
  }

  void _send() {
    final text = _field.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    // Replies are private: it goes to your chat with the author about it.
    setState(
      () => _privateChatFor(widget.owner, _target, 'you').messages.add(
        _Msg('you', text, 'now'),
      ),
    );
    _field.clear();
  }

  @override
  Widget build(BuildContext context) {
    final hue = _hueOf(widget.owner);
    return Scaffold(
      backgroundColor: Colors.transparent,
      // A tap anywhere that is not a post or a button puts the keyboard away.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: LayoutBuilder(
        builder: (context, box) {
          final pad = MediaQuery.paddingOf(context);
          final own = widget.owner == 'you';
          // Room at the top lets even the oldest post come down to the field.
          final headroom = math.max(0.0, box.maxHeight - pad.top - 260);
          return Stack(
            children: [
              Positioned.fill(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: ListView.builder(
                    key: const ValueKey('thread-screen'),
                    controller: _scroll,
                    reverse: true,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      pad.top + 64 + headroom,
                      20,
                      pad.bottom + 110,
                    ),
                    itemCount: _posts.length,
                    itemBuilder: (context, i) => KeyedSubtree(
                      key: _keys[i],
                      child: _ThreadPost(
                        owner: widget.owner,
                        post: _posts[i],
                        hue: hue,
                        // Your own posts have no reply target: all lit.
                        focused: own || i == _target,
                        picked: !own && i == _target && _picked,
                        link: _privateLinkLabel(widget.owner, i),
                        onLink: () => _openPrivate(i),
                        divider: i > 0,
                        onTap: own ? () {} : () => _pick(i),
                      ),
                    ),
                  ),
                ),
              ),
              // Fades so posts slide softly under the header and the field.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: IgnorePointer(
                  child: Container(
                    height: pad.top + 100,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFA0C0E1E), Color(0x000C0E1E)],
                        stops: [0.68, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    height: pad.bottom + 140,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xEB05080C), Color(0x0005080C)],
                        stops: [0.4, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: pad.top,
                child: _header(),
              ),
              // Your own posts take no reply field: friends write to you.
              if (widget.owner != 'you')
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: MediaQuery.viewInsetsOf(context).bottom > 0
                      ? 8
                      : pad.bottom + 8,
                  child: _replyField(hue),
                ),
            ],
          );
        },
        ),
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Close thread',
            icon: const Icon(Icons.arrow_back, color: _ink),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          _personPhoto(widget.owner, 32),
          const SizedBox(width: 10),
          Text(
            widget.owner,
            style: const TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              shadows: _PostCard._lift,
            ),
          ),
        ],
      ),
    );
  }

  Widget _replyField(Color hue) {
    final post = _posts[_target];
    final typing = _field.text.trim().isNotEmpty;
    return Container(
      key: _fieldKey,
      padding: EdgeInsets.fromLTRB(7, typing ? 8 : 7, 7, 7),
      decoration: BoxDecoration(
        color: const Color(0xF5181A20),
        borderRadius: BorderRadius.circular(typing ? 26 : 29),
        border: Border.all(color: const Color(0x24F2F4F3)),
        boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 24)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Once you type, the post you are answering is quoted, so you can
          // check before you send.
          if (typing)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 6),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Replying to ${widget.owner}',
                          style: TextStyle(
                            color: hue,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          post.paragraphs.isEmpty ? '' : post.paragraphs.first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFC9CFCB),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel reply',
                    icon: const Icon(Icons.close, size: 18, color: _muted),
                    onPressed: _field.clear,
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _field,
                  focusNode: _fieldFocus,
                  style: const TextStyle(color: _ink, fontSize: 16),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Reply to “${_shortLine(post)}”',
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
                  tooltip: 'Send reply',
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
        ],
      ),
    );
  }
}

/// One post in a thread. The one a reply would go to is lit; the others dim.
class _ThreadPost extends StatelessWidget {
  final String owner;
  final _Post post;
  final Color hue;
  final bool focused;

  /// Picked by a tap rather than by scrolling: marked in the friend's colour.
  final bool picked;

  /// The link to this post's private side, if there is anything there.
  final String? link;
  final VoidCallback onLink;

  /// A line under it, between it and the newer post below.
  final bool divider;
  final VoidCallback onTap;

  const _ThreadPost({
    required this.owner,
    required this.post,
    required this.hue,
    required this.focused,
    required this.picked,
    required this.link,
    required this.onLink,
    required this.divider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(
      color: _ink,
      fontSize: 18,
      height: 1.42,
      shadows: _PostCard._lift,
    );
    const muted = TextStyle(
      color: Color(0xFFA9B1AC),
      fontSize: 13,
      shadows: _PostCard._lift,
    );
    final visuals = [
      for (final s in post.attachments)
        if (s.kind == _SlideKind.photo || s.kind == _SlideKind.video) s,
    ];
    final voices = [
      for (final s in post.attachments)
        if (s.kind == _SlideKind.voice) s,
    ];
    final space = post.space;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: focused ? 1 : 0.4,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (picked)
                  Positioned(
                    left: -12,
                    top: 2,
                    bottom: 2,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: hue,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${post.age} ago', style: muted),
                    for (var i = 0; i < post.paragraphs.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 6 : 12),
                        child: Text(post.paragraphs[i], style: body),
                      ),
                    if (visuals.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _ThreadGallery(
                          owner: owner,
                          post: post,
                          slides: visuals,
                        ),
                      ),
                    for (final voice in voices)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _PostAttachment(
                          slide: voice,
                          u: 1,
                          active: focused,
                          photoHeight: 0,
                        ),
                      ),
                    if (space != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _SpaceChip(
                            space: space,
                            u: 1,
                            onTap: () => _openSpace(context, owner, space),
                          ),
                        ),
                      ),
                    if (link != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _PrivateLink(
                            label: link!,
                            hue: owner == 'you' ? null : hue,
                            onTap: onLink,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (divider)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Divider(height: 1, thickness: 1, color: Color(0x1AF2F4F3)),
          ),
      ],
    );
  }
}

/// The small link under a post to its private side: your chat with the
/// author (in their colour, with a lock), or your own post's reactions.
class _PrivateLink extends StatelessWidget {
  final String label;
  final Color? hue;
  final VoidCallback onTap;

  const _PrivateLink({required this.label, required this.hue, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hue = this.hue;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: hue == null
                ? const Color(0x14F2F4F3)
                : hue.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: hue == null
                ? null
                : Border.all(color: hue.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hue != null) ...[
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: Color.lerp(hue, Colors.white, 0.55),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hue == null
                        ? const Color(0xFFDDE5E7)
                        : Color.lerp(hue, Colors.white, 0.55),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A post's photos and videos, big: you opened the thread to look. Each one
/// takes most of the width in a tall 4:5 frame, and the next peeks in from
/// the right edge, so it is plain there are more. Tapping one opens it full
/// screen.
class _ThreadGallery extends StatefulWidget {
  final String owner;
  final _Post post;
  final List<_Slide> slides;

  const _ThreadGallery({
    required this.owner,
    required this.post,
    required this.slides,
  });

  @override
  State<_ThreadGallery> createState() => _ThreadGalleryState();
}

class _ThreadGalleryState extends State<_ThreadGallery> {
  static const double _peek = 0.86;
  static const double _gap = 8;

  late final PageController _pages = PageController(
    viewportFraction: widget.slides.length > 1 ? _peek : 1,
  );
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _open(int i) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, _) => _PhotoViewer(
          owner: widget.owner,
          post: widget.post,
          slides: widget.slides,
          initial: i,
        ),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    final many = slides.length > 1;
    return LayoutBuilder(
      builder: (context, box) {
        // Run on past the post's right margin to the edge of the screen.
        final run = box.maxWidth + (many ? 20 : 0);
        final photo = (many ? run * _peek - _gap : box.maxWidth);
        final height = math.min(photo * 1.25, MediaQuery.sizeOf(context).height * 0.58);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: run,
                maxWidth: run,
                child: PageView.builder(
                  key: const ValueKey('thread-gallery'),
                  controller: _pages,
                  padEnds: false,
                  itemCount: slides.length,
                  onPageChanged: (p) => setState(() => _page = p),
                  itemBuilder: (context, i) => Padding(
                    padding: EdgeInsets.only(right: many ? _gap : 0),
                    child: GestureDetector(
                      onTap: () => _open(i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            slides[i].kind == _SlideKind.video
                                ? _VideoSlide(
                                    slide: slides[i],
                                    k: 1,
                                    active: i == _page,
                                  )
                                : Image(
                                    image: _photo(slides[i].photo!),
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                            if (many && i == _page)
                              Positioned(
                                right: 10,
                                top: 10,
                                child: _Pill(
                                  text: '${_page + 1}/${slides.length}',
                                  k: 1,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (many)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _Dots(count: slides.length, at: _page),
              ),
          ],
        );
      },
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int at;

  const _Dots({required this.count, required this.at});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i == at ? _ink : _ink.withValues(alpha: 0.35),
          ),
        ),
    ],
  );
}

/// One post's photos and videos full screen on black: swipe through them,
/// pinch to zoom, swipe down or tap ✕ to go back.
class _PhotoViewer extends StatefulWidget {
  final String owner;
  final _Post post;
  final List<_Slide> slides;
  final int initial;

  const _PhotoViewer({
    required this.owner,
    required this.post,
    required this.slides,
    required this.initial,
  });

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initial,
  );
  late int _page = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    final line = widget.post.paragraphs.isEmpty
        ? ''
        : widget.post.paragraphs.first;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // A firm swipe down puts the photo away.
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 400) Navigator.of(context).maybePop();
        },
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  key: const ValueKey('photo-viewer'),
                  controller: _pages,
                  itemCount: slides.length,
                  onPageChanged: (p) => setState(() => _page = p),
                  itemBuilder: (context, i) => slides[i].kind ==
                          _SlideKind.video
                      ? Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: _VideoSlide(
                              slide: slides[i],
                              k: 1,
                              active: i == _page,
                            ),
                          ),
                        )
                      : InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: Center(
                            child: Image(
                              image: _photo(slides[i].photo!),
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                ),
              ),
              Positioned(
                left: 4,
                right: 4,
                top: 0,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close photo',
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Text(
                        slides.length > 1
                            ? '${_page + 1} / ${slides.length}'
                            : '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              if (slides.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 76,
                  child: _Dots(count: slides.length, at: _page),
                ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Row(
                  children: [
                    _personPhoto(widget.owner, 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.owner,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFA9B1AC),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
