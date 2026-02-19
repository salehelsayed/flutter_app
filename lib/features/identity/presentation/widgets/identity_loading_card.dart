import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

/// A branded loading overlay for identity generation/restore.
///
/// Shows stage-based text with smooth transitions:
/// - `'generating_keys'` → "Creating identity & encryption keys..."
/// - `'saving'` → "Saving securely..."
///
/// Uses a simple opaque overlay instead of BackdropFilter to avoid
/// expensive per-frame blur recomputation against the animated background.
class IdentityLoadingCard extends StatelessWidget {
  final String stage;

  const IdentityLoadingCard({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _stageText(stage);

    return Material(
      color: AppColors.background.withValues(alpha: 0.92),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          decoration: BoxDecoration(
            color: AppColors.glassBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.glassBorder,
              width: 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  color: AppColors.primaryAccent,
                  strokeWidth: 3.0,
                ),
              ),
              const SizedBox(height: 32),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  title,
                  key: ValueKey(title),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, String) _stageText(String stage) {
    switch (stage) {
      case 'saving':
        return ('Saving securely...', 'Almost there');
      case 'generating_keys':
      default:
        return ('Creating identity & encryption keys...', 'This only happens once');
    }
  }
}
