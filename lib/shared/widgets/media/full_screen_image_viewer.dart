import 'dart:io';
import 'package:flutter/material.dart';

/// Full-screen image viewer with pinch-to-zoom and horizontal swiping
/// between multiple images.
///
/// When [allPaths] is provided, displays a PageView that lets the user
/// swipe between images starting at [initialIndex]. A page indicator
/// is shown when there are multiple images.
///
/// Falls back to single-image mode when only [localPath] is given.
class FullScreenImageViewer extends StatefulWidget {
  final String localPath;
  final List<String> allPaths;
  final int initialIndex;

  const FullScreenImageViewer({
    super.key,
    required this.localPath,
    this.allPaths = const [],
    this.initialIndex = 0,
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
          return InteractiveViewer(
            child: Center(
              child: Image.file(
                File(_paths[index]),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
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
