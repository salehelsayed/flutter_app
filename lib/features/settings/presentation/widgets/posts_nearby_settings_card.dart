import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class PostsNearbySettingsCard extends StatelessWidget {
  final bool sharingEnabled;
  final ValueChanged<bool> onChanged;

  const PostsNearbySettingsCard({
    super.key,
    required this.sharingEnabled,
    required this.onChanged,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.settings_share_nearby,
                        style: TextStyle(
                          color: readableColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sharingEnabled
                            ? l10n.settings_share_nearby_on
                            : l10n.settings_share_nearby_off,
                        style: TextStyle(
                          color: readableColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.settings_share_nearby_desc,
                        style: TextStyle(
                          color: readableColors.textMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch.adaptive(value: sharingEnabled, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
