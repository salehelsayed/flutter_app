import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'media_display_helpers.dart';
import 'media_thumbnail_image.dart';
import 'video_thumbnail_overlay.dart';

/// A single cell in the media grid: image, video, placeholder, or "+N" overlay.
class MediaGridCell extends StatelessWidget {
  final MediaAttachment attachment;
  final double borderRadius;
  final bool showOverlayCount;
  final int overlayCount;
  final VoidCallback? onTap;
  final VoidCallback? onRetryUnavailableMedia;
  final bool requireVerifiedContentHash;

  const MediaGridCell({
    super.key,
    required this.attachment,
    this.borderRadius = mediaGridItemRadius,
    this.showOverlayCount = false,
    this.overlayCount = 0,
    this.onTap,
    this.onRetryUnavailableMedia,
    this.requireVerifiedContentHash = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _canOpen ? onTap : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildContent(context),
            if (_canShowVideoOverlay)
              VideoThumbnailOverlay(durationMs: attachment.durationMs),
            if (_showsGifBadge) _buildGifBadge(),
            if (showOverlayCount && overlayCount > 0) _buildOverlayCount(),
          ],
        ),
      ),
    );
  }

  bool get _showsGifBadge => attachment.isAnimated && _isDisplayableDoneMedia;

  bool get _isDisplayableDoneMedia {
    if (requireVerifiedContentHash) {
      return GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(attachment);
    }
    return attachment.downloadStatus == 'done' && attachment.localPath != null;
  }

  bool get _canOpen => onTap != null && _isDisplayableDoneMedia;

  bool get _hasAllowedDescriptor => GroupMediaMimePolicy.isValidDescriptor(
    mime: attachment.mime,
    mediaType: attachment.mediaType,
  );

  bool get _hasAllowedSize =>
      GroupMediaSizePolicy.validateAttachments([attachment]).isValid;

  bool get _hasRequiredGroupMetadata =>
      !requireVerifiedContentHash ||
      (GroupMediaIntegrityPolicy.hasValidContentHash(attachment) &&
          attachment.hasEncryptionMetadata);

  bool get _showsUnavailableMedia =>
      GroupMediaIntegrityPolicy.isUnavailableMedia(
        attachment,
        requireVerifiedContentHash: requireVerifiedContentHash,
      ) ||
      !_hasAllowedDescriptor ||
      !_hasAllowedSize ||
      !_hasRequiredGroupMetadata;

  bool get _canShowVideoOverlay =>
      attachment.mediaType == 'video' && !_showsUnavailableMedia;

  bool get _canRetryUnavailableMedia =>
      onRetryUnavailableMedia != null &&
      GroupMediaIntegrityPolicy.isRetryableDownloadFailure(attachment);

  Widget _buildContent(BuildContext context) {
    final isImage = attachment.mediaType == 'image';
    final isVideo = attachment.mediaType == 'video';
    final isDone = attachment.downloadStatus == 'done';
    final hasPath = attachment.localPath != null;
    if (_showsUnavailableMedia) {
      return _buildUnavailablePlaceholder(context);
    }

    if ((isImage || isVideo) && isDone && hasPath) {
      if (!_isDisplayableDoneMedia) {
        return _buildUnavailablePlaceholder(context);
      }
      return MediaThumbnailImage(
        mediaPath: attachment.localPath!,
        mediaType: attachment.mediaType,
        fit: BoxFit.cover,
        cacheWidth: 400,
        placeholder: isVideo
            ? Container(color: const Color.fromRGBO(0, 0, 0, 0.60))
            : _buildLoadingPlaceholder(),
        error: _buildUnavailablePlaceholder(context),
      );
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

  Widget _buildUnavailablePlaceholder(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: const Color.fromRGBO(255, 255, 255, 0.03),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                size: 24,
                color: Color.fromRGBO(255, 255, 255, 0.34),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.media_unavailable,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color.fromRGBO(255, 255, 255, 0.66),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_canRetryUnavailableMedia) ...[
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  label: l10n.media_retry_unavailable,
                  button: true,
                  child: IconButton(
                    key: ValueKey(
                      'unavailable-media-retry-${attachment.messageId}-${attachment.id}',
                    ),
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    color: const Color(0xFF4ecdc4),
                    onPressed: onRetryUnavailableMedia,
                    tooltip: l10n.media_retry_unavailable,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ],
            ],
          ),
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

  Widget _buildGifBadge() {
    return Positioned(
      left: 8,
      bottom: 8,
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
    );
  }
}
