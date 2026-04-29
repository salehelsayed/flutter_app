import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

/// Toggle widget for media quality preference.
///
/// Displays two options: "Compressed" and "Original" in a segmented
/// glass-style container matching the settings screen design.
///
/// Use [label] and [icon] to customize for photo vs video quality.
class ImageQualityToggle extends StatelessWidget {
  final ImageQualityPreference value;
  final ValueChanged<ImageQualityPreference> onChanged;
  final String label;
  final IconData icon;

  const ImageQualityToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.icon = Icons.photo_size_select_large,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: readableColors.glassSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: readableColors.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: readableColors.iconMuted),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: readableColors.textMuted,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: readableColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      _buildOption(
                        label: l10n.settings_compressed,
                        isSelected: value == ImageQualityPreference.compressed,
                        readableColors: readableColors,
                        onTap: () =>
                            onChanged(ImageQualityPreference.compressed),
                      ),
                      _buildOption(
                        label: l10n.settings_original,
                        isSelected: value == ImageQualityPreference.original,
                        readableColors: readableColors,
                        onTap: () => onChanged(ImageQualityPreference.original),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value == ImageQualityPreference.original
                      ? l10n.settings_original_desc
                      : l10n.settings_compressed_desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: readableColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOption({
    required String label,
    required bool isSelected,
    required BackgroundReadableColors readableColors,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? readableColors.surfaceRaised
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? readableColors.textPrimary
                  : readableColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
