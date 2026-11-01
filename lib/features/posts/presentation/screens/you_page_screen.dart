import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/posts/application/group_thought_reactions.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';

class YouPageData {
  const YouPageData({
    required this.username,
    required this.avatarBytes,
    required this.friendCount,
    required this.thought,
  });

  final String username;
  final Uint8List? avatarBytes;
  final int friendCount;

  /// The one live own Thought, or null when nothing is up.
  final YouThought? thought;
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
const _mono = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: ['Courier', 'monospace'],
);

/// Your own page, opened from your photo in the middle of Orbit: your live
/// Thought, who reacted, and who wrote back. A face that wrote opens your
/// chat with them; nobody else sees what they wrote.
class YouPageScreen extends StatefulWidget {
  const YouPageScreen({
    super.key,
    required this.load,
    required this.onBack,
    required this.onOpenChat,
    required this.onCompose,
    required this.now,
  });

  final Future<YouPageData> Function() load;
  final VoidCallback onBack;
  final Future<void> Function(String peerId) onOpenChat;

  /// Opens the write sheet and completes once it has closed.
  final Future<void> Function() onCompose;
  final DateTime Function() now;

  @override
  State<YouPageScreen> createState() => _YouPageScreenState();
}

class _YouPageScreenState extends State<YouPageScreen> {
  YouPageData? _data;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final data = await widget.load();
      if (mounted && generation == _generation) setState(() => _data = data);
    } catch (_) {
      // The page keeps what it last showed; the next open or share reloads.
    }
  }

  Future<void> _compose() async {
    await widget.onCompose();
    if (mounted) await _reload();
  }

  Future<void> _openChat(String peerId) async {
    await widget.onOpenChat(peerId);
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = _data;
    final thought = data?.thought;
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
            Expanded(
              child: data == null
                  ? const SizedBox.shrink()
                  : thought == null
                  ? Center(
                      child: Text(
                        l10n.you_page_empty,
                        style: _mono.copyWith(color: _muted, fontSize: 12),
                      ),
                    )
                  : ListView(
                      key: const ValueKey('you-feed'),
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      children: [
                        _ThoughtCard(
                          thought: thought,
                          now: widget.now,
                          onOpenChat: _openChat,
                        ),
                      ],
                    ),
            ),
            _ComposerBar(onTap: _compose),
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
    required this.thought,
    required this.now,
    required this.onOpenChat,
  });

  final YouThought thought;
  final DateTime Function() now;
  final Future<void> Function(String peerId) onOpenChat;

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
    final reacted = {
      for (final group in thought.reactions)
        for (final p in group.participants) p.peerId,
    }.length;
    final wrote = thought.wroteBack;
    final fresh = wrote.where((w) => w.hasUnread).length;
    final label = _mono.copyWith(color: _muted, fontSize: 11.5);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AudienceChip(label: l10n.compose_audience_all),
          if (post.text.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              post.text,
              style: const TextStyle(
                color: _ink,
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (visual.isNotEmpty) ...[
            const SizedBox(height: 8),
            _MediaGrid(visual: visual),
          ],
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
                child: Text(l10n.you_page_live(_hoursLeft()), style: label),
              ),
            ],
          ),
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
  const _MediaGrid({required this.visual});

  final List<PostMediaAttachmentModel> visual;

  @override
  Widget build(BuildContext context) {
    Widget tile(int i) => _MediaTile(media: visual[i]);
    return switch (visual.length) {
      1 => SizedBox(height: 170, child: tile(0)),
      2 => SizedBox(
        height: 140,
        child: Row(
          children: [
            Expanded(child: tile(0)),
            const SizedBox(width: 4),
            Expanded(child: tile(1)),
          ],
        ),
      ),
      _ => SizedBox(
        height: 180,
        child: Row(
          children: [
            Expanded(flex: 3, child: tile(0)),
            const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Expanded(child: tile(1)),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        tile(2),
                        if (visual.length > 3)
                          Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0x99000000),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '+${visual.length - 3}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
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
  const _MediaTile({required this.media});

  final PostMediaAttachmentModel media;

  String _duration() {
    final seconds = ((media.durationMs ?? 0) / 1000).round();
    return '${seconds ~/ 60}:${'${seconds % 60}'.padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final video = media.kind == 'video';
    final path = media.localPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF111614)),
          if (path != null)
            MediaThumbnailImage(
              mediaPath: MediaFileManager.resolveStoredPathSync(path),
              mediaType: media.kind,
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
  const _ComposerBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
            label: l10n.thought_compose_open,
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
                      child: Text(
                        l10n.thought_compose_open,
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
