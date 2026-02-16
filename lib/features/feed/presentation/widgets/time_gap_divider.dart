import 'package:flutter/material.dart';

/// Thin divider with a time label, shown between messages with a significant
/// time gap in the expanded thread view.
class TimeGapDivider extends StatelessWidget {
  final String timeLabel;

  const TimeGapDivider({super.key, required this.timeLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 0.5,
              color: const Color.fromRGBO(255, 255, 255, 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              timeLabel,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: Color.fromRGBO(255, 255, 255, 0.25),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 0.5,
              color: const Color.fromRGBO(255, 255, 255, 0.08),
            ),
          ),
        ],
      ),
    );
  }
}
