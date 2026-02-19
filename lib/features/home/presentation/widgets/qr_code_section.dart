import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// QR code display section with green glow effect.
class QRCodeSection extends StatelessWidget {
  final String? qrData;

  const QRCodeSection({
    super.key,
    this.qrData,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate responsive QR size based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    // QR container is ~55% of screen width, clamped between 180 and 240
    final qrContainerSize = (screenWidth * 0.55).clamp(180.0, 240.0);
    final qrImageSize = qrContainerSize - 24; // 12px padding on each side

    return Column(
      children: [
        // Description text
        const Text(
          'Show this to someone you want in your circle...',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        // QR code container with glow
        GestureDetector(
          onLongPress: qrData != null && kDebugMode
              ? () => _copyQRData(context)
              : null,
          child: Container(
            width: qrContainerSize,
            height: qrContainerSize,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.greenGlow.withValues(alpha: 0.3),
                  blurRadius: 40,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Center(
              child: qrData != null
                  ? QrImageView(
                      data: qrData!,
                      version: QrVersions.auto,
                      size: qrImageSize,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    )
                  : _buildLoadingShimmer(qrImageSize),
            ),
          ),
        ),
        // Debug hint
        if (kDebugMode && qrData != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Long-press QR to copy data',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
      ],
    );
  }

  void _copyQRData(BuildContext context) {
    if (qrData == null) return;
    Clipboard.setData(ClipboardData(text: qrData!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR data copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildLoadingShimmer(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.3, end: 0.7),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        builder: (context, value, child) {
          return Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: value),
              borderRadius: BorderRadius.circular(12),
            ),
          );
        },
        onEnd: () {},
      ),
    );
  }
}
