import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/media/amplitude_bars.dart';

class RecordingOverlay extends StatelessWidget {
  final Duration elapsed;
  final VoidCallback onCancel;
  final List<double> amplitudeValues;

  const RecordingOverlay({
    super.key,
    required this.elapsed,
    required this.onCancel,
    this.amplitudeValues = const [],
  });

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
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
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatDuration(elapsed),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 24,
              child: AmplitudeBars(values: amplitudeValues),
            ),
          ),
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
