import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'media_display_helpers.dart';
import 'video_thumbnail_overlay.dart';

/// A single cell in the media grid: image, video, placeholder, or "+N" overlay.
class MediaGridCell extends StatelessWidget {
  final MediaAttachment attachment;
  final double borderRadius;
  final bool showOverlayCount;
  final int overlayCount;
  final VoidCallback? onTap;

  const MediaGridCell({
    super.key,
    required this.attachment,
    this.borderRadius = mediaGridItemRadius,
    this.showOverlayCount = false,
    this.overlayCount = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildContent(),
            if (attachment.mediaType == 'video')
              VideoThumbnailOverlay(durationMs: attachment.durationMs),
            if (showOverlayCount && overlayCount > 0) _buildOverlayCount(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final isImage = attachment.mediaType == 'image';
    final isVideo = attachment.mediaType == 'video';
    final isDone = attachment.downloadStatus == 'done';
    final hasPath = attachment.localPath != null;

    if ((isImage || isVideo) && isDone && hasPath) {
      return Image.file(
        File(attachment.localPath!),
        fit: BoxFit.cover,
        cacheWidth: 400,
        errorBuilder: (_, __, ___) => _buildFailedPlaceholder(),
      );
    }

    if (attachment.downloadStatus == 'failed') {
      return _buildFailedPlaceholder();
    }

    if (isVideo && !hasPath) {
      // Video without thumbnail: dark background
      return Container(color: const Color.fromRGBO(0, 0, 0, 0.60));
    }

    // Pending or downloading
    return _buildLoadingPlaceholder();
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      color: const Color.fromRGBO(255, 255, 255, 0.03),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF4ecdc4),
          ),
        ),
      ),
    );
  }

  Widget _buildFailedPlaceholder() {
    return Container(
      color: const Color.fromRGBO(255, 255, 255, 0.03),
      child: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 24,
          color: Color.fromRGBO(255, 255, 255, 0.25),
        ),
      ),
    );
  }

  Widget _buildOverlayCount() {
    return Container(
      color: const Color.fromRGBO(0, 0, 0, 0.60),
      child: Center(
        child: Text(
          '+$overlayCount',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
