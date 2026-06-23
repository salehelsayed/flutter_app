import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

/// The role a [LetterBubble] plays in the redesigned Feed "letters" inbox
/// (134 §3). Drives fill / border / glow / alignment — there is no per-message
/// timestamp, status tick, reaction chip, or unread pill on a letter.
enum LetterBubbleRole {
  /// A message received from the contact (left-aligned).
  incoming,

  /// A message sent by the local user (right-aligned).
  outgoing,

  /// A system / informational note (left-aligned, green-accented).
  system,
}

/// A single chat "letter" bubble: a blurred, rounded, token-driven container
/// holding one source message — its body text AND its media. Media is rendered
/// the SAME way as the 1:1 chat / group conversation screens: an image/video
/// [MediaGrid] (tap → [FullScreenImageViewer]) and an inline [AudioPlayerWidget]
/// per voice attachment. Pure leaf widget — no timestamp, status tick,
/// "(edited)", reaction chips, or unread pill (134 §3).
///
/// All colours, blur sigma, and radius are read from `context.feedTokens`;
/// nothing is hardcoded. RTL is render-derived from the body text via
/// [detectTextDirection] (no model `rtl` field).
class LetterBubble extends StatelessWidget {
  /// The body text rendered inside the bubble. May be empty for a media-only
  /// (caption-less) message — in that case only the media is rendered.
  final String text;

  /// The message's media attachments (already path-resolved). Rendered above
  /// the text pill, mirroring the conversation `LetterCard`.
  final List<MediaAttachment> media;

  /// The bubble role — drives fill / border / glow / alignment.
  final LetterBubbleRole role;

  /// Whether an `incoming` letter is the focused one (raised surface, teal
  /// border + glow). No effect on `outgoing` / `system` roles.
  final bool focused;

  /// Owned-media directory id (1:1 contact peerId / groupId) for the
  /// render-boundary fallback to the durable owned copy — forwarded to
  /// [MediaGrid], same as the conversation cards.
  final String? ownedMediaPeerId;

  /// Group media must verify its content hash before display; 1:1 does not.
  /// Forwarded to [MediaGrid] / [AudioPlayerWidget].
  final bool requireVerifiedContentHash;

  const LetterBubble({
    super.key,
    required this.text,
    required this.role,
    this.media = const [],
    this.focused = false,
    this.ownedMediaPeerId,
    this.requireVerifiedContentHash = false,
  });

  List<MediaAttachment> get _imageVideoMedia => media
      .where((a) => a.mediaType == 'image' || a.mediaType == 'video')
      .toList();

  List<MediaAttachment> get _audioMedia =>
      media.where((a) => a.mediaType == 'audio').toList();

  @override
  Widget build(BuildContext context) {
    final tokens = context.feedTokens;
    final alignment = role == LetterBubbleRole.outgoing
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final crossAxis = role == LetterBubbleRole.outgoing
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final maxWidth = MediaQuery.of(context).size.width * 0.76;

    final imageVideo = _imageVideoMedia;
    final audio = _audioMedia;

    final children = <Widget>[];

    // Media grid (images/videos) — tap opens the same full-screen viewer the
    // chat uses.
    if (imageVideo.isNotEmpty) {
      children.add(
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: MediaGrid(
            media: imageVideo,
            onTap: (index) => _openMediaViewer(context, imageVideo, index),
            requireVerifiedContentHash: requireVerifiedContentHash,
            ownedMediaPeerId: ownedMediaPeerId,
          ),
        ),
      );
    }

    // Inline voice players — one per audio attachment.
    for (final attachment in audio) {
      if (children.isNotEmpty) {
        children.add(SizedBox(height: tokens.space3 * 0.5));
      }
      children.add(
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: AudioPlayerWidget(
            key: ValueKey('feed-audio-${attachment.id}'),
            attachment: attachment,
            requireVerifiedContentHash: requireVerifiedContentHash,
          ),
        ),
      );
    }

    // Body text pill — only when there is text (a caption-less media message
    // renders no empty bubble). When the line has no media AND no text we still
    // render an (empty) pill to preserve the prior layout contract.
    if (text.isNotEmpty || children.isEmpty) {
      if (children.isNotEmpty) {
        children.add(SizedBox(height: tokens.space3 * 0.5));
      }
      children.add(_buildTextPill(context, tokens, maxWidth));
    }

    return Align(
      alignment: alignment,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxis,
        children: children,
      ),
    );
  }

  Widget _buildTextPill(BuildContext context, FeedTokens tokens, double maxWidth) {
    final radius = BorderRadius.circular(tokens.radiusFull);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: tokens.blurLetter,
          sigmaY: tokens.blurLetter,
        ),
        child: Container(
          decoration: _decorationFor(tokens),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Text(
              text,
              textDirection: detectTextDirection(text),
              style: tokens.textMessage,
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the tapped image/video in the shared full-screen viewer, with the
  /// run's other displayable items as the swipe gallery — identical to the
  /// conversation screen's media-tap handler.
  void _openMediaViewer(
    BuildContext context,
    List<MediaAttachment> visual,
    int index,
  ) {
    if (index >= visual.length) return;
    final tapped = visual[index];
    if (tapped.localPath == null) return;
    final allPaths = visual
        .where((a) => a.localPath != null && a.downloadStatus == 'done')
        .map((a) => a.localPath!)
        .toList();
    if (allPaths.isEmpty) return;
    final startIndex = allPaths
        .indexOf(tapped.localPath!)
        .clamp(0, allPaths.length - 1);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenImageViewer(
          localPath: tapped.localPath!,
          allPaths: allPaths,
          initialIndex: startIndex,
        ),
      ),
    );
  }

  BoxDecoration _decorationFor(FeedTokens tokens) {
    final radius = BorderRadius.circular(tokens.radiusFull);

    switch (role) {
      case LetterBubbleRole.incoming:
        if (focused) {
          return BoxDecoration(
            color: tokens.surfaceRaised,
            borderRadius: radius,
            border: Border.all(color: tokens.teal400, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: tokens.teal400.withValues(alpha: 0.30),
                blurRadius: 16,
              ),
            ],
          );
        }
        return BoxDecoration(
          color: tokens.surfaceSubtle,
          borderRadius: radius,
          border: Border.all(color: tokens.borderSoft, width: 1.0),
        );
      case LetterBubbleRole.outgoing:
      case LetterBubbleRole.system:
        return BoxDecoration(
          color: tokens.greenFill15,
          borderRadius: radius,
          border: Border.all(color: tokens.green500, width: 1.0),
        );
    }
  }
}
