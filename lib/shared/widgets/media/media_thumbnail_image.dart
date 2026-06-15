import 'dart:io';

import 'package:flutter/material.dart';
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
        oldWidget.videoThumbnailResolver != widget.videoThumbnailResolver) {
      _configureThumbnailFuture();
    }
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
        if (File(widget.mediaPath).existsSync()) {
          return widget.placeholder ?? const SizedBox.shrink();
        }
        return widget.error ?? widget.placeholder ?? const SizedBox.shrink();
      },
    );
  }

  Widget _buildImage(String path) {
    final isGifImage =
        widget.mediaType == 'image' && path.toLowerCase().endsWith('.gif');
    return Image.file(
      File(path),
      fit: widget.fit,
      cacheWidth: isGifImage ? null : widget.cacheWidth,
      cacheHeight: isGifImage ? null : widget.cacheHeight,
      errorBuilder: (context, error, stackTrace) {
        // 117 Session 1: a video whose derived thumbnail JPG fails to decode
        // is NOT unavailable — the underlying video source is still present
        // and playable. Fall back to the benign placeholder (paralleling the
        // null-thumbnail + source-present branch in build()). Reserve `error`
        // for a genuinely corrupt/missing non-video image.
        if (widget.mediaType == 'video' &&
            File(widget.mediaPath).existsSync()) {
          return widget.placeholder ?? const SizedBox.shrink();
        }
        return widget.error ?? widget.placeholder ?? const SizedBox.shrink();
      },
    );
  }
}
