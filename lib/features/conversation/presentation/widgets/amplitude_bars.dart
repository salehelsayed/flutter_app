import 'package:flutter/material.dart';

/// Displays a row of vertical bars representing audio amplitude.
///
/// Each bar height is proportional to its value (0.0–1.0).
/// Used inside the recording overlay for real-time mic feedback.
class AmplitudeBars extends StatelessWidget {
  final List<double> values;

  const AmplitudeBars({super.key, required this.values});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: AmplitudeBarsPainter(values: values),
    );
  }
}

class AmplitudeBarsPainter extends CustomPainter {
  final List<double> values;

  const AmplitudeBarsPainter({required this.values});

  static const _barWidth = 2.0;
  static const _barGap = 2.0;
  static const _minBarHeight = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, 0.5)
      ..strokeCap = StrokeCap.round;

    final totalBarWidth = _barWidth + _barGap;
    final count = values.length;
    final totalWidth = count * totalBarWidth - _barGap;
    final startX = (size.width - totalWidth) / 2;
    final centerY = size.height / 2;
    final maxBarHeight = size.height;

    for (var i = 0; i < count; i++) {
      final value = values[i].clamp(0.0, 1.0);
      final barHeight =
          (_minBarHeight + value * (maxBarHeight - _minBarHeight));
      final x = startX + i * totalBarWidth + _barWidth / 2;
      final top = centerY - barHeight / 2;
      final bottom = centerY + barHeight / 2;

      canvas.drawLine(
        Offset(x, top),
        Offset(x, bottom),
        paint..strokeWidth = _barWidth,
      );
    }
  }

  @override
  bool shouldRepaint(AmplitudeBarsPainter oldDelegate) {
    return !identical(values, oldDelegate.values);
  }
}
