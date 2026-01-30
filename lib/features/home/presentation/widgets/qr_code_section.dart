import 'package:flutter/material.dart';
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
        Container(
          width: 220,
          height: 220,
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
                    size: 196,
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
                : _buildLoadingShimmer(),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingShimmer() {
    return SizedBox(
      width: 196,
      height: 196,
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
