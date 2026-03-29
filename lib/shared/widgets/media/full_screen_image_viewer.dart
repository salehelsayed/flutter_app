import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/video_thumbnail_cache.dart';
import 'package:video_player/video_player.dart';

typedef FullScreenVideoPageBuilder =
    Widget Function(String path, bool isActive);

/// Full-screen media viewer with pinch-to-zoom for images and inline playback
/// for videos.
///
/// When [allPaths] is provided, displays a PageView that lets the user
/// swipe between media items starting at [initialIndex]. A page indicator
/// is shown when there are multiple images.
///
/// Falls back to single-item mode when only [localPath] is given.
class FullScreenImageViewer extends StatefulWidget {
  final String localPath;
  final List<String> allPaths;
  final int initialIndex;
  final FullScreenVideoPageBuilder? videoPageBuilder;

  const FullScreenImageViewer({
    super.key,
    required this.localPath,
    this.allPaths = const [],
    this.initialIndex = 0,
    this.videoPageBuilder,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late final PageController _pageController;
  late int _currentPage;
  late final List<String> _paths;

  @override
  void initState() {
    super.initState();
    _paths = widget.allPaths.isNotEmpty ? widget.allPaths : [widget.localPath];
    _currentPage = widget.initialIndex.clamp(0, _paths.length - 1);
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showIndicator = _paths.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: showIndicator
            ? Text(
                '${_currentPage + 1} / ${_paths.length}',
                style: const TextStyle(
                  color: Color.fromRGBO(255, 255, 255, 0.7),
                  fontSize: 14,
                ),
              )
            : null,
        centerTitle: true,
      ),
      extendBodyBehindAppBar: true,
      body: PageView.builder(
        controller: _pageController,
        itemCount: _paths.length,
        onPageChanged: (index) => setState(() => _currentPage = index),
        itemBuilder: (context, index) {
          final path = _paths[index];
          if (isLikelyVideoPath(path)) {
            final videoPageBuilder = widget.videoPageBuilder;
            if (videoPageBuilder != null) {
              return videoPageBuilder(path, index == _currentPage);
            }
            return _FullScreenVideoPage(
              key: ValueKey(path),
              path: path,
              isActive: index == _currentPage,
            );
          }

          return InteractiveViewer(
            child: Center(
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: Color.fromRGBO(255, 255, 255, 0.25),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FullScreenVideoPage extends StatefulWidget {
  final String path;
  final bool isActive;

  const _FullScreenVideoPage({
    super.key,
    required this.path,
    required this.isActive,
  });

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  Object? _initializationError;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(_FullScreenVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _disposeController();
      _createController();
      return;
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (widget.isActive) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _createController() {
    _initializationError = null;
    final controller = VideoPlayerController.file(File(widget.path));
    _controller = controller;
    _initializeFuture = controller
        .initialize()
        .then((_) async {
          await controller.setLooping(false);
          if (!mounted || controller != _controller) {
            return;
          }
          if (widget.isActive) {
            await controller.play();
          }
          setState(() {});
        })
        .catchError((Object error) {
          if (!mounted || controller != _controller) {
            return;
          }
          _initializationError = error;
          setState(() {});
        });
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    _initializeFuture = null;
    if (controller != null) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initializeFuture = _initializeFuture;
    if (controller == null || initializeFuture == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<void>(
      future: initializeFuture,
      builder: (context, snapshot) {
        if (_initializationError != null) {
          return _buildErrorState();
        }
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white70,
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () {
            if (controller.value.isPlaying) {
              controller.pause();
            } else if (widget.isActive) {
              controller.play();
            }
            setState(() {});
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: controller.value.isPlaying ? 0.0 : 1.0,
                child: IgnorePointer(
                  ignoring: controller.value.isPlaying,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(0, 0, 0, 0.45),
                      borderRadius: BorderRadius.circular(36),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Color.fromRGBO(255, 255, 255, 0.35),
                    backgroundColor: Color.fromRGBO(255, 255, 255, 0.12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 42,
            color: Color.fromRGBO(255, 255, 255, 0.55),
          ),
          SizedBox(height: 12),
          Text(
            'Could not load video',
            style: TextStyle(
              color: Color.fromRGBO(255, 255, 255, 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
