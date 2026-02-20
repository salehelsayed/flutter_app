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
  final ValueChanged<int>? onRemove;

  const AttachmentPreviewStrip({
    super.key,
    required this.attachments,
    this.isUploading = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
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
