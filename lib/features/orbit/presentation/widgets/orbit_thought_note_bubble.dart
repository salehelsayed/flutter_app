import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/press_feedback.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_thought_note.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_media_preview_label.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// A thought's two-line preview. An unseen note is bold and outlined; a seen
/// one is regular and dimmer. The outline never changes the layout.
class OrbitThoughtNoteBubble extends StatelessWidget {
  static const tailHeight = 11.0;
  static const _padding = EdgeInsets.symmetric(horizontal: 9, vertical: 6);

  final OrbitThoughtNote note;
  final String? _authorName;
  final VoidCallback? onTap;

  /// A friend's note, read as "Thought from [authorName]".
  const OrbitThoughtNoteBubble({
    super.key,
    required this.note,
    required String authorName,
    this.onTap,
  }) : _authorName = authorName;

  /// The user's own note, read as "Your thought".
  const OrbitThoughtNoteBubble.own({super.key, required this.note, this.onTap})
    : _authorName = null;

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

  /// Includes the tail. Uses the same direction, text scaler and weight as the
  /// rendered text, so collision geometry remains valid for accessibility.
  static Size measure(BuildContext context, OrbitThoughtNote note) {
    final preview = _preview(context, note);
    final painter = TextPainter(
      text: TextSpan(text: preview, style: _resolvedStyle(context, note)),
      textAlign: TextAlign.center,
      textDirection: _previewDirection(context, note, preview),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: note.hasUnsupportedMedia ? null : 2,
      ellipsis: note.hasUnsupportedMedia ? null : '…',
    )..layout(maxWidth: 132);
    final result = Size(
      (painter.width + 18).clamp(40.0, 150.0).toDouble(),
      painter.height + 12 + tailHeight,
    );
    painter.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final size = measure(context, note);
    final preview = _preview(context, note);
    final l10n = AppLocalizations.of(context)!;
    final authorName = _authorName;
    final tap = note.hasUnsupportedMedia ? null : onTap;
    return Semantics(
      button: tap != null,
      label: authorName == null
          ? l10n.orbit_thought_note_self_semantics(preview)
          : note.isRead
          ? l10n.orbit_thought_note_semantics(authorName, preview)
          : l10n.orbit_thought_note_new_semantics(authorName, preview),
      onTap: tap,
      excludeSemantics: true,
      child: GestureDetector(
        // Retire an in-flight press when a newer thought replaces this one.
        key: ValueKey('orbit-thought-tap-${note.postId}'),
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Column(
            children: [
              Container(
                width: size.width,
                height: size.height - tailHeight,
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
                  maxLines: note.hasUnsupportedMedia ? null : 2,
                  overflow: note.hasUnsupportedMedia
                      ? TextOverflow.clip
                      : TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: _resolvedStyle(context, note),
                ),
              ),
              const SizedBox(height: 2),
              const _ThoughtTailDot(size: 5),
              const SizedBox(height: 1),
              const _ThoughtTailDot(size: 3),
            ],
          ),
        ),
      ).withPressFeedback(),
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
