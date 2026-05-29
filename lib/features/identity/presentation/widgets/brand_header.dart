import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Brand header section with glowing icon, title, and tagline.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

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
              border: Border.all(color: AppColors.primaryAccent, width: 2),
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
        Text(
          'mknoon',
          style: TextStyle(
            color: readableColors.textPrimary,
            fontSize: 36,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        // Tagline
        Text(
          l10n.identity_tagline,
          style: TextStyle(color: readableColors.textSecondary, fontSize: 16),
        ),
      ],
    );
  }
}
