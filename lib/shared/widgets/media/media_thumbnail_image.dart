import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/video_thumbnail_cache.dart';

class MediaThumbnailImage extends StatefulWidget {
  final String mediaPath;
  final String mediaType;
  final String? thumbnailPath;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final Widget? placeholder;
  final Widget? error;

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
        oldWidget.thumbnailPath != widget.thumbnailPath) {
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
    _videoThumbnailFuture = VideoThumbnailCache.resolve(widget.mediaPath);
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
        return widget.error ?? widget.placeholder ?? const SizedBox.shrink();
      },
    );
  }

  Widget _buildImage(String path) {
    return Image.file(
      File(path),
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      errorBuilder: (context, error, stackTrace) =>
          widget.error ?? widget.placeholder ?? const SizedBox.shrink(),
    );
  }
}
