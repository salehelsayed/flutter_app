import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/press_feedback.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_thought_note.dart';
import 'package:flutter_app/features/orbit/domain/orbit_thought_layout.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_media_preview_label.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// A thought's two-line preview. An unseen note is bold and outlined; a seen
/// one is regular and dimmer. The outline never changes the layout.
class OrbitThoughtNoteBubble extends StatelessWidget {
  static const _padding = EdgeInsets.symmetric(horizontal: 9, vertical: 6);

  final OrbitThoughtNote note;
  final String? _authorName;
  final VoidCallback? onTap;
  final OrbitThoughtPlacement? placement;
  final Offset? avatarCenter;

  /// A friend's note, read as "Thought from [authorName]".
  const OrbitThoughtNoteBubble({
    super.key,
    required this.note,
    required String authorName,
    this.onTap,
    this.placement,
    this.avatarCenter,
  }) : _authorName = authorName;

  /// The user's own note, read as "Your thought".
  const OrbitThoughtNoteBubble.own({
    super.key,
    required this.note,
    this.onTap,
    this.placement,
    this.avatarCenter,
  }) : _authorName = null;

  static TextStyle textStyle({required bool isRead}) => TextStyle(
    color: isRead ? const Color(0xFFBDBDBD) : const Color(0xFFF5F5F5),
    fontSize: 11.5,
    height: 1.22,
    fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
  );

  /// The inherited app text style (the phone's real font) merged with the
  /// note style, so measuring and painting lay out the same glyphs.
  static TextStyle _resolvedStyle(
    BuildContext context,
    OrbitThoughtNote note,
  ) => DefaultTextStyle.of(context).style.merge(textStyle(isRead: note.isRead));

  static String _preview(BuildContext context, OrbitThoughtNote note) {
    final l10n = AppLocalizations.of(context)!;
    return note.hasUnsupportedMedia
        ? l10n.thought_update_to_view
        : orbitMediaPreviewLabel(
            l10n: l10n,
            caption: note.text,
            media: note.media,
          );
  }

  static TextDirection _previewDirection(
    BuildContext context,
    OrbitThoughtNote note,
    String preview,
  ) => note.hasUnsupportedMedia
      ? Directionality.of(context)
      : detectTextDirection(preview);

  static String semanticLabel(
    BuildContext context,
    OrbitThoughtNote note, {
    String? authorName,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final preview = _preview(context, note);
    return authorName == null
        ? l10n.orbit_thought_note_self_semantics(preview)
        : note.isRead
        ? l10n.orbit_thought_note_semantics(authorName, preview)
        : l10n.orbit_thought_note_new_semantics(authorName, preview);
  }

  /// Uses the same direction, text scaler and weight as the rendered text.
  static Size measureBody(
    BuildContext context,
    OrbitThoughtNote note, {
    bool compact = false,
  }) {
    final preview = _preview(context, note);
    final maxWidth = compact ? 96 - orbitThoughtTailSize : 150.0;
    final painter = TextPainter(
      text: TextSpan(text: preview, style: _resolvedStyle(context, note)),
      textAlign: TextAlign.center,
      textDirection: _previewDirection(context, note, preview),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: _maxLines(note, compact),
      ellipsis: _maxLines(note, compact) == null ? null : '…',
    )..layout(maxWidth: maxWidth - _padding.horizontal);
    final result = Size(
      (painter.width + _padding.horizontal).clamp(40.0, maxWidth).toDouble(),
      painter.height + _padding.vertical,
    );
    painter.dispose();
    return result;
  }

  static int? _maxLines(OrbitThoughtNote note, bool compact) => compact
      ? 1
      : note.hasUnsupportedMedia
      ? null
      : 2;

  @override
  Widget build(BuildContext context) {
    final placement = this.placement;
    final side = placement?.side ?? OrbitThoughtSide.above;
    final compact = placement?.compact ?? false;
    final vertical =
        side == OrbitThoughtSide.above || side == OrbitThoughtSide.below;
    final tailWidth = vertical ? 0.0 : orbitThoughtTailSize;
    final tailHeight = vertical ? orbitThoughtTailSize : 0.0;
    final body = placement == null
        ? measureBody(context, note)
        : Size(
            placement.rect.width - tailWidth,
            placement.rect.height - tailHeight,
          );
    final bodyLeft = side == OrbitThoughtSide.right ? tailWidth : 0.0;
    final bodyTop = side == OrbitThoughtSide.below ? tailHeight : 0.0;
    final preview = _preview(context, note);
    final tap = note.hasUnsupportedMedia ? null : onTap;
    final avatar = placement != null && avatarCenter != null
        ? avatarCenter! - placement.rect.topLeft
        : Offset(body.width / 2, body.height / 2);

    return Semantics(
      button: tap != null,
      label: semanticLabel(context, note, authorName: _authorName),
      onTap: tap,
      excludeSemantics: true,
      child: GestureDetector(
        // Retire an in-flight press when a newer thought replaces this one.
        key: ValueKey('orbit-thought-tap-${note.postId}'),
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: SizedBox(
          width: body.width + tailWidth,
          height: body.height + tailHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: bodyLeft,
                top: bodyTop,
                width: body.width,
                height: body.height,
                child: Container(
                  padding: _padding,
                  decoration: BoxDecoration(
                    color: const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x59000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  foregroundDecoration: note.isRead
                      ? null
                      : BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xD9FFFFFF),
                            width: 1.5,
                          ),
                        ),
                  child: Text(
                    preview,
                    textDirection: _previewDirection(context, note, preview),
                    maxLines: _maxLines(note, compact),
                    overflow: _maxLines(note, compact) == null
                        ? TextOverflow.clip
                        : TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: _resolvedStyle(context, note),
                  ),
                ),
              ),
              _tailDot(side, body, avatar, 5, 2),
              _tailDot(side, body, avatar, 3, 8),
            ],
          ),
        ),
      ).withPressFeedback(),
    );
  }

  Widget _tailDot(
    OrbitThoughtSide side,
    Size body,
    Offset avatar,
    double size,
    double gap,
  ) {
    final left = avatar.dx.clamp(8.0, body.width - 8).toDouble() - size / 2;
    final top =
        (body.height <= 16
            ? body.height / 2
            : avatar.dy.clamp(8.0, body.height - 8).toDouble()) -
        size / 2;
    final position = switch (side) {
      OrbitThoughtSide.above => Offset(left, body.height + gap),
      OrbitThoughtSide.below => Offset(left, orbitThoughtTailSize - gap - size),
      OrbitThoughtSide.right => Offset(orbitThoughtTailSize - gap - size, top),
      OrbitThoughtSide.left => Offset(body.width + gap, top),
    };
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: _ThoughtTailDot(size: size),
    );
  }
}

class _ThoughtTailDot extends StatelessWidget {
  final double size;
  const _ThoughtTailDot({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: Color(0xFF262626),
      shape: BoxShape.circle,
    ),
  );
}
