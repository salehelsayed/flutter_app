import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// QR code display section with green glow effect.
class QRCodeSection extends StatelessWidget {
  final String? qrData;
  final double scaleFactor;

  const QRCodeSection({super.key, this.qrData, this.scaleFactor = 1.0});

  @override
  Widget build(BuildContext context) {
    // Calculate responsive QR size based on both width and height.
    final screenWidth = MediaQuery.of(context).size.width;
    final t = scaleFactor;
    final qrRatio = lerpDouble(0.48, 0.55, t)!;
    final minSize = lerpDouble(155, 170, t)!;
    final maxSize = lerpDouble(195, 240, t)!;
    final qrContainerSize = (screenWidth * qrRatio).clamp(minSize, maxSize);
    final qrImageSize = qrContainerSize - 24; // 12px padding on each side
    final textSize = lerpDouble(12.5, 14, t)!;
    final spacing = lerpDouble(8, 16, t)!;

    return Column(
      children: [
        // Description text
        Text(
          AppLocalizations.of(context)!.qr_show_desc,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: textSize,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: spacing),
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
        if (kDebugMode && qrData != null && t > 0.5)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              AppLocalizations.of(context)!.qr_copy_hint,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
      ],
    );
  }

  void _copyQRData(BuildContext context) {
    if (qrData == null) return;
    Clipboard.setData(ClipboardData(text: qrData!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.qr_copied),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildLoadingShimmer(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: const _PulsingShimmer(),
    );
  }
}

class _PulsingShimmer extends StatefulWidget {
  const _PulsingShimmer();

  @override
  State<_PulsingShimmer> createState() => _PulsingShimmerState();
}

class _PulsingShimmerState extends State<_PulsingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.3,
      end: 0.7,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        key: const ValueKey('qr-loading-shimmer'),
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
