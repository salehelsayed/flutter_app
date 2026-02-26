import 'dart:math';
import 'package:flutter/material.dart';

/// A waveform-based seek bar for audio playback.
///
/// Draws vertical bars representing amplitude data, split into played
/// (teal) and unplayed (dim white) portions based on [progress].
/// Supports tap-to-seek via [onSeek].
class WaveformSeekBar extends StatelessWidget {
  /// Normalized amplitude values in [0.0, 1.0]. Null or empty renders flat bars.
  final List<double>? waveform;

  /// Current playback progress in [0.0, 1.0].
  final double progress;

  /// Called with a [0.0, 1.0] value when the user taps to seek.
  final ValueChanged<double>? onSeek;

  static const int _barCount = 50;

  const WaveformSeekBar({
    super.key,
    required this.waveform,
    required this.progress,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: onSeek != null
          ? (details) {
              final box = context.findRenderObject() as RenderBox;
              final localX = details.localPosition.dx;
              final fraction = (localX / box.size.width).clamp(0.0, 1.0);
              onSeek!(fraction);
            }
          : null,
      child: CustomPaint(
        size: const Size(double.infinity, 28),
        painter: _WaveformSeekBarPainter(
          waveform: waveform,
          progress: progress.clamp(0.0, 1.0),
        ),
      ),
    );
  }
}

class _WaveformSeekBarPainter extends CustomPainter {
  final List<double>? waveform;
  final double progress;

  static const _barWidth = 2.0;
  static const _barGap = 2.0;
  static const _minBarHeight = 2.0;

  static const _playedColor = Color.fromRGBO(78, 205, 196, 0.70);
  static const _unplayedColor = Color.fromRGBO(255, 255, 255, 0.15);

  _WaveformSeekBarPainter({required this.waveform, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = WaveformSeekBar._barCount;
    final totalBarWidth = _barWidth + _barGap;
    final maxBars = (size.width / totalBarWidth).floor();
    final bars = min(barCount, maxBars);
    if (bars <= 0) return;

    final samples = _resolveSamples(bars);
    final maxHeight = size.height;
    final centerY = size.height / 2;

    final playedPaint = Paint()..color = _playedColor;
    final unplayedPaint = Paint()..color = _unplayedColor;

    // Center bars horizontally
    final totalWidth = bars * totalBarWidth - _barGap;
    final startX = (size.width - totalWidth) / 2;

    for (var i = 0; i < bars; i++) {
      final barFraction = (i + 0.5) / bars;
      final paint = barFraction <= progress ? playedPaint : unplayedPaint;

      final amplitude = samples[i].clamp(0.0, 1.0);
      final barHeight = max(_minBarHeight, amplitude * maxHeight);
      final x = startX + i * totalBarWidth;
      final top = centerY - barHeight / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, _barWidth, barHeight),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  List<double> _resolveSamples(int count) {
    final data = waveform;
    if (data == null || data.isEmpty) {
      return List.filled(count, 0.05); // minimal flat bars
    }
    if (data.length == count) return data;
    if (data.length < count) {
      // Stretch: repeat nearest sample
      return List.generate(count, (i) {
        final srcIndex = (i * data.length / count).floor().clamp(0, data.length - 1);
        return data[srcIndex];
      });
    }
    // Downsample: average buckets
    return List.generate(count, (i) {
      final start = (i * data.length / count).floor();
      final end = ((i + 1) * data.length / count).floor();
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        sum += data[j];
      }
      return (end > start) ? sum / (end - start) : 0.0;
    });
  }

  @override
  bool shouldRepaint(_WaveformSeekBarPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.waveform != waveform;
  }
}
