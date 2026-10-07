part of 'orbit_depth_prototype_screen.dart';

// The front friend's thought as an Instagram-style carousel: photos, videos,
// voice notes and text, swiped sideways inside the card. The card has no
// buttons; one reply dock at the bottom of the screen answers whatever slide
// is showing, so swiping is how you aim it.

/// Room kept free at the bottom of the stage for the dock.
const double _dockInset = 76;

enum _SlideKind { photo, video, voice, text }

class _Slide {
  final _SlideKind kind;
  final String? photo;
  final int seconds;
  final String? text;

  const _Slide.photo(this.photo)
    : kind = _SlideKind.photo,
      seconds = 0,
      text = null;
  const _Slide.video(this.photo, this.seconds)
    : kind = _SlideKind.video,
      text = null;
  const _Slide.voice(this.seconds, [this.text])
    : kind = _SlideKind.voice,
      photo = null;
  const _Slide.text(this.text)
    : kind = _SlideKind.text,
      photo = null,
      seconds = 0;
}

/// Live thoughts with more than one thing in them.
const _slides = <String, List<_Slide>>{
  'layla': [
    _Slide.photo('trip_ridge'),
    _Slide.photo('trip_fjord'),
    _Slide.photo('trip_canoe'),
    _Slide.photo('trip_falls'),
    _Slide.photo('trip_road'),
    _Slide.photo('trip_valley'),
  ],
  'sara': [
    _Slide.video('sara_card', 18),
    _Slide.voice(6, 'her first howl'),
    _Slide.text('she has already claimed the sofa. and my side of the bed.'),
  ],
  'omar': [_Slide.voice(14), _Slide.text('results on friday. fingers crossed')],
  'maya': [
    _Slide.photo('job_cafe'),
    _Slide.video('job_view', 12),
    _Slide.voice(9, 'what I am most nervous about'),
  ],
  'dana': [
    _Slide.photo('food_bowl'),
    _Slide.photo('food_onions'),
    _Slide.video('food_brew', 15),
    _Slide.photo('food_berries'),
    _Slide.voice(7, 'the menu, read out'),
  ],
  'tarek': [
    _Slide.text(
      'putting up shelves this weekend and mine died halfway through the first one.'
      '\n\nit is the cordless one I bought when I moved in. the battery still '
      'charges, but the motor just clicks and smells a bit like burnt toast, '
      'so I think it is done for good.'
      '\n\nI only need it for saturday morning, maybe two hours. I can come and '
      'pick it up, and I will bring it back clean with a box of knafeh as rent.'
      '\n\nalso, if anyone knows how to find the studs in an old plaster wall '
      'without drilling ten test holes, please tell me before I do exactly that.',
    ),
    _Slide.voice(8, 'the noise it made'),
  ],
};

/// The slides of [friend]'s live thought; one-part thoughts get one slide.
List<_Slide> _slidesOf(_ProtoFriend friend) {
  final slides = _slides[friend.name];
  if (slides != null) return slides;
  final d = _detailFor(friend);
  return switch (d.kind) {
    _ThoughtKind.photo when d.photo != null => [_Slide.photo(d.photo)],
    _ThoughtKind.voice => [_Slide.voice(d.seconds)],
    _ => [_Slide.text(d.more)],
  };
}

/// Which slide each friend's carousel is on, and a tick that changes whenever
/// it does, so the dock can follow.
final Map<String, int> _slideAt = {};
final ValueNotifier<int> _slideTick = ValueNotifier(0);

/// What you sent to each slide while the prototype runs ('name#slide').
final Map<String, List<String>> _sent = {};

String _slideLabel(_ProtoFriend friend, int index) {
  final slides = _slidesOf(friend);
  final slide = slides[index.clamp(0, slides.length - 1)];
  int nth(_SlideKind kind) =>
      slides.take(index + 1).where((s) => s.kind == kind).length;
  int count(_SlideKind kind) => slides.where((s) => s.kind == kind).length;
  return switch (slide.kind) {
    _SlideKind.photo =>
      count(_SlideKind.photo) > 1
          ? 'photo ${nth(_SlideKind.photo)}'
          : 'the photo',
    _SlideKind.video =>
      count(_SlideKind.video) > 1
          ? 'video ${nth(_SlideKind.video)}'
          : 'the video',
    _SlideKind.voice => 'the voice note',
    _SlideKind.text => '${friend.name}’s thought',
  };
}

class _CarouselCard extends StatefulWidget {
  final _ProtoFriend friend;
  final double maxHeight;
  final double expand;
  final double k;
  final double alpha;
  final VoidCallback onWorld;

  const _CarouselCard({
    super.key,
    required this.friend,
    required this.maxHeight,
    required this.expand,
    required this.k,
    required this.alpha,
    required this.onWorld,
  });

  @override
  State<_CarouselCard> createState() => _CarouselCardState();
}

class _CarouselCardState extends State<_CarouselCard> {
  late final List<_Slide> _list = _slidesOf(widget.friend);
  late int _index = (_slideAt[widget.friend.name] ?? 0).clamp(
    0,
    _list.length - 1,
  );
  late final PageController _pages = PageController(initialPage: _index);

  @override
  void initState() {
    super.initState();
    _slideTick.addListener(_onTick);
  }

  @override
  void dispose() {
    _slideTick.removeListener(_onTick);
    _pages.dispose();
    super.dispose();
  }

  // Something was sent to a slide: show its tally.
  void _onTick() {
    if (mounted) setState(() {});
  }

  void _onPage(int i) {
    HapticFeedback.selectionClick();
    _index = i;
    _slideAt[widget.friend.name] = i;
    _slideTick.value++;
  }

  @override
  Widget build(BuildContext context) {
    final friend = widget.friend;
    final u = widget.k / OrbitDepthTuning.cardScale;
    final t = _interval(widget.expand, 0.5, 1);
    final height = math.min(widget.maxHeight, 330 * u);
    final d = _detailFor(friend);
    final slide = _list[_index];
    final many = _list.length > 1;
    final sent = _sent['${friend.name}#$_index'] ?? const [];

    return Opacity(
      opacity: (widget.alpha * t).clamp(0.0, 1.0),
      child: Transform.scale(
        scale: _lerp(0.92, 1, t),
        alignment: Alignment.topCenter,
        child: Container(
          height: height,
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22 * u),
            border: Border.all(color: _accent, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22 * u),
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  key: ValueKey('carousel-${friend.name}'),
                  controller: _pages,
                  itemCount: _list.length,
                  onPageChanged: _onPage,
                  itemBuilder: (context, i) => _SlideView(
                    slide: _list[i],
                    friend: friend,
                    k: u,
                    active: i == _index && widget.expand > 0.9,
                  ),
                ),
                // Shade top and bottom so the counter and caption read on
                // any photo.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                        stops: const [0, 0.22, 0.5, 1],
                      ),
                    ),
                  ),
                ),
                if (many)
                  Positioned(
                    right: 12 * u,
                    top: 12 * u,
                    child: _Pill(text: '${_index + 1}/${_list.length}', k: u),
                  ),
                if (sent.isNotEmpty)
                  Positioned(
                    right: 12 * u,
                    top: (many ? 42 : 12) * u,
                    child: _Pill(text: 'you: ${sent.join(' ')}', k: u),
                  ),
                Positioned(
                  left: 16 * u,
                  right: 16 * u,
                  bottom: 12 * u,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (many)
                        Padding(
                          padding: EdgeInsets.only(bottom: 10 * u),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < _list.length; i++)
                                Container(
                                  width: (i == _index ? 7 : 6) * u,
                                  height: (i == _index ? 7 : 6) * u,
                                  margin: EdgeInsets.symmetric(
                                    horizontal: 2.5 * u,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: i == _index
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.45),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      // A text slide is the thought itself; elsewhere the
                      // thought is the caption.
                      if (slide.kind != _SlideKind.text)
                        IgnorePointer(
                          child: Text(
                            friend.thought ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17 * u,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              shadows: const [
                                Shadow(color: Colors.black54, blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                      SizedBox(height: 6 * u),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${d.age} ago · ❤ ${d.comments * 2 + 3}'
                              ' · ${d.comments == 1 ? '1 reply' : '${d.comments} replies'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12.5 * u,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: widget.onWorld,
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 4 * u),
                              child: Text(
                                "${friend.name}'s world ›",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5 * u,
                                  fontWeight: FontWeight.w600,
                                ),
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
          ),
        ),
      ),
    );
  }
}

/// Whether [friend]'s live thought leads with text; those read as a post
/// rather than a carousel.
bool _textLed(_ProtoFriend friend) =>
    _slidesOf(friend).first.kind == _SlideKind.text;

/// One post as the cards and the full-screen view show it: its words, then
/// the voice notes, photos and videos attached to them.
class _Post {
  final String owner;
  final List<String> paragraphs;
  final List<_Slide> attachments;
  final String age;
  final int comments;
  final String? space;

  /// Where the orbit's dock tallies what you sent; only the live thought has
  /// one.
  final String? sentKey;

  /// Shown above the words where no friend stands over the card (their
  /// world); the actions then leave the age out.
  final String? header;

  const _Post({
    required this.owner,
    required this.paragraphs,
    required this.attachments,
    required this.age,
    required this.comments,
    this.space,
    this.sentKey,
    this.header,
  });

  int get likes => comments * 2 + 3;
}

/// [friend]'s live thought: text slides become words, the rest attachments.
_Post _livePost(_ProtoFriend friend) {
  final d = _detailFor(friend);
  final paragraphs = <String>[if (friend.thought != null) friend.thought!];
  final attachments = <_Slide>[];
  for (final slide in _slidesOf(friend)) {
    if (slide.kind != _SlideKind.text) {
      attachments.add(slide);
    } else if (slide.text != null) {
      paragraphs.addAll(slide.text!.split('\n\n'));
    }
  }
  return _Post(
    owner: friend.name,
    paragraphs: paragraphs,
    attachments: attachments,
    age: d.age,
    comments: d.comments,
    sentKey: '${friend.name}#0',
  );
}

/// One of [owner]'s posts as kept in their world.
_Post _pastPost(String owner, _PastThought thought, {bool header = false}) {
  final photo = thought.photo;
  return _Post(
    owner: owner,
    paragraphs: [thought.text, if (thought.more != null) thought.more!],
    attachments: [
      if (thought.kind == _ThoughtKind.voice) _Slide.voice(thought.seconds),
      if (thought.kind == _ThoughtKind.photo && photo != null)
        _Slide.photo(photo),
    ],
    age: thought.age,
    comments: thought.comments,
    space: thought.space,
    header: !header
        ? null
        : thought.live
        ? '${thought.age} ago · on the orbit now'
        : '${thought.age} ago',
  );
}

/// Opens [post] full screen.
void _openPost(BuildContext context, _Post post) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, _) => _PostScreen(post: post),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

const _postFill = Color(0xFF0B0D0E);

/// A post laid out like one on X. On the orbit the friend's photo and name
/// already sit above it, so it carries only the words, what is attached to
/// them, and one row of actions. Long text stops behind "Show more"; that, or
/// a tap anywhere on the card, opens the post full screen.
class _PostCard extends StatelessWidget {
  static const int _collapsedLines = 8;
  static const int _minLines = 3;

  /// Keeps words legible where they sit straight on the sky.
  static const List<Shadow> _lift = [
    Shadow(color: Color(0xB3000000), blurRadius: 10),
  ];

  final _Post post;
  final double maxHeight;
  final double expand;
  final double k;
  final double alpha;
  final VoidCallback onOpen;

  /// The link to the friend's world; null where the card already is there.
  final VoidCallback? onWorld;

  /// Opens the Space the post came from, if it came from one.
  final VoidCallback? onSpace;

  /// The front friend's card wears the accent outline.
  final bool front;

  const _PostCard({
    super.key,
    required this.post,
    required this.maxHeight,
    required this.expand,
    required this.k,
    required this.alpha,
    required this.onOpen,
    this.onWorld,
    this.onSpace,
    this.front = true,
  });

  bool get _universe => OrbitDepthTuning.postCards == OrbitPostCards.universe;

  List<Shadow>? get _shadows => _universe ? _lift : null;

  @override
  Widget build(BuildContext context) {
    final u = k / OrbitDepthTuning.cardScale;
    final t = _interval(expand, 0.5, 1);
    final header = post.header;
    final space = post.space;

    return Opacity(
      opacity: (alpha * t).clamp(0.0, 1.0),
      child: Transform.scale(
        scale: _lerp(0.92, 1, t),
        alignment: Alignment.topCenter,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Container(
              padding: EdgeInsets.fromLTRB(16 * u, 13 * u, 16 * u, 2 * u),
              decoration: _universe
                  ? null
                  : BoxDecoration(
                      color: _postFill,
                      borderRadius: BorderRadius.circular(22 * u),
                      border: front
                          ? Border.all(color: _accent, width: 2)
                          : Border.all(color: _chat.border),
                    ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (header != null)
                    Padding(
                      padding: EdgeInsets.only(bottom: 6 * u),
                      child: Text(
                        header,
                        style: TextStyle(
                          color: _muted,
                          fontSize: 12.5 * u,
                          shadows: _shadows,
                        ),
                      ),
                    ),
                  // Words and attachments share what the actions leave: the
                  // words show as many whole lines as fit beside the
                  // attachments, never fewer than [_minLines].
                  Flexible(
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _body(context, box, _attachmentsHeight(u), u),
                            for (final slide in post.attachments)
                              Padding(
                                padding: EdgeInsets.only(top: 10 * u),
                                child: _PostAttachment(
                                  slide: slide,
                                  u: u,
                                  active: expand >= 0.9,
                                  photoHeight: 150 * u,
                                ),
                              ),
                            if (space != null && onSpace != null)
                              Padding(
                                padding: EdgeInsets.only(top: 10 * u),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _SpaceChip(
                                    space: space,
                                    u: u,
                                    onTap: onSpace!,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _PostActions(
                    post: post,
                    u: u,
                    shadows: _shadows,
                    onWorld: onWorld,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Roughly how tall the attachments stand, so the words can leave them
  /// room.
  double _attachmentsHeight(double u) {
    var height = post.space != null && onSpace != null ? 40 * u : 0.0;
    for (final s in post.attachments) {
      height +=
          10 * u +
          switch (s.kind) {
            _SlideKind.voice => s.text == null ? 62 * u : 84 * u,
            _SlideKind.photo || _SlideKind.video => 150 * u,
            _SlideKind.text => 44 * u,
          };
    }
    return height;
  }

  /// The paragraphs, stopping after [_collapsedLines] lines, or sooner when
  /// fewer whole lines fit in [box] beside [reserve] and "Show more".
  Widget _body(
    BuildContext context,
    BoxConstraints box,
    double reserve,
    double u,
  ) {
    final paragraphs = post.paragraphs;
    final style = TextStyle(
      color: _chat.textPrimary,
      fontSize: 16 * u,
      height: 1.38,
      shadows: _shadows,
    );
    final moreStyle = TextStyle(
      color: _accent,
      fontSize: 15 * u,
      fontWeight: FontWeight.w600,
      shadows: _shadows,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final gap = 10 * u;
    (int, double) measure(String text, TextStyle s) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: s),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: box.maxWidth);
      final result = (painter.computeLineMetrics().length, painter.height);
      painter.dispose();
      return result;
    }

    final sizes = [for (final p in paragraphs) measure(p, style)];
    final totalLines = sizes.fold(0, (a, s) => a + s.$1);
    final fullHeight =
        sizes.fold(0.0, (a, s) => a + s.$2) + gap * (paragraphs.length - 1);
    final moreHeight = measure('Show more', moreStyle).$2 + 6 * u;
    final long =
        totalLines > _collapsedLines || fullHeight + reserve > box.maxHeight;

    final children = <Widget>[];
    var room = box.maxHeight - reserve - (long ? moreHeight : 0);
    var lineBudget = _collapsedLines;
    var promised = _minLines;
    for (var i = 0; i < paragraphs.length; i++) {
      final (lines, height) = sizes[i];
      final top = i == 0 ? 0.0 : gap;
      final lineHeight = lines == 0 ? height : height / lines;
      final fit = math.max(((room - top) / lineHeight).floor(), promised);
      final show = math.min(lines, math.min(lineBudget, fit));
      if (show <= 0) break;
      room -= top + show * lineHeight;
      lineBudget -= show;
      promised = math.max(0, promised - show);
      final cut = show < lines;
      children.add(
        Padding(
          padding: EdgeInsets.only(top: top),
          child: Text(
            paragraphs[i],
            style: style,
            maxLines: cut ? show : null,
            overflow: cut ? TextOverflow.ellipsis : null,
          ),
        ),
      );
      if (cut) break;
    }
    if (long) {
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: onOpen,
            child: Padding(
              padding: EdgeInsets.only(top: 4 * u, bottom: 2 * u),
              child: Text('Show more', style: moreStyle),
            ),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

}

/// The row under a post: replies, likes, its age (or what you sent), and
/// the link to the friend's world.
class _PostActions extends StatelessWidget {
  final _Post post;
  final double u;
  final List<Shadow>? shadows;
  final VoidCallback? onWorld;

  /// Overrides [_Post.sentKey], for a carousel aimed at one of its slides.
  final String? sentKey;

  const _PostActions({
    required this.post,
    required this.u,
    this.shadows,
    this.onWorld,
    this.sentKey,
  });

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      color: _muted,
      fontSize: 13 * u,
      shadows: shadows,
    );
    final world = onWorld;
    final key = sentKey ?? post.sentKey;
    return Padding(
      padding: EdgeInsets.only(top: 6 * u),
      child: Row(
        children: [
          // Counts shrink before the world link does.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ValueListenableBuilder<int>(
                valueListenable: _slideTick,
                builder: (context, tick, child) {
                  final sent = key == null
                      ? const <String>[]
                      : _sent[key] ?? const <String>[];
                  return Row(
                    children: [
                      _PostCount(
                        icon: Icons.chat_bubble_outline,
                        label: post.comments == 1
                            ? '1 reply'
                            : '${post.comments} replies',
                        style: muted,
                        u: u,
                      ),
                      SizedBox(width: 16 * u),
                      _PostCount(
                        icon: Icons.favorite_border,
                        label: '${post.likes}',
                        style: muted,
                        u: u,
                      ),
                      if (sent.isNotEmpty || post.header == null) ...[
                        SizedBox(width: 16 * u),
                        Text(
                          sent.isEmpty ? post.age : 'you: ${sent.join(' ')}',
                          style: muted,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
          if (world != null) ...[
            SizedBox(width: 10 * u),
            GestureDetector(
              onTap: world,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10 * u),
                child: Text(
                  "${post.owner}'s world ›",
                  style: TextStyle(
                    color: _chatSecondary,
                    fontSize: 12.5 * u,
                    fontWeight: FontWeight.w600,
                    shadows: shadows,
                  ),
                ),
              ),
            ),
          ] else
            SizedBox(height: 36 * u),
        ],
      ),
    );
  }
}

class _PostCount extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextStyle style;
  final double u;

  const _PostCount({
    required this.icon,
    required this.label,
    required this.style,
    required this.u,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16 * u, color: _muted),
      SizedBox(width: 5 * u),
      Text(label, style: style),
    ],
  );
}

/// A voice note, photo or video attached to a post.
class _PostAttachment extends StatelessWidget {
  final _Slide slide;
  final double u;
  final bool active;
  final double photoHeight;

  const _PostAttachment({
    required this.slide,
    required this.u,
    required this.active,
    required this.photoHeight,
  });

  @override
  Widget build(BuildContext context) {
    switch (slide.kind) {
      case _SlideKind.voice:
        // Outlined in a card; in the universe look it floats on the sky.
        final framed = OrbitDepthTuning.postCards == OrbitPostCards.framed;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: framed ? 10 * u : 0,
            vertical: 8 * u,
          ),
          decoration: framed
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14 * u),
                  border: Border.all(color: _chat.border),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VoicePlayer(seconds: slide.seconds, k: u, active: active),
              if (slide.text != null)
                Padding(
                  padding: EdgeInsets.only(top: 4 * u),
                  child: Text(
                    slide.text!,
                    style: TextStyle(color: _muted, fontSize: 12.5 * u),
                  ),
                ),
            ],
          ),
        );
      case _SlideKind.photo:
      case _SlideKind.video:
        return ClipRRect(
          borderRadius: BorderRadius.circular(14 * u),
          child: SizedBox(
            height: photoHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(
                  image: _photo(slide.photo!),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
                if (slide.kind == _SlideKind.video)
                  Center(
                    child: Container(
                      width: 48 * u,
                      height: 48 * u,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 30 * u,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      case _SlideKind.text:
        return Text(
          slide.text ?? '',
          style: TextStyle(
            color: _chat.textPrimary,
            fontSize: 16 * u,
            height: 1.38,
          ),
        );
    }
  }
}

class _SpaceChip extends StatelessWidget {
  final String space;
  final double u;
  final VoidCallback onTap;

  const _SpaceChip({required this.space, required this.u, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * u, vertical: 6 * u),
      decoration: BoxDecoration(
        color: _chat.surfaceSubtle,
        borderRadius: BorderRadius.circular(10 * u),
      ),
      child: Text(
        'from $space  ›',
        style: TextStyle(
          color: _chatSecondary,
          fontSize: 12.5 * u,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// A live thought that leads with photos, videos or voice notes, in the
/// universe look: its words float on the sky, the media below them swipes
/// sideways without a frame, and the same row of actions closes it. Swiping
/// re-aims the dock, as the framed carousel does.
class _UniverseMediaCard extends StatefulWidget {
  final _ProtoFriend friend;
  final double maxHeight;
  final double expand;
  final double k;
  final double alpha;
  final VoidCallback onOpen;
  final VoidCallback onWorld;

  const _UniverseMediaCard({
    super.key,
    required this.friend,
    required this.maxHeight,
    required this.expand,
    required this.k,
    required this.alpha,
    required this.onOpen,
    required this.onWorld,
  });

  @override
  State<_UniverseMediaCard> createState() => _UniverseMediaCardState();
}

class _UniverseMediaCardState extends State<_UniverseMediaCard> {
  static const int _maxLines = 3;

  late final List<_Slide> _all = _slidesOf(widget.friend);

  /// Where in [_all] each media slide sits; text slides join the words.
  late final List<int> _media = [
    for (var i = 0; i < _all.length; i++)
      if (_all[i].kind != _SlideKind.text) i,
  ];
  late int _page = math.max(
    0,
    _media.indexOf(_slideAt[widget.friend.name] ?? _media.first),
  );
  late final PageController _pages = PageController(initialPage: _page);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _onPage(int page) {
    HapticFeedback.selectionClick();
    setState(() => _page = page);
    _slideAt[widget.friend.name] = _media[page];
    _slideTick.value++;
  }

  @override
  Widget build(BuildContext context) {
    final friend = widget.friend;
    final u = widget.k / OrbitDepthTuning.cardScale;
    final t = _interval(widget.expand, 0.5, 1);
    final words = [
      if (friend.thought != null) friend.thought!,
      for (final s in _all)
        if (s.kind == _SlideKind.text && s.text != null) s.text!,
    ].join('\n');
    final style = TextStyle(
      color: _chat.textPrimary,
      fontSize: 16 * u,
      height: 1.38,
      shadows: _PostCard._lift,
    );

    return Opacity(
      opacity: (widget.alpha * t).clamp(0.0, 1.0),
      child: Transform.scale(
        scale: _lerp(0.92, 1, t),
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: LayoutBuilder(
            builder: (context, box) {
              final painter = TextPainter(
                text: TextSpan(text: words, style: style),
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: _maxLines,
                ellipsis: '…',
              )..layout(maxWidth: math.max(0.0, box.maxWidth - 32 * u));
              final wordsHeight = painter.height;
              final cut = painter.didExceedMaxLines;
              painter.dispose();
              // The media takes what the words, dots and actions leave.
              final mediaHeight =
                  (widget.maxHeight -
                          15 * u -
                          wordsHeight -
                          (cut ? 26 * u : 0) -
                          12 * u -
                          (_media.length > 1 ? 18 * u : 0) -
                          44 * u)
                      .clamp(120 * u, 320 * u);
              return SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16 * u, 13 * u, 16 * u, 2 * u),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onOpen,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              words,
                              maxLines: _maxLines,
                              overflow: TextOverflow.ellipsis,
                              style: style,
                            ),
                            if (cut)
                              Padding(
                                padding: EdgeInsets.only(top: 4 * u),
                                child: Text(
                                  'Show more',
                                  style: TextStyle(
                                    color: _accent,
                                    fontSize: 15 * u,
                                    fontWeight: FontWeight.w600,
                                    shadows: _PostCard._lift,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(height: 12 * u),
                      SizedBox(
                        height: mediaHeight,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18 * u),
                          child: PageView.builder(
                            key: ValueKey('universe-media-${friend.name}'),
                            controller: _pages,
                            itemCount: _media.length,
                            onPageChanged: _onPage,
                            itemBuilder: (context, page) => _slide(
                              _all[_media[page]],
                              u,
                              active: page == _page && widget.expand > 0.9,
                            ),
                          ),
                        ),
                      ),
                      if (_media.length > 1)
                        Padding(
                          padding: EdgeInsets.only(top: 9 * u),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var p = 0; p < _media.length; p++)
                                Container(
                                  width: (p == _page ? 7 : 6) * u,
                                  height: (p == _page ? 7 : 6) * u,
                                  margin: EdgeInsets.symmetric(
                                    horizontal: 2.5 * u,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: p == _page
                                        ? _ink
                                        : _ink.withValues(alpha: 0.35),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      _PostActions(
                        post: _livePost(friend),
                        u: u,
                        shadows: _PostCard._lift,
                        onWorld: widget.onWorld,
                        sentKey: '${friend.name}#${_media[_page]}',
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _slide(_Slide slide, double u, {required bool active}) {
    switch (slide.kind) {
      case _SlideKind.photo:
        return Image(
          image: _photo(slide.photo!),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      case _SlideKind.video:
        return _VideoSlide(slide: slide, k: u, active: active);
      case _SlideKind.voice:
        // No backdrop and no outline: the player floats on the sky, in the
        // same space a photo would take.
        return SizedBox.expand(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 18 * u),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.graphic_eq,
                        size: 18 * u,
                        color: widget.friend.hue.color,
                      ),
                      SizedBox(width: 6 * u),
                      Text(
                        slide.text ?? 'voice note',
                        style: TextStyle(
                          color: _chatSecondary,
                          fontSize: 14 * u,
                          fontWeight: FontWeight.w600,
                          shadows: _PostCard._lift,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 14 * u),
                  _VoicePlayer(seconds: slide.seconds, k: u * 1.1, active: active),
                ],
              ),
            ),
          ),
        );
      case _SlideKind.text:
        return const SizedBox.shrink();
    }
  }
}

/// A post opened full screen: who wrote it, all of its words and
/// attachments, and a place to reply.
class _PostScreen extends StatefulWidget {
  final _Post post;

  const _PostScreen({required this.post});

  @override
  State<_PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<_PostScreen> {
  final List<String> _replies = [];
  final TextEditingController _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _send() {
    final text = _field.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _replies.add(text);
      _field.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final space = post.space;
    const body = TextStyle(color: _ink, fontSize: 18, height: 1.42);
    final sent = post.sentKey == null
        ? const <String>[]
        : _sent[post.sentKey] ?? const <String>[];
    return Scaffold(
      backgroundColor: _ground,
      body: SafeArea(
        // The reply bar runs under the home indicator itself.
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close post',
                    icon: const Icon(Icons.arrow_back, color: _ink),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Text(
                    'Post',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('post-screen'),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Row(
                    children: [
                      _personPhoto(post.owner, 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.owner,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${post.age} ago',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < post.paragraphs.length; i++)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                      child: Text(post.paragraphs[i], style: body),
                    ),
                  for (final slide in post.attachments)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _PostAttachment(
                        slide: slide,
                        u: 1,
                        active: true,
                        photoHeight: 280,
                      ),
                    ),
                  if (space != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _SpaceChip(
                          space: space,
                          u: 1,
                          onTap: () => _openSpace(context, post.owner, space),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Divider(color: _chat.border, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '${post.comments == 1 ? '1 reply' : '${post.comments} replies'}'
                      '  ·  ${post.likes} likes',
                      style: const TextStyle(color: _muted, fontSize: 14),
                    ),
                  ),
                  Divider(color: _chat.border, height: 1),
                  for (final reply in [...sent, ..._replies])
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _personPhoto('you', 32),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'you',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  reply,
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 15,
                                    height: 1.35,
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
            Container(
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                8,
                MediaQuery.viewInsetsOf(context).bottom > 0
                    ? 8
                    : 8 + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: _sheet,
                border: Border(top: BorderSide(color: _chat.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _field,
                      style: const TextStyle(color: _ink),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Reply to ${post.owner}…',
                        hintStyle: const TextStyle(color: Color(0xFF78837C)),
                        filled: true,
                        fillColor: _chat.surfaceSubtle,
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
                  IconButton(
                    tooltip: 'Send reply',
                    icon: const Icon(Icons.send_rounded, color: _accent),
                    onPressed: _send,
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

class _Pill extends StatelessWidget {
  final String text;
  final double k;

  const _Pill({required this.text, required this.k});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 9 * k, vertical: 3 * k),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12 * k),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: Colors.white,
        fontSize: 12 * k,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Lays [child] out at its natural height and shrinks it to fit short cards.
Widget _fitted(EdgeInsets padding, Widget child) => Padding(
  padding: padding,
  child: LayoutBuilder(
    builder: (context, box) => FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(width: box.maxWidth, child: child),
    ),
  ),
);

class _SlideView extends StatelessWidget {
  final _Slide slide;
  final _ProtoFriend friend;
  final double k;
  final bool active;

  const _SlideView({
    required this.slide,
    required this.friend,
    required this.k,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    switch (slide.kind) {
      case _SlideKind.photo:
        return Image(
          image: _photo(slide.photo!),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      case _SlideKind.video:
        return _VideoSlide(slide: slide, k: k, active: active);
      case _SlideKind.voice:
        return _VoiceSlide(slide: slide, friend: friend, k: k, active: active);
      case _SlideKind.text:
        // Words read like a post: plain, left-aligned, from the top.
        final style = TextStyle(
          color: _chat.textPrimary,
          fontSize: 17 * k,
          height: 1.38,
        );
        return ColoredBox(
          color: _postFill,
          child: Padding(
            padding: EdgeInsets.fromLTRB(18 * k, 44 * k, 18 * k, 56 * k),
            child: LayoutBuilder(
              builder: (context, box) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: box.maxWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(friend.thought ?? '', style: style),
                      if (slide.text != null) ...[
                        SizedBox(height: 10 * k),
                        Text(slide.text!, style: style),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    }
  }
}

/// A video slide. No real video in the prototype: tapping plays a slow push
/// in on the still with a progress bar, which is enough to feel the flow.
class _VideoSlide extends StatefulWidget {
  final _Slide slide;
  final double k;
  final bool active;

  const _VideoSlide({
    required this.slide,
    required this.k,
    required this.active,
  });

  @override
  State<_VideoSlide> createState() => _VideoSlideState();
}

class _VideoSlideState extends State<_VideoSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _play = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.slide.seconds),
  )..addStatusListener(_onStatus);

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _play.value = 0;
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(_VideoSlide old) {
    super.didUpdateWidget(old);
    if (!widget.active && _play.isAnimating) _play.stop();
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  void _toggle() =>
      setState(() => _play.isAnimating ? _play.stop() : _play.forward());

  @override
  Widget build(BuildContext context) {
    final k = widget.k;
    final seconds = widget.slide.seconds;
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _play,
        builder: (context, _) {
          final playing = _play.isAnimating;
          final left = (seconds * (1 - _play.value)).ceil();
          return Stack(
            fit: StackFit.expand,
            children: [
              Transform.scale(
                scale: 1 + 0.08 * _play.value,
                child: Image(
                  image: _photo(widget.slide.photo!),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
              if (!playing)
                Align(
                  alignment: const Alignment(0, -0.3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58 * k,
                        height: 58 * k,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.75),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 34 * k,
                        ),
                      ),
                    ],
                  ),
                ),
              Positioned(
                left: 12 * k,
                top: 12 * k,
                child: _Pill(
                  text:
                      '\u25b6 0:${'${playing ? left : seconds}'.padLeft(2, '0')}',
                  k: k,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 3,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _play.value,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VoiceSlide extends StatelessWidget {
  final _Slide slide;
  final _ProtoFriend friend;
  final double k;
  final bool active;

  const _VoiceSlide({
    required this.slide,
    required this.friend,
    required this.k,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 1.1,
          colors: [
            Color.lerp(friend.hue.fill, friend.hue.color, 0.28)!,
            _sheet,
          ],
        ),
      ),
      // The orbit already shows whose it is: just what it is and the player,
      // kept clear of the counter above and the caption below.
      child: _fitted(
        EdgeInsets.fromLTRB(22 * k, 40 * k, 22 * k, 98 * k),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.graphic_eq, size: 18 * k, color: friend.hue.color),
                SizedBox(width: 6 * k),
                Text(
                  slide.text ?? 'voice note',
                  style: TextStyle(
                    color: _chatSecondary,
                    fontSize: 14 * k,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: 14 * k),
            _VoicePlayer(seconds: slide.seconds, k: k * 1.1, active: active),
          ],
        ),
      ),
    );
  }
}

/// What the dock is aimed at.
class _DockTarget {
  final _ProtoFriend friend;

  /// The carousel slide, or null for one of the friend's older posts.
  final int? slide;

  const _DockTarget(this.friend, this.slide);

  String get label =>
      slide == null ? '${friend.name}’s post' : _slideLabel(friend, slide!);

  _Slide? get _slide {
    final i = slide;
    if (i == null) return null;
    final slides = _slidesOf(friend);
    return slides[i.clamp(0, slides.length - 1)];
  }

  /// A small picture of the target for the chip.
  Widget thumb(double size) {
    final s = _slide;
    final photo = s?.photo;
    if (photo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image(
          image: _photo(photo),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    if (s?.kind == _SlideKind.voice) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: friend.hue.fill,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.graphic_eq,
          size: size * 0.6,
          color: friend.hue.color,
        ),
      );
    }
    return ClipOval(
      child: _ringAvatarPeers.containsKey(friend.name)
          ? Container(width: size, height: size, color: friend.hue.fill)
          : Image(
              image: _photo(friend.name),
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
    );
  }

  void record(String mark) {
    final i = slide;
    if (i == null) return;
    (_sent['${friend.name}#$i'] ??= []).add(mark);
    _slideTick.value++;
  }
}

enum _DockMode { idle, react, voice, video, typing }

/// One reply bar for the whole screen: react, type, hold for voice, or record
/// a round video. Everything goes to [target], shown in the chip above.
class _ReplyDock extends StatefulWidget {
  final _DockTarget target;
  final double k;

  const _ReplyDock({required this.target, required this.k});

  @override
  State<_ReplyDock> createState() => _ReplyDockState();
}

class _ReplyDockState extends State<_ReplyDock> with TickerProviderStateMixin {
  static const _emoji = ['❤️', '😍', '😲', '🔥', '😂', '👏'];

  _DockMode _mode = _DockMode.idle;
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// Seconds of voice or video recorded so far.
  late final AnimationController _rec = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );

  /// The reaction flying up from the dock, and the "sent" toast.
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _toast = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  String _flying = '';
  String _toastText = '';
  double _voiceDrag = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        setState(() => _mode = _DockMode.typing);
      } else if (_mode == _DockMode.typing) {
        setState(() => _mode = _DockMode.idle);
      }
    });
  }

  @override
  void didUpdateWidget(_ReplyDock old) {
    super.didUpdateWidget(old);
    if (old.target.friend != widget.target.friend && _mode == _DockMode.react) {
      _mode = _DockMode.idle;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _rec.dispose();
    _fly.dispose();
    _toast.dispose();
    super.dispose();
  }

  void _sent(String mark, String what) {
    HapticFeedback.mediumImpact();
    widget.target.record(mark);
    _toastText = '$what sent to ${widget.target.label}';
    _toast.forward(from: 0);
  }

  void _react(String emoji) {
    setState(() {
      _mode = _DockMode.idle;
      _flying = emoji;
    });
    _fly.forward(from: 0);
    _sent(emoji, emoji);
  }

  void _send() {
    if (_text.text.trim().isEmpty) return;
    _text.clear();
    _focus.unfocus();
    _sent('💬', 'Reply');
  }

  void _startVoice() {
    HapticFeedback.selectionClick();
    setState(() {
      _mode = _DockMode.voice;
      _voiceDrag = 0;
    });
    _rec.forward(from: 0);
  }

  void _endVoice() {
    final seconds = _rec.value * 60;
    final cancelled = _voiceDrag < -90;
    _rec.stop();
    setState(() => _mode = _DockMode.idle);
    if (cancelled) {
      _toastText = 'Voice note cancelled';
      _toast.forward(from: 0);
    } else if (seconds >= 0.6) {
      _sent('🎙', 'Voice note');
    } else {
      _toastText = 'Hold the mic to record';
      _toast.forward(from: 0);
    }
  }

  void _startVideo() {
    HapticFeedback.selectionClick();
    setState(() => _mode = _DockMode.video);
    _rec.forward(from: 0);
  }

  void _endVideo({required bool send}) {
    _rec.stop();
    setState(() => _mode = _DockMode.idle);
    if (send) _sent('🎥', 'Video');
  }

  String get _clock {
    final s = (_rec.value * 60).floor();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.k;
    final target = widget.target;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bottom = math.max(
      8 * k,
      keyboard - MediaQuery.paddingOf(context).bottom + 8 * k,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (_mode == _DockMode.video) ..._videoOverlay(k),
        // The reaction rising towards the card.
        AnimatedBuilder(
          animation: _fly,
          builder: (context, _) {
            if (!_fly.isAnimating) return const SizedBox.shrink();
            final v = Curves.easeOutCubic.transform(_fly.value);
            return Positioned(
              left: 24 * k,
              bottom: bottom + 60 * k + 220 * k * v,
              child: IgnorePointer(
                child: Opacity(
                  opacity: (1 - _fly.value) * 1.4 > 1
                      ? 1
                      : (1 - _fly.value) * 1.4,
                  child: Text(
                    _flying,
                    style: TextStyle(fontSize: (34 + 30 * v) * k),
                  ),
                ),
              ),
            );
          },
        ),
        // "Sent to photo 2".
        AnimatedBuilder(
          animation: _toast,
          builder: (context, _) {
            final v = _toast.value;
            if (!_toast.isAnimating) return const SizedBox.shrink();
            final alpha = v < 0.1 ? v / 0.1 : (v > 0.8 ? (1 - v) / 0.2 : 1.0);
            return Positioned(
              left: 0,
              right: 0,
              bottom: bottom + 104 * k,
              child: IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: alpha,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14 * k,
                        vertical: 8 * k,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xF2252830),
                        borderRadius: BorderRadius.circular(18 * k),
                        border: Border.all(color: _chat.border),
                      ),
                      child: Text(
                        _toastText,
                        style: TextStyle(
                          color: _ink,
                          fontSize: 13 * k,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (_mode == _DockMode.react)
          Positioned(left: 12 * k, bottom: bottom + 66 * k, child: _tray(k)),
        Positioned(
          left: 10 * k,
          right: 10 * k,
          bottom: bottom,
          height: 58 * k,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 7 * k),
            decoration: BoxDecoration(
              color: const Color(0xF0181A20),
              borderRadius: BorderRadius.circular(29 * k),
              border: Border.all(color: _chat.border),
              boxShadow: const [
                BoxShadow(color: Color(0x59000000), blurRadius: 24),
              ],
            ),
            child: switch (_mode) {
              _DockMode.voice => _voiceBar(k),
              _DockMode.video => _videoBar(k),
              _ => _idleBar(k, target),
            },
          ),
        ),
      ],
    );
  }

  Widget _round(
    IconData icon, {
    required double k,
    Color bg = const Color(0x14FFFFFF),
    Color color = _ink,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    final button = Container(
      width: 44 * k,
      height: 44 * k,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: 22 * k, color: color),
    );
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(onTap: onTap, child: button),
    );
  }

  Widget _idleBar(double k, _DockTarget target) {
    final typing = _mode == _DockMode.typing;
    return Row(
      children: [
        _round(
          _mode == _DockMode.react
              ? Icons.close
              : Icons.emoji_emotions_outlined,
          k: k,
          tooltip: 'React',
          onTap: () => setState(
            () => _mode = _mode == _DockMode.react
                ? _DockMode.idle
                : _DockMode.react,
          ),
        ),
        SizedBox(width: 6 * k),
        Expanded(
          child: Container(
            height: 44 * k,
            padding: EdgeInsets.symmetric(horizontal: 14 * k),
            decoration: BoxDecoration(
              color: const Color(0x0DFFFFFF),
              borderRadius: BorderRadius.circular(22 * k),
            ),
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: _text,
              focusNode: _focus,
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send,
              style: TextStyle(color: _ink, fontSize: 14.5 * k),
              cursorColor: _accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Reply to ${target.label}…',
                hintStyle: TextStyle(color: _muted, fontSize: 14.5 * k),
              ),
            ),
          ),
        ),
        SizedBox(width: 6 * k),
        if (typing)
          _round(
            Icons.arrow_upward_rounded,
            k: k,
            bg: _accent,
            color: const Color(0xFF03140A),
            tooltip: 'Send',
            onTap: _send,
          )
        else ...[
          GestureDetector(
            onLongPressStart: (_) => _startVoice(),
            onLongPressMoveUpdate: (d) =>
                setState(() => _voiceDrag = d.offsetFromOrigin.dx),
            onLongPressEnd: (_) => _endVoice(),
            onTap: () {
              _toastText = 'Hold the mic to record';
              _toast.forward(from: 0);
            },
            child: _round(
              Icons.mic_none_rounded,
              k: k,
              bg: _accent,
              color: const Color(0xFF03140A),
              tooltip: 'Hold to record a voice note',
            ),
          ),
          SizedBox(width: 6 * k),
          _round(
            Icons.videocam_outlined,
            k: k,
            tooltip: 'Record a video reply',
            onTap: _startVideo,
          ),
        ],
      ],
    );
  }

  Widget _tray(double k) => Container(
    padding: EdgeInsets.symmetric(horizontal: 8 * k, vertical: 6 * k),
    decoration: BoxDecoration(
      color: const Color(0xFF23262E),
      borderRadius: BorderRadius.circular(30 * k),
      border: Border.all(color: _chat.border),
      boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 30)],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in _emoji)
          GestureDetector(
            onTap: () => _react(e),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 5 * k),
              child: Text(e, style: TextStyle(fontSize: 27 * k)),
            ),
          ),
      ],
    ),
  );

  Widget _voiceBar(double k) => AnimatedBuilder(
    animation: _rec,
    builder: (context, _) {
      final cancelling = _voiceDrag < -90;
      return Row(
        children: [
          SizedBox(width: 10 * k),
          Container(
            width: 10 * k,
            height: 10 * k,
            decoration: BoxDecoration(
              color: (_rec.value * 120).floor().isEven
                  ? const Color(0xFFF43F5E)
                  : const Color(0x55F43F5E),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 8 * k),
          Text(
            _clock,
            style: TextStyle(color: _ink, fontSize: 15 * k),
          ),
          SizedBox(width: 10 * k),
          Expanded(
            child: SizedBox(
              height: 24 * k,
              child: CustomPaint(
                painter: _LiveWavePainter(phase: _rec.value * 600),
              ),
            ),
          ),
          SizedBox(width: 10 * k),
          Text(
            cancelling ? 'release to cancel' : '‹ slide to cancel',
            style: TextStyle(
              color: cancelling ? const Color(0xFFF43F5E) : _muted,
              fontSize: 12.5 * k,
            ),
          ),
          SizedBox(width: 8 * k),
          Container(
            width: 44 * k,
            height: 44 * k,
            decoration: BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.35),
                  spreadRadius: 6 * k,
                ),
              ],
            ),
            child: Icon(
              Icons.mic_rounded,
              size: 24 * k,
              color: const Color(0xFF03140A),
            ),
          ),
        ],
      );
    },
  );

  Widget _videoBar(double k) => Row(
    children: [
      _round(
        Icons.close,
        k: k,
        tooltip: 'Cancel',
        onTap: () => _endVideo(send: false),
      ),
      Expanded(
        child: Center(
          child: Text(
            'tap to send',
            style: TextStyle(color: _muted, fontSize: 13 * k),
          ),
        ),
      ),
      _round(
        Icons.stop_rounded,
        k: k,
        bg: const Color(0xFFF43F5E),
        color: Colors.white,
        tooltip: 'Send video',
        onTap: () => _endVideo(send: true),
      ),
    ],
  );

  List<Widget> _videoOverlay(double k) => [
    Positioned.fill(
      child: GestureDetector(
        onTap: () => _endVideo(send: true),
        child: const ColoredBox(color: Color(0xA002030A)),
      ),
    ),
    Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: const Alignment(0, -0.05),
          child: AnimatedBuilder(
            animation: _rec,
            builder: (context, _) {
              // A round clip of you, ringed by how long it has run (up to
              // 15 seconds), with the thing it answers pinned on top.
              final progress = (_rec.value * 4).clamp(0.0, 1.0);
              if (progress >= 1 && _mode == _DockMode.video) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => mounted && _mode == _DockMode.video
                      ? _endVideo(send: true)
                      : null,
                );
              }
              return SizedBox(
                width: 250 * k,
                height: 330 * k,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned(
                      top: 70 * k,
                      child: CustomPaint(
                        painter: _ClipRingPainter(progress: progress),
                        child: Padding(
                          padding: EdgeInsets.all(6 * k),
                          child: ClipOval(
                            child: Image(
                              image: _photo('you'),
                              width: 228 * k,
                              height: 228 * k,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      child: Transform.rotate(
                        angle: -0.1,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16 * k),
                            border: Border.all(color: _accent, width: 3),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x80000000),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: widget.target.thumb(84 * k),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      child: Text(
                        '● $_clock',
                        style: TextStyle(color: _ink, fontSize: 14 * k),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  ];
}

class _LiveWavePainter extends CustomPainter {
  final double phase;

  _LiveWavePainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final bars = (size.width / 5).floor();
    final paint = Paint()
      ..color = _ink
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    for (var i = 0; i < bars; i++) {
      final level =
          0.2 +
          0.8 *
              (math.sin(i * 0.8 + phase) * math.cos(i * 0.31 - phase * 0.7))
                  .abs();
      final h = size.height * level;
      final x = i * 5 + 2.5;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LiveWavePainter old) => old.phase != phase;
}

class _ClipRingPainter extends CustomPainter {
  final double progress;

  _ClipRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..color = const Color(0x26FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawOval(rect.deflate(2.5), track);
    canvas.drawArc(
      rect.deflate(2.5),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      track..color = _accent,
    );
  }

  @override
  bool shouldRepaint(_ClipRingPainter old) => old.progress != progress;
}
