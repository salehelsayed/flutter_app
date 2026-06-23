import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/media/video_thumbnail_cache.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';

/// Horizontal thumbnail strip shown above the compose area when
/// the user has picked attachments to send.
///
/// Each thumbnail is 72x72 with a small X button to remove it.
/// During upload, a dark scrim + spinner overlays each thumbnail.
class AttachmentPreviewStrip extends StatelessWidget {
  final List<File> attachments;
  final bool isUploading;
  final bool isProcessing;
  final double processingProgress;
  final int processingCurrent;
  final int processingTotal;

  /// Indices of picked attachments that failed a size/GIF SEND policy (149).
  /// Each renders an inline red error chip; Send is disabled while any present.
  final Set<int> invalidIndices;

  /// Per-index normalized rejection reason (`too_large` | `gif_too_large`) used
  /// to pick the short chip caption.
  final Map<int, String> invalidReasons;

  /// True when each attachment is individually valid but the combined size
  /// exceeds the whole-message cap (149 — group only). Renders a strip-level
  /// note above the thumbnails (no per-chip border, since it owns no index).
  final bool hasTotalSizeOverflow;
  final ValueChanged<int>? onRemove;

  const AttachmentPreviewStrip({
    super.key,
    required this.attachments,
    this.isUploading = false,
    this.isProcessing = false,
    this.processingProgress = 0.0,
    this.processingCurrent = 0,
    this.processingTotal = 0,
    this.invalidIndices = const {},
    this.invalidReasons = const {},
    this.hasTotalSizeOverflow = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final totalCount = attachments.length + (isProcessing ? 1 : 0);
    final list = SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: totalCount,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (isProcessing && index == totalCount - 1) {
            return _ProcessingThumbnail(
              progress: processingProgress,
              current: processingCurrent,
              total: processingTotal,
            );
          }
          return _Thumbnail(
            file: attachments[index],
            index: index,
            isUploading: isUploading,
            isInvalid: invalidIndices.contains(index),
            reasonText: invalidReasons[index],
            onRemove: onRemove != null ? () => onRemove!(index) : null,
          );
        },
      ),
    );
    if (!hasTotalSizeOverflow) return list;
    // 149: whole-message overflow owns no single index → strip-level note.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: const ValueKey('attachment-total-overflow'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              const Icon(
                Icons.error_outline,
                size: 16,
                color: Color(0xFFFF5252),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.media_attachments_too_large_note,
                  style: const TextStyle(
                    color: Color(0xFFFF8A80),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        list,
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final File file;
  final int index;
  final bool isUploading;

  /// True when this attachment failed a size/GIF SEND policy (149). Paints an
  /// inline red error chip (border + warning + short caption); never painted
  /// over an in-flight upload (the invalid branch is `isInvalid && !isUploading`).
  final bool isInvalid;

  /// Normalized rejection reason for the invalid caption (`too_large` |
  /// `gif_too_large`). Null when [isInvalid] is false.
  final String? reasonText;
  final VoidCallback? onRemove;

  const _Thumbnail({
    required this.file,
    required this.index,
    required this.isUploading,
    this.isInvalid = false,
    this.reasonText,
    this.onRemove,
  });

  String _invalidCaption(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return reasonText == 'gif_too_large'
        ? l10n.media_gif_too_large_chip
        : l10n.media_too_large_chip;
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final mediaType = isLikelyVideoPath(file.path) ? 'video' : 'image';
    final showsInvalid = isInvalid && !isUploading;
    final showsGifBadge =
        !isUploading &&
        !showsInvalid &&
        mediaType == 'image' &&
        file.path.toLowerCase().endsWith('.gif');
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Thumbnail image
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: MediaThumbnailImage(
              mediaPath: file.path,
              mediaType: mediaType,
              fit: BoxFit.cover,
              cacheWidth: 200,
              placeholder: Container(
                width: 72,
                height: 72,
                color: readableColors.surfaceSubtle,
              ),
              error: Container(
                width: 72,
                height: 72,
                color: readableColors.surfaceSubtle,
                child: Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 18,
                    color: readableColors.iconMuted,
                  ),
                ),
              ),
            ),
          ),
          // Upload overlay
          if (isUploading)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 72,
                height: 72,
                color: const Color.fromRGBO(0, 0, 0, 0.5),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
          if (showsGifBadge)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(0, 0, 0, 0.7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'GIF',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          // 149: inline size/GIF rejection chip — red border + warning + short
          // caption. Never painted over an in-flight upload. The remove X stays
          // (rendered after this in the Stack so it sits on top + tappable).
          if (showsInvalid)
            Positioned.fill(
              key: ValueKey('attachment-invalid-$index'),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(120, 0, 0, 0.45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFFF5252),
                      width: 2,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _invalidCaption(context),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Remove button (hidden during upload)
          if (!isUploading && onRemove != null)
            Positioned(
              top: -6,
              right: -6,
              child: GestureDetector(
                onTap: onRemove,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color.fromRGBO(0, 0, 0, 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProcessingThumbnail extends StatelessWidget {
  final double progress;
  final int current;
  final int total;

  const _ProcessingThumbnail({
    required this.progress,
    required this.current,
    required this.total,
  });

  String get _label {
    if (total > 1 && current > 0) {
      return 'Processing ($current/$total)';
    }
    return 'Processing';
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final percent = (progress * 100).round();
    return SizedBox(
      width: 72,
      height: 72,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: readableColors.surfaceSubtle,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: readableColors.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.5,
                    color: const Color(0xFF4ECDC4),
                    backgroundColor: readableColors.disabledSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$percent%',
                  style: TextStyle(
                    color: readableColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
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
