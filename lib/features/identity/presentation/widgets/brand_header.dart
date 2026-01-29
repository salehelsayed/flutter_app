import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

/// Brand header section with glowing icon, title, and tagline.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon with glow effect
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.greenGlow.withValues(alpha: 0.4),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.background,
              border: Border.all(
                color: AppColors.primaryAccent,
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.fingerprint,
              size: 40,
              color: AppColors.primaryAccent,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Brand name
        const Text(
          'mknoon',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 36,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        // Tagline
        const Text(
          'Your identity, your control',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
