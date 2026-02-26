import 'package:flutter/material.dart';

/// Overlay shown above the compose area during active recording.
///
/// Displays a red recording indicator, elapsed time, and "Slide to cancel" hint.
class RecordingOverlay extends StatelessWidget {
  final Duration elapsed;
  final VoidCallback onCancel;

  const RecordingOverlay({
    super.key,
    required this.elapsed,
    required this.onCancel,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color.fromRGBO(30, 30, 35, 0.95),
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
      child: Row(
        children: [
          // Red recording dot
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          // Elapsed time
          Text(
            _formatDuration(elapsed),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          // Slide to cancel hint
          GestureDetector(
            onTap: onCancel,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.chevron_left,
                  size: 16,
                  color: Color.fromRGBO(255, 255, 255, 0.4),
                ),
                SizedBox(width: 2),
                Text(
                  'Slide to cancel',
                  style: TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.4),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
