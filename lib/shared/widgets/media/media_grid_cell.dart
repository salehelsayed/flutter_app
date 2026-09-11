import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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

  /// 235: per-attachment long-press (exact item identity for received-media
  /// actions). Unlike [onTap] it is NOT gated on displayability — Info and
  /// Delete-for-me apply to pending/unavailable rows too; the caller's policy
  /// decides what to surface.
  final VoidCallback? onLongPress;
  final VoidCallback? onRetryUnavailableMedia;
  final bool requireVerifiedContentHash;
  final VideoThumbnailResolver? videoThumbnailResolver;
  final String? renderedSemanticsLabel;

  /// 128 (round 5): the conversation dir id (1:1 contact peerId, or groupId) the
  /// durable owned media copy is keyed under (`media/<id>/<blob>.<ext>`). When
  /// the displayed `localPath` is stale/transient (e.g. the deleted optimistic
  /// `pending_uploads` path), the render gate falls back to this canonical
  /// owned copy — so the cell renders from the durable file regardless of which
  /// (possibly un-updated) in-memory path it was handed.
  final String? ownedMediaPeerId;

  const MediaGridCell({
    super.key,
    required this.attachment,
    this.borderRadius = mediaGridItemRadius,
    this.showOverlayCount = false,
    this.overlayCount = 0,
    this.onTap,
    this.onLongPress,
    this.onRetryUnavailableMedia,
    this.requireVerifiedContentHash = false,
    this.videoThumbnailResolver,
    this.ownedMediaPeerId,
    this.renderedSemanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 231: stable per-tile handle for tap/long-press targeting in tests.
      key: ValueKey('media-grid-cell-${attachment.messageId}-${attachment.id}'),
      onTap: _canOpen ? onTap : null,
      onLongPress: onLongPress,
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

  /// 128: process-wide dedup so the build-time diagnostic fires at most once
  /// per attachment id (build() can run many times).
  static final Set<String> _diagnosedUnavailableIds = <String>{};

  @visibleForTesting
  static void debugResetUnavailableDiagnostics() =>
      _diagnosedUnavailableIds.clear();

  static String _localPathKind(String? path) {
    if (path == null || path.isEmpty) return 'empty';
    if (path.startsWith('media/') || path.startsWith('media\\')) {
      return 'relative-media';
    }
    if (path.contains('pending_uploads/') ||
        path.contains('pending_uploads\\')) {
      return 'pending-uploads-abs';
    }
    if (path.contains('/media/')) return 'owned-media-abs';
    return 'other';
  }

  void _emitUnavailableDiagnostic() {
    final id = attachment.id;
    if (!_diagnosedUnavailableIds.add(id)) return;
    final raw = attachment.localPath;
    final resolved = raw == null
        ? null
        : MediaFileManager.resolveStoredPathSync(raw);
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_RENDER_GATE_UNAVAILABLE',
      details: {
        'attachmentId': id.length > 8 ? id.substring(0, 8) : id,
        'rawLocalPathKind': _localPathKind(raw),
        'resolvedPathKind': _localPathKind(resolved),
        'existsAtResolved': resolved != null && File(resolved).existsSync(),
        'cacheSeeded': MediaFileManager.cachedDocumentsDir != null,
        'downloadStatus': attachment.downloadStatus,
      },
    );
  }

  /// The absolute path of an EXISTING file to render, or null if none exists.
  ///
  /// 127 (round 3): resolve the RELATIVE stored localPath to absolute (iOS
  /// stores relative; `File(relative)` fails against the process CWD).
  /// 128 (round 5): if that path doesn't exist (the in-memory display can hold
  /// a stale/transient path — e.g. the deleted optimistic `pending_uploads`
  /// path that is never swapped for the durable copy), fall back to the
  /// canonical owned copy `media/<ownedMediaPeerId>/<blobId>.<ext>`. Single
  /// render chokepoint, independent of any upstream path-update timing.
  String? get _resolvedExistingLocalPath => resolveExistingMediaPathForDisplay(
    attachment: attachment,
    ownedMediaPeerId: ownedMediaPeerId,
  );

  bool get _hasExistingLocalFile => _resolvedExistingLocalPath != null;

  bool get _isDisplayableDoneMedia {
    if (!_hasExistingLocalFile) {
      return false;
    }
    if (requireVerifiedContentHash) {
      return GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(attachment);
    }
    return attachment.downloadStatus == 'done';
  }

  bool get _canOpen => onTap != null && _isDisplayableDoneMedia;

  bool get _hasAllowedDescriptor => GroupMediaMimePolicy.isValidDescriptor(
    mime: attachment.mime,
    mediaType: attachment.mediaType,
  );

  bool get _hasAllowedSize =>
      // Render eligibility: permissive cross-type backstop so already-received
      // media is never newly hidden by the narrower per-type SEND caps.
      GroupMediaSizePolicy.validateAttachments([
        attachment,
      ], perMediaLimitBytes: kGroupMediaPerAttachmentLimitBytes).isValid;

  bool get _hasRequiredGroupMetadata =>
      !requireVerifiedContentHash ||
      (GroupMediaIntegrityPolicy.hasValidContentHash(attachment) &&
          attachment.hasEncryptionMetadata);

  bool get _showsUnavailableMedia =>
      GroupMediaIntegrityPolicy.isUnavailableMedia(
        attachment,
        requireVerifiedContentHash: requireVerifiedContentHash,
      ) ||
      // 117 Session 2: the group MIME allow-list + size policy are a
      // verified-group rendering gate, NOT a 1:1 concern. For 1:1
      // (requireVerifiedContentHash == false) availability is determined by
      // file presence + downloadStatus + isUnavailableMedia, so present,
      // done 1:1 media with a real-but-non-allowlisted mime (e.g. the video
      // re-encode-fallback containers) still renders and opens. This render
      // gate was never the 1:1 safety boundary: a 1:1 sender controls the mime
      // and could always forge an allow-listed value. 1:1 integrity is
      // enforced at download/promotion (content-hash + plaintext size + AEAD
      // auth-tag in decryptAndPromoteStagedDirectBlob), and rendering is
      // decode-only (Image.file / just_audio), never an OS file-handler — so
      // dropping this gate for 1:1 cannot render or execute a dangerous file.
      (requireVerifiedContentHash &&
          (!_hasAllowedDescriptor || !_hasAllowedSize)) ||
      !_hasRequiredGroupMetadata;

  bool get _canShowVideoOverlay =>
      attachment.mediaType == 'video' &&
      _isDisplayableDoneMedia &&
      !_showsUnavailableMedia;

  bool get _canRetryUnavailableMedia =>
      onRetryUnavailableMedia != null &&
      GroupMediaIntegrityPolicy.isRetryableDownloadFailure(attachment);

  /// 229: user-removed local copy — a truthful terminal-ish state, never an
  /// indefinite loader, with a user-authoritative explicit Retry (not gated
  /// by the bounded auto-retry budget).
  bool get _isEvicted =>
      attachment.downloadStatus == kMediaDownloadStatusEvicted;

  Widget _buildContent(BuildContext context) {
    final isImage = attachment.mediaType == 'image';
    final isVideo = attachment.mediaType == 'video';
    final isDone = attachment.downloadStatus == 'done';
    final hasPath = attachment.localPath != null;
    if (attachment.downloadStatus == kMediaDownloadStatusUploadPending) {
      return _buildUploadPendingPlaceholder(context);
    }

    if (_isEvicted) {
      return _buildEvictedPlaceholder(context);
    }

    if (_showsUnavailableMedia) {
      return _buildUnavailablePlaceholder(context);
    }

    if ((isImage || isVideo) && !isDone) {
      return _buildLoadingPlaceholder();
    }

    if ((isImage || isVideo) && isDone && hasPath) {
      if (!_isDisplayableDoneMedia) {
        // 128: a done image/video that still can't display — emit ONE diagnostic
        // per attachment so a device log reveals WHY (raw vs resolved path kind,
        // file existence, whether the sync resolver cache was seeded).
        _emitUnavailableDiagnostic();
        return _buildUnavailablePlaceholder(context);
      }
      return MediaThumbnailImage(
        mediaPath:
            _resolvedExistingLocalPath ??
            MediaFileManager.resolveStoredPathSync(attachment.localPath!),
        mediaType: attachment.mediaType,
        fit: BoxFit.cover,
        cacheWidth: 400,
        placeholder: isVideo
            ? Container(color: const Color.fromRGBO(0, 0, 0, 0.60))
            : _buildLoadingPlaceholder(),
        error: Builder(builder: _buildUnavailablePlaceholder),
        videoThumbnailResolver: videoThumbnailResolver,
        renderedSemanticsLabel: renderedSemanticsLabel,
      );
    }

    if (isVideo && !hasPath) {
      // Video without thumbnail: dark background
      return Container(color: const Color.fromRGBO(0, 0, 0, 0.60));
    }

    // Pending or downloading
    return _buildLoadingPlaceholder();
  }

  Widget _buildUploadPendingPlaceholder(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: const Color.fromRGBO(255, 255, 255, 0.04),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 20,
                color: Color.fromRGBO(255, 255, 255, 0.58),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.post_media_pending_upload,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color.fromRGBO(255, 255, 255, 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.post_media_pending_upload_desc,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color.fromRGBO(255, 255, 255, 0.58),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                // Tamper (integrity_failed) gets an honest "couldn't verify"
                // label, distinct from the generic unavailable/terminal copy.
                GroupMediaIntegrityPolicy.isQuarantinedGroupMedia(attachment)
                    ? l10n.media_could_not_verify
                    : l10n.media_unavailable,
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

  /// 229: "local copy removed" placeholder. The relay keeps blobs for a
  /// bounded time only, so the copy makes no cloud-style re-download
  /// promise — Retry attempts a transfer that settles truthfully (done or
  /// terminal unavailable).
  Widget _buildEvictedPlaceholder(BuildContext context) {
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
                Icons.file_download_off_outlined,
                size: 24,
                color: Color.fromRGBO(255, 255, 255, 0.34),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.media_local_copy_removed,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color.fromRGBO(255, 255, 255, 0.66),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onRetryUnavailableMedia != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  label: l10n.media_retry_unavailable,
                  button: true,
                  child: IconButton(
                    key: ValueKey(
                      'evicted-media-retry-${attachment.messageId}-${attachment.id}',
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
