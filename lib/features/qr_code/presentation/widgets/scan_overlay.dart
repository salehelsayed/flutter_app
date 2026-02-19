import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

/// Overlay widget for QR scanner with cutout and corner markers.
class ScanOverlay extends StatelessWidget {
  /// Size of the scan area (square).
  final double scanAreaSize;

  const ScanOverlay({
    super.key,
    this.scanAreaSize = 280,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanOverlayPainter(scanAreaSize: scanAreaSize),
      child: SizedBox.expand(),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  final double scanAreaSize;

  _ScanOverlayPainter({required this.scanAreaSize});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scanRect = Rect.fromCenter(
      center: center,
      width: scanAreaSize,
      height: scanAreaSize,
    );

    // Draw semi-transparent overlay with cutout
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    canvas.drawPath(overlayPath, overlayPaint);

    // Draw corner markers
    final cornerPaint = Paint()
      ..color = AppColors.primaryAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const cornerRadius = 16.0;

    // Top-left corner
    _drawCorner(
      canvas,
      cornerPaint,
      scanRect.topLeft + const Offset(0, cornerRadius),
      cornerLength,
      isTop: true,
      isLeft: true,
    );

    // Top-right corner
    _drawCorner(
      canvas,
      cornerPaint,
      scanRect.topRight + const Offset(0, cornerRadius),
      cornerLength,
      isTop: true,
      isLeft: false,
    );

    // Bottom-left corner
    _drawCorner(
      canvas,
      cornerPaint,
      scanRect.bottomLeft - const Offset(0, cornerRadius),
      cornerLength,
      isTop: false,
      isLeft: true,
    );

    // Bottom-right corner
    _drawCorner(
      canvas,
      cornerPaint,
      scanRect.bottomRight - const Offset(0, cornerRadius),
      cornerLength,
      isTop: false,
      isLeft: false,
    );

    // Draw subtle border around scan area
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRRect(
      RRect.fromRectAndRadius(scanRect, const Radius.circular(16)),
      borderPaint,
    );
  }

  void _drawCorner(
    Canvas canvas,
    Paint paint,
    Offset start,
    double length, {
    required bool isTop,
    required bool isLeft,
  }) {
    final horizontalDir = isLeft ? 1.0 : -1.0;
    final verticalDir = isTop ? 1.0 : -1.0;

    // Vertical line
    canvas.drawLine(
      start,
      start + Offset(0, length * verticalDir),
      paint,
    );

    // Horizontal line
    canvas.drawLine(
      start,
      start + Offset(length * horizontalDir, 0),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
