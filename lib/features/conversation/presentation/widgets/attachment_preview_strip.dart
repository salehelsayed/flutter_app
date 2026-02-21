import 'dart:io';
import 'package:flutter/material.dart';

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
  final ValueChanged<int>? onRemove;

  const AttachmentPreviewStrip({
    super.key,
    required this.attachments,
    this.isUploading = false,
    this.isProcessing = false,
    this.processingProgress = 0.0,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final totalCount = attachments.length + (isProcessing ? 1 : 0);
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: totalCount,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (isProcessing && index == totalCount - 1) {
            return _ProcessingThumbnail(progress: processingProgress);
          }
          return _Thumbnail(
            file: attachments[index],
            isUploading: isUploading,
            onRemove: onRemove != null ? () => onRemove!(index) : null,
          );
        },
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final File file;
  final bool isUploading;
  final VoidCallback? onRemove;

  const _Thumbnail({
    required this.file,
    required this.isUploading,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Thumbnail image
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              file,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              cacheWidth: 200,
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
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white,
                  ),
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
  const _ProcessingThumbnail({required this.progress});

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();
    return SizedBox(
      width: 72,
      height: 72,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: const Color.fromRGBO(255, 255, 255, 0.08),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.5,
                    color: Colors.white70,
                    backgroundColor: const Color.fromRGBO(255, 255, 255, 0.15),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    color: Colors.white70,
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
