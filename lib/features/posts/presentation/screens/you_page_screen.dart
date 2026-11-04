import 'dart:async';
import 'package:flutter_app/features/posts/application/load_own_thought_tags_use_case.dart';
import 'package:flutter_app/features/posts/presentation/widgets/thought_voice.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/format_day_separator_label.dart';
import 'package:flutter_app/core/utils/thought_tags.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/posts/application/group_thought_reactions.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/screens/thought_card_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';
import 'package:flutter_app/shared/widgets/thought_tag_style.dart';

class YouPageData {
  const YouPageData({
    required this.username,
    required this.avatarBytes,
    required this.friendCount,
    required this.thought,
    required this.past,
    this.tag,
    this.tagCount = 0,
    this.tags = const [],
  });

  final String username;
  final Uint8List? avatarBytes;
  final int friendCount;

  /// The one live own Thought, or null when nothing is up.
  final YouThought? thought;

  /// Expired own Thoughts, newest first: only those with [tag] when set.
  final List<YouThought> past;

  /// The tag key [past] was loaded for, or null for the whole log.
  final String? tag;

  /// How many own Thoughts carry [tag], the live one included.
  final int tagCount;

  /// Every tag on the author's own Thoughts, newest first.
  final List<OwnThoughtTag> tags;
}

class YouThought {
  const YouThought({
    required this.post,
    required this.reactions,
    required this.wroteBack,
  });

  final PostModel post;
  final List<ThoughtReactionGroup> reactions;
  final List<YouWroteBack> wroteBack;
}

class YouWroteBack {
  const YouWroteBack({
    required this.peerId,
    required this.name,
    required this.hasUnread,
  });

  final String peerId;
  final String name;
  final bool hasUnread;
}

const _ground = Color(0xFF040605);
const _ink = Color(0xFFE8ECE9);
const _muted = Color(0xFF9AA59F);
const _accent = Color(0xFF1DB954);
const _friendsBlue = Color(0xFF5FB3C9);
const _hairline = Color(0x14E8ECE9);
const _soft = Color(0xFF8C968F);
const _faint = Color(0xFF59625D);
const _historyPage = 20;
const _mono = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: ['Courier', 'monospace'],
);

/// Your own page, opened from your photo in the middle of Orbit: your live
/// Thought below your past ones, who reacted, and who wrote back. A face that
/// wrote opens your chat with them; nobody else sees what they wrote.
class YouPageScreen extends StatefulWidget {
  const YouPageScreen({
    super.key,
    required this.load,
    required this.onBack,
    required this.onOpenChat,
    required this.onCompose,
    required this.now,
    this.changes = const [],
    this.thoughtReplies = const Stream.empty(),
    this.tagsNoteSeen = true,
    this.onTagsNoteSeen,
  });

  /// Whether the one-time note pointing at "your tags" was already shown.
  final bool tagsNoteSeen;

  /// The note was seen: it never shows again.
  final VoidCallback? onTagsNoteSeen;

  /// Loads the page with at most [historyLimit] past Thoughts, only those
  /// with the tag key [tag] when it is set.
  final Future<YouPageData> Function(int historyLimit, String? tag) load;

  /// Any event reloads the page: a stored post changed.
  final List<Stream<Object?>> changes;

  /// Post ids whose replies changed. Only a Thought on the page reloads it.
  final Stream<String> thoughtReplies;
  final VoidCallback onBack;
  final Future<void> Function(String peerId) onOpenChat;

  /// Opens the write sheet, starting with [tag] when set, and completes once
  /// it has closed.
  final Future<void> Function(String? tag) onCompose;
  final DateTime Function() now;

  @override
  State<YouPageScreen> createState() => _YouPageScreenState();
}

class _YouPageScreenState extends State<YouPageScreen>
    with WidgetsBindingObserver {
  YouPageData? _data;

  /// The tag you tapped: only your Thoughts with it show.
  ThoughtTag? _tag;
  String _tagLabel = '';
  int _historyLimit = _historyPage;
  bool _loadingOlder = false;
  int _generation = 0;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _expiryTimer;
  Timer? _ageTimer;
  Route<void>? _mediaRoute;
  String? _mediaPostId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final changes in widget.changes) {
      _subscriptions.add(changes.listen((_) => _reload()));
    }
    _subscriptions.add(
      widget.thoughtReplies.listen((postId) {
        if (_shows(postId)) _reload();
      }),
    );
    // Keeps "gone in N h" current between reloads.
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _expireThenReload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _expiryTimer?.cancel();
    _ageTimer?.cancel();
    super.dispose();
  }

  bool _shows(String postId) {
    final data = _data;
    return data == null ||
        [
          ?data.thought,
          ...data.past,
        ].any((each) => each.post.id == postId && _hasTag(each));
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final data = await widget.load(_historyLimit, _tag?.key);
      if (!mounted || generation != _generation) return;
      final shown = {
        ?data.thought?.post.id,
        for (final past in data.past) past.post.id,
      };
      if (!shown.contains(_mediaPostId)) _closeMediaViewer();
      setState(() => _data = data);
      _armExpiry(data.thought?.post);
    } catch (_) {
      // The page keeps what it last showed; the next change or open reloads.
    }
  }

  /// The clock, not the reload, ends a live Thought: it moves into the past
  /// and its viewer closes at once, whether or not the reload answers.
  void _expireThenReload() {
    final data = _data;
    final live = data?.thought;
    final expiry = DateTime.tryParse(live?.post.expiresAt ?? '')?.toUtc();
    if (data != null &&
        live != null &&
        expiry != null &&
        !expiry.isAfter(widget.now().toUtc())) {
      if (_mediaPostId == live.post.id) _closeMediaViewer();
      setState(
        () => _data = YouPageData(
          username: data.username,
          avatarBytes: data.avatarBytes,
          friendCount: data.friendCount,
          thought: null,
          past: [live, ...data.past],
          tag: data.tag,
          tagCount: data.tagCount,
        ),
      );
    }
    _reload();
  }

  void _armExpiry(PostModel? post) {
    _expiryTimer?.cancel();
    final expiry = post == null
        ? null
        : DateTime.tryParse(post.expiresAt)?.toUtc();
    if (expiry == null) return;
    final remaining = expiry.difference(widget.now().toUtc());
    _expiryTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _expireThenReload,
    );
  }

  void _closeMediaViewer() {
    final route = _mediaRoute;
    _mediaRoute = null;
    _mediaPostId = null;
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _openMedia(
    String postId,
    List<PostMediaAttachmentModel> visual,
    int index,
  ) async {
    if (_mediaRoute != null || visual[index].localPath == null) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => FullScreenTypedMediaViewer(
        key: const ValueKey('you-media-viewer'),
        items: visual.map(thoughtMediaViewerItem).toList(growable: false),
        initialIndex: index,
      ),
    );
    _mediaRoute = route;
    _mediaPostId = postId;
    await Navigator.of(context).push(route);
    if (identical(_mediaRoute, route)) {
      _mediaRoute = null;
      _mediaPostId = null;
    }
  }

  /// Near the oldest card, a full page asks for the next one.
  bool _loadOlderAtTop(ScrollNotification notification) {
    final data = _data;
    if (!_loadingOlder &&
        data != null &&
        data.past.length >= _historyLimit &&
        notification.metrics.extentAfter < 400) {
      _loadingOlder = true;
      _historyLimit += _historyPage;
      // Scroll events before the next layout still carry the old extent.
      _reload().whenComplete(
        () => WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadingOlder = false,
        ),
      );
    }
    return false;
  }

  Future<void> _compose() async {
    await widget.onCompose(_tag == null ? null : _tagLabel);
    if (mounted) await _reload();
  }

  void _showTag(ThoughtTag? tag, [String label = '']) {
    setState(() {
      _tag = tag;
      _tagLabel = label;
      _historyLimit = _historyPage;
    });
    _reload();
  }

  bool _hasTag(YouThought thought) {
    final tag = _tag;
    return tag == null || hasThoughtTag(thought.post.text, tag.key);
  }

  Future<void> _openChat(String peerId) async {
    await widget.onOpenChat(peerId);
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = _data;
    final tag = _tag;
    final thought = data?.thought;
    final shown = [
      if (data != null)
        for (final each in [?thought, ...data.past])
          if (_hasTag(each)) each,
    ];
    final empty = _mono.copyWith(color: _muted, fontSize: 12);
    return Scaffold(
      key: const ValueKey('you'),
      backgroundColor: _ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, l10n, data),
            const Divider(height: 1, color: _hairline),
            if (tag != null)
              _TagBar(
                label: _tagLabel,
                count: data?.tag == tag.key ? data!.tagCount : shown.length,
                onClear: () => _showTag(null),
              ),
            Expanded(
              child: data == null
                  ? const SizedBox.shrink()
                  : shown.isEmpty && tag == null
                  ? Center(child: Text(l10n.you_page_empty, style: empty))
                  : NotificationListener<ScrollNotification>(
                      onNotification: _loadOlderAtTop,
                      child: ListView(
                        key: const ValueKey('you-feed'),
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        children: [
                          if (thought == null && tag == null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                l10n.you_page_empty,
                                textAlign: TextAlign.center,
                                style: empty,
                              ),
                            ),
                          for (final each in shown)
                            _ThoughtCard(
                              key: ValueKey('you-thought-${each.post.id}'),
                              thought: each,
                              live: identical(each, thought),
                              now: widget.now,
                              onOpenChat: _openChat,
                              onOpenMedia: (visual, index) =>
                                  _openMedia(each.post.id, visual, index),
                              activeTag: tag?.key,
                              onTag: _showTag,
                            ),
                        ],
                      ),
                    ),
            ),
            _ComposerBar(
              label: tag == null
                  ? l10n.thought_compose_open
                  : l10n.you_page_add_to_tag(_tagLabel),
              tag: tag == null ? null : _tagLabel,
              onTap: _compose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    YouPageData? data,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 8, 10),
    child: Row(
      children: [
        IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: _ink),
        ),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x991DB954), width: 2),
          ),
          child: UserAvatar(
            avatarBytes: data?.avatarBytes,
            size: 28,
            showGlow: false,
          ),
        ),
        const SizedBox(width: 12),
        if (data != null)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'you/',
                        style: TextStyle(color: _accent),
                      ),
                      TextSpan(text: ' @${data.username}'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono.copyWith(
                    color: _ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const _ColourDot(color: _friendsBlue, size: 7),
                    const SizedBox(width: 6),
                    Text(
                      l10n.you_page_friends(data.friendCount),
                      style: _mono.copyWith(color: _muted, fontSize: 11.5),
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

class _ThoughtCard extends StatelessWidget {
  const _ThoughtCard({
    super.key,
    required this.thought,
    required this.live,
    required this.now,
    required this.onOpenChat,
    required this.onOpenMedia,
    required this.activeTag,
    required this.onTag,
  });

  final YouThought thought;

  /// Only the live Thought says how long it stays up.
  final bool live;
  final DateTime Function() now;
  final Future<void> Function(String peerId) onOpenChat;
  final Future<void> Function(List<PostMediaAttachmentModel> visual, int index)
  onOpenMedia;
  final String? activeTag;
  final void Function(ThoughtTag tag, String label) onTag;

  int _hoursLeft() {
    final expiry = DateTime.tryParse(thought.post.expiresAt)?.toUtc();
    if (expiry == null) return 1;
    final left = expiry.difference(now().toUtc()).inMicroseconds;
    return (left / Duration.microsecondsPerHour).ceil().clamp(1, 24);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final post = thought.post;
    final visual = [
      for (final m in post.media)
        if (m.kind == 'image' || m.kind == 'video') m,
    ]..sort((a, b) => a.position.compareTo(b.position));
    final localPhotos = [
      if (!post.isIncoming && post.media.isEmpty && post.mediaKind != 'none')
        for (final source in post.localMediaSources)
          if (source.kind == 'image') source,
    ]..sort((a, b) => a.position.compareTo(b.position));
    final voice = [
      for (final m in post.media)
        if (m.kind == 'voice') m,
    ];
    final reacted = {
      for (final group in thought.reactions)
        for (final p in group.participants) p.peerId,
    }.length;
    final wrote = thought.wroteBack;
    final fresh = wrote.where((w) => w.hasUnread).length;
    final label = _mono.copyWith(color: _muted, fontSize: 11.5);
    final created = DateTime.tryParse(post.createdAt);
    final picked = post.audience.kind == PostAudienceKind.pickPeople
        ? post.audience.selectedPeerIds.length
        : 0;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (created != null) ...[
            Text(
              formatDaySeparatorLabel(
                created,
                now: now(),
                todayLabel: l10n.date_today,
                yesterdayLabel: l10n.date_yesterday,
                locale: Localizations.localeOf(context).toLanguageTag(),
              ),
              style: label,
            ),
            const SizedBox(height: 6),
          ],
          _AudienceChip(
            label: picked == 0
                ? l10n.compose_audience_all
                : l10n.you_page_people(picked),
          ),
          if (post.text.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            _TaggedText(text: post.text, activeTag: activeTag, onTag: onTag),
          ],
          if (visual.isNotEmpty) ...[
            const SizedBox(height: 8),
            _MediaGrid(
              tiles: [
                for (var i = 0; i < visual.length; i++)
                  GestureDetector(
                    key: ValueKey('you-media-${visual[i].mediaId}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onOpenMedia(visual, i),
                    child: _MediaTile(
                      path: visual[i].localPath,
                      kind: visual[i].kind,
                      durationMs: visual[i].durationMs,
                    ),
                  ),
              ],
            ),
          ] else if (localPhotos.isNotEmpty) ...[
            const SizedBox(height: 8),
            _MediaGrid(
              tiles: [
                for (final source in localPhotos)
                  _MediaTile(path: source.localFilePath, kind: source.kind),
              ],
            ),
          ],
          for (final attachment in voice) ...[
            const SizedBox(height: 8),
            if (attachment.caption case final caption?)
              ThoughtVoiceCaption(caption, color: _muted),
            AudioPlayerWidget(
              key: ValueKey('you-voice-${attachment.mediaId}'),
              attachment: attachment.toSharedMediaAttachment(),
            ),
          ],
          if (live) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0x2E1DB954), spreadRadius: 3),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    picked == 0
                        ? l10n.you_page_live(_hoursLeft())
                        : l10n.you_page_live_people(picked, _hoursLeft()),
                    style: label,
                  ),
                ),
              ],
            ),
          ],
          if (reacted > 0 || wrote.isNotEmpty) const SizedBox(height: 10),
          if (reacted > 0)
            _ResponseRow(
              label: Text(l10n.you_page_reacted(reacted), style: label),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final group in thought.reactions)
                    for (final person in group.participants)
                      _ReactionFace(
                        key: ValueKey(
                          'you-reaction-${person.peerId}-${group.reaction.name}',
                        ),
                        peerId: person.peerId,
                        name: person.name,
                        glyph: group.reaction.glyph,
                      ),
                ],
              ),
            ),
          if (reacted > 0 && wrote.isNotEmpty) const SizedBox(height: 8),
          // Who wrote, never what: the words live in your chats.
          if (wrote.isNotEmpty)
            _ResponseRow(
              label: Text.rich(
                TextSpan(
                  text: l10n.you_page_wrote_back(wrote.length),
                  children: [
                    if (fresh > 0)
                      TextSpan(
                        text: ' ${l10n.you_page_new_replies(fresh)}',
                        style: const TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                style: label,
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final person in wrote)
                    _WroteFace(
                      person: person,
                      onTap: () => onOpenChat(person.peerId),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A label and the faces it names, side by side.
class _ResponseRow extends StatelessWidget {
  const _ResponseRow({required this.label, required this.child});

  final Widget label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 92),
        child: label,
      ),
      const SizedBox(width: 10),
      Expanded(child: child),
    ],
  );
}

class _AudienceChip extends StatelessWidget {
  const _AudienceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 20,
    padding: const EdgeInsets.only(left: 6, right: 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _hairline),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _ColourDot(color: _friendsBlue, size: 6),
        const SizedBox(width: 6),
        Text(label, style: _mono.copyWith(color: _muted, fontSize: 11.5)),
      ],
    ),
  );
}

class _ColourDot extends StatelessWidget {
  const _ColourDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// One face wearing what that person sent.
class _ReactionFace extends StatelessWidget {
  const _ReactionFace({
    super.key,
    required this.peerId,
    required this.name,
    required this.glyph,
  });

  final String peerId;
  final String name;
  final String glyph;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: name,
    triggerMode: TooltipTriggerMode.longPress,
    child: Semantics(
      label: '$name $glyph',
      excludeSemantics: true,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            UserAvatar(peerId: peerId, size: 28, showGlow: false),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: const BoxDecoration(
                  color: _ground,
                  shape: BoxShape.circle,
                ),
                child: Text(glyph, style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WroteFace extends StatelessWidget {
  const _WroteFace({required this.person, required this.onTap});

  final YouWroteBack person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: person.name,
    triggerMode: TooltipTriggerMode.longPress,
    child: Semantics(
      button: true,
      label: person.name,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('you-wrote-${person.peerId}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(peerId: person.peerId, size: 28, showGlow: false),
              if (person.hasUnread)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    key: ValueKey('you-unread-${person.peerId}'),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: _ground, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The Thought's photos and videos, laid out as on the prototype feed.
class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return switch (tiles.length) {
      1 => SizedBox(height: 170, child: tiles[0]),
      2 => SizedBox(
        height: 140,
        child: Row(
          children: [
            Expanded(child: tiles[0]),
            const SizedBox(width: 4),
            Expanded(child: tiles[1]),
          ],
        ),
      ),
      _ => SizedBox(
        height: 180,
        child: Row(
          children: [
            Expanded(flex: 3, child: tiles[0]),
            const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Expanded(child: tiles[1]),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        tiles[2],
                        if (tiles.length > 3)
                          IgnorePointer(
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0x99000000),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '+${tiles.length - 3}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
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
          ],
        ),
      ),
    };
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.path, required this.kind, this.durationMs});

  final String? path;
  final String kind;
  final int? durationMs;

  String _duration() {
    final seconds = ((durationMs ?? 0) / 1000).round();
    return '${seconds ~/ 60}:${'${seconds % 60}'.padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final video = kind == 'video';
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF111614)),
          if (path != null)
            MediaThumbnailImage(
              mediaPath: MediaFileManager.resolveStoredPathSync(path!),
              mediaType: kind,
              fit: BoxFit.cover,
            ),
          if (video) ...[
            Center(
              child: ClipOval(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _duration(),
                  style: _mono.copyWith(color: Colors.white, fontSize: 11.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The prototype's composer bar, as a door: tapping anywhere on it opens the
/// app's write sheet.
class _ComposerBar extends StatelessWidget {
  const _ComposerBar({required this.label, this.tag, required this.onTap});

  final String label;

  /// The open tag, set in the tag type inside [label].
  final String? tag;
  final VoidCallback onTap;

  TextSpan _hintWithTag() {
    final tag = this.tag;
    final at = tag == null ? -1 : label.indexOf(tag);
    if (tag == null || at < 0) return TextSpan(text: label);
    return TextSpan(
      children: [
        TextSpan(text: label.substring(0, at)),
        TextSpan(
          text: tag,
          style: thoughtTagStyle(const TextStyle(fontSize: 15), color: _soft),
        ),
        TextSpan(text: label.substring(at + tag.length)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0x2E05070C),
            border: Border(top: BorderSide(color: _hairline)),
          ),
          padding: EdgeInsets.fromLTRB(
            12,
            10,
            12,
            MediaQuery.paddingOf(context).bottom + 10,
          ),
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: GestureDetector(
              key: const ValueKey('you-composer'),
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0x0FFFFFFF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.image_outlined,
                      color: Color(0xFFC7CEC9),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 44,
                      alignment: AlignmentDirectional.centerStart,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0x0DFFFFFF),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: _hairline),
                      ),
                      child: Text.rich(
                        _hintWithTag(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8A8F98),
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0x401DB954),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_upward_rounded,
                      color: Color(0xFF03140A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Your words with each #tag in the tag type. A tag opens your own log of
/// the Thoughts that carry it.
class _TaggedText extends StatelessWidget {
  const _TaggedText({
    required this.text,
    required this.activeTag,
    required this.onTag,
  });

  final String text;

  /// The open tag's key: its mentions stand out.
  final String? activeTag;
  final void Function(ThoughtTag tag, String label) onTag;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: _ink,
      fontSize: 16,
      height: 1.4,
      fontWeight: FontWeight.w500,
    );
    final tagStyle = thoughtTagStyle(style, color: _soft);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final tag in parseThoughtTags(text)) {
      if (tag.start > at) {
        spans.add(TextSpan(text: text.substring(at, tag.start)));
      }
      final label = text.substring(tag.start, tag.end);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTag(tag, label),
              child: tag.key == activeTag
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: const Color(0x1AE8ECE9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        key: ValueKey('you-tag-${tag.key}'),
                        style: tagStyle.copyWith(color: _ink),
                      ),
                    )
                  : Text(
                      label,
                      key: ValueKey('you-tag-${tag.key}'),
                      style: tagStyle,
                    ),
            ),
          ),
        ),
      );
      at = tag.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(children: spans), style: style);
  }
}

/// Over your log while a tag is open: the tag in a pill whose X goes back
/// to everything, how many Thoughts carry it, and that nobody else sees it.
class _TagBar extends StatelessWidget {
  const _TagBar({
    required this.label,
    required this.count,
    required this.onClear,
  });

  final String label;
  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final small = _mono.copyWith(fontSize: 11.5);
    return Container(
      key: const ValueKey('you-tag-bar'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _hairline)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Semantics(
                    button: true,
                    label: MaterialLocalizations.of(context).closeButtonTooltip,
                    child: GestureDetector(
                      key: const ValueKey('you-tag-clear'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onClear,
                      child: Container(
                        height: 32,
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          12,
                          0,
                          6,
                          0,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x14E8ECE9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _mono.copyWith(
                                  color: _ink,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                color: Color(0x1FE8ECE9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: _ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.you_page_tag_count(count),
                  style: small.copyWith(color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              l10n.you_page_tag_private,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small.copyWith(color: _faint),
            ),
          ),
        ],
      ),
    );
  }
}
