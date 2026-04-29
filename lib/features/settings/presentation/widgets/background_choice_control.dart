import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Settings card for choosing the shared app background.
class BackgroundChoiceControl extends StatelessWidget {
  final BackgroundPreference value;
  final ValueChanged<BackgroundPreference> onChanged;
  final String? errorText;

  const BackgroundChoiceControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;
    final isDefaultSelected = value == BackgroundPreference.defaultBackground;
    final selectedLabel = switch (value) {
      BackgroundPreference.defaultBackground =>
        l10n.settings_background_default_selected,
      BackgroundPreference.cosmic => l10n.settings_background_cosmic_selected,
      BackgroundPreference.cosmicMirrored =>
        l10n.settings_background_cosmic_mirrored_selected,
      BackgroundPreference.daylightLagoon =>
        l10n.settings_background_daylight_lagoon_selected,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Semantics(
            key: const ValueKey('background-choice-control-semantics'),
            container: true,
            label: l10n.settings_background_semantics,
            value: selectedLabel,
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
                      Icon(
                        Icons.wallpaper,
                        size: 16,
                        color: readableColors.iconMuted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.settings_background,
                        key: const ValueKey('background-choice-title'),
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
                  _BackgroundOption(
                    optionKey: const ValueKey('background-choice-default'),
                    semanticsKey: const ValueKey(
                      'background-choice-default-semantics',
                    ),
                    selectedIconKey: const ValueKey(
                      'background-choice-default-selected-icon',
                    ),
                    label: l10n.settings_background_default,
                    description: l10n.settings_background_default_desc,
                    selectedLabel: l10n.settings_background_default_selected,
                    isSelected: isDefaultSelected,
                    onTap: () =>
                        onChanged(BackgroundPreference.defaultBackground),
                  ),
                  const SizedBox(height: 10),
                  _BackgroundOption(
                    optionKey: const ValueKey('background-choice-cosmic'),
                    semanticsKey: const ValueKey(
                      'background-choice-cosmic-semantics',
                    ),
                    selectedIconKey: const ValueKey(
                      'background-choice-cosmic-selected-icon',
                    ),
                    label: l10n.settings_background_cosmic,
                    description: l10n.settings_background_cosmic_desc,
                    selectedLabel: l10n.settings_background_cosmic_selected,
                    isSelected: value == BackgroundPreference.cosmic,
                    onTap: () => onChanged(BackgroundPreference.cosmic),
                  ),
                  const SizedBox(height: 10),
                  _BackgroundOption(
                    optionKey: const ValueKey(
                      'background-choice-cosmic-mirrored',
                    ),
                    semanticsKey: const ValueKey(
                      'background-choice-cosmic-mirrored-semantics',
                    ),
                    selectedIconKey: const ValueKey(
                      'background-choice-cosmic-mirrored-selected-icon',
                    ),
                    label: l10n.settings_background_cosmic_mirrored,
                    description: l10n.settings_background_cosmic_mirrored_desc,
                    selectedLabel:
                        l10n.settings_background_cosmic_mirrored_selected,
                    isSelected: value == BackgroundPreference.cosmicMirrored,
                    onTap: () => onChanged(BackgroundPreference.cosmicMirrored),
                  ),
                  const SizedBox(height: 10),
                  _BackgroundOption(
                    optionKey: const ValueKey(
                      'background-choice-daylight-lagoon',
                    ),
                    semanticsKey: const ValueKey(
                      'background-choice-daylight-lagoon-semantics',
                    ),
                    selectedIconKey: const ValueKey(
                      'background-choice-daylight-lagoon-selected-icon',
                    ),
                    label: l10n.settings_background_daylight_lagoon,
                    description: l10n.settings_background_daylight_lagoon_desc,
                    selectedLabel:
                        l10n.settings_background_daylight_lagoon_selected,
                    isSelected: value == BackgroundPreference.daylightLagoon,
                    onTap: () => onChanged(BackgroundPreference.daylightLagoon),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      key: const ValueKey('background-choice-error'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color.fromRGBO(255, 107, 107, 0.95),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundOption extends StatelessWidget {
  final Key optionKey;
  final Key semanticsKey;
  final Key selectedIconKey;
  final String label;
  final String description;
  final String selectedLabel;
  final bool isSelected;
  final VoidCallback onTap;

  const _BackgroundOption({
    required this.optionKey,
    required this.semanticsKey,
    required this.selectedIconKey,
    required this.label,
    required this.description,
    required this.selectedLabel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Semantics(
      key: semanticsKey,
      button: true,
      selected: isSelected,
      label: label,
      value: isSelected ? selectedLabel : null,
      child: GestureDetector(
        key: optionKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? readableColors.surfaceRaised
                : readableColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? readableColors.border : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? readableColors.textPrimary
                            : readableColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 11,
                        color: readableColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  key: selectedIconKey,
                  size: 18,
                  color: const Color.fromRGBO(29, 185, 84, 0.95),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
