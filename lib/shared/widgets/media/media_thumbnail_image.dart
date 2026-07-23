import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/video_thumbnail_cache.dart';

typedef VideoThumbnailResolver = Future<String?> Function(String mediaPath);

class MediaThumbnailImage extends StatefulWidget {
  final String mediaPath;
  final String mediaType;
  final String? thumbnailPath;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final Widget? placeholder;
  final Widget? error;
  final VideoThumbnailResolver? videoThumbnailResolver;

  /// Optional device-proof label exposed only after this renderer has a real
  /// decoded frame (image or derived video thumbnail).
  /// Ordinary callers leave this null, so production accessibility output is
  /// unchanged outside the explicitly wired proof route.
  final String? renderedSemanticsLabel;

  const MediaThumbnailImage({
    super.key,
    required this.mediaPath,
    required this.mediaType,
    this.thumbnailPath,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
    this.placeholder,
    this.error,
    this.videoThumbnailResolver,
    this.renderedSemanticsLabel,
  });

  @override
  State<MediaThumbnailImage> createState() => _MediaThumbnailImageState();
}

class _MediaThumbnailImageState extends State<MediaThumbnailImage> {
  Future<String?>? _videoThumbnailFuture;

  @override
  void initState() {
    super.initState();
    _configureThumbnailFuture();
  }

  @override
  void didUpdateWidget(MediaThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaPath != widget.mediaPath ||
        oldWidget.mediaType != widget.mediaType ||
        oldWidget.thumbnailPath != widget.thumbnailPath ||
        oldWidget.videoThumbnailResolver != widget.videoThumbnailResolver ||
        oldWidget.renderedSemanticsLabel != widget.renderedSemanticsLabel) {
      _configureThumbnailFuture();
    }
  }

  Widget _withRenderedSemantics(Widget child) {
    final label = widget.renderedSemanticsLabel;
    if (label == null) return child;
    return Semantics(container: true, label: label, child: child);
  }

  void _configureThumbnailFuture() {
    if (widget.mediaType != 'video') {
      _videoThumbnailFuture = null;
      return;
    }
    final explicitThumbnailPath = widget.thumbnailPath;
    if (explicitThumbnailPath != null && explicitThumbnailPath.isNotEmpty) {
      _videoThumbnailFuture = Future<String?>.value(explicitThumbnailPath);
      return;
    }
    final resolver =
        widget.videoThumbnailResolver ?? VideoThumbnailCache.resolve;
    _videoThumbnailFuture = resolver(widget.mediaPath);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaType != 'video') {
      return _buildImage(widget.mediaPath);
    }

    final thumbnailFuture = _videoThumbnailFuture;
    if (thumbnailFuture == null) {
      return widget.placeholder ?? const SizedBox.shrink();
    }

    return FutureBuilder<String?>(
      future: thumbnailFuture,
      builder: (context, snapshot) {
        final thumbnailPath = snapshot.data;
        if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
          return _buildImage(thumbnailPath);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.placeholder ?? const SizedBox.shrink();
        }
        if (File(_resolvedMediaPath).existsSync()) {
          // A present source keeps the normal benign video fallback, but the
          // device-proof label is intentionally absent until an actual
          // thumbnail frame decodes. File existence alone is not render proof.
          return widget.placeholder ?? const SizedBox.shrink();
        }
        return widget.error ?? widget.placeholder ?? const SizedBox.shrink();
      },
    );
  }

  /// 127 (round 3): resolve a RELATIVE stored path to an absolute one at the
  /// render boundary (the DB stores relative; iOS needs the Documents dir).
  String get _resolvedMediaPath =>
      MediaFileManager.resolveStoredPathSync(widget.mediaPath);

  Widget _buildImage(String path) {
    final resolvedPath = MediaFileManager.resolveStoredPathSync(path);
    final isGifImage =
        widget.mediaType == 'image' &&
        resolvedPath.toLowerCase().endsWith('.gif');
    return Image.file(
      File(resolvedPath),
      fit: widget.fit,
      cacheWidth: isGifImage ? null : widget.cacheWidth,
      cacheHeight: isGifImage ? null : widget.cacheHeight,
      // 143: while the full-resolution photo is being read + decoded + resized
      // (cacheWidth:400), Flutter paints transparent inside the size-reserved
      // box — which reads as an empty/failed send. Show the supplied sized
      // placeholder during decode instead of an empty box; the decoded child
      // appears the moment a frame is available (or if it loaded synchronously,
      // e.g. an already-cached image — no placeholder flash).
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return _withRenderedSemantics(child);
        }
        return widget.placeholder ?? const SizedBox.shrink();
      },
      errorBuilder: (context, error, stackTrace) {
        // 117 Session 1: a video whose derived thumbnail JPG fails to decode
        // is NOT unavailable — the underlying video source is still present
        // and playable. Fall back to the benign placeholder (paralleling the
        // null-thumbnail + source-present branch in build()). Reserve `error`
        // for a genuinely corrupt/missing non-video image.
        if (widget.mediaType == 'video' &&
            File(_resolvedMediaPath).existsSync()) {
          return widget.placeholder ?? const SizedBox.shrink();
        }
        return widget.error ?? widget.placeholder ?? const SizedBox.shrink();
      },
    );
  }
}
