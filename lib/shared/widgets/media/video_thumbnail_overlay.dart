import 'package:flutter/material.dart';
import 'media_display_helpers.dart';

/// Dark overlay with play icon and optional duration pill for video thumbnails.
class VideoThumbnailOverlay extends StatelessWidget {
  final int? durationMs;

  const VideoThumbnailOverlay({super.key, this.durationMs});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dark scrim
        Positioned.fill(
          child: Container(color: const Color.fromRGBO(0, 0, 0, 0.30)),
        ),
        // Play icon
        const Center(
          child: Icon(
            Icons.play_arrow_rounded,
            size: 28,
            color: Color.fromRGBO(255, 255, 255, 0.90),
          ),
        ),
        // Duration pill
        if (durationMs != null)
          Positioned(
            bottom: 6,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(0, 0, 0, 0.40),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  formatDurationMs(durationMs),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color.fromRGBO(255, 255, 255, 0.80),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
