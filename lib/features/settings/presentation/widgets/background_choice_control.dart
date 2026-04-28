import 'dart:ui';

import 'package:flutter/material.dart';
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
    final isDefaultSelected = value == BackgroundPreference.defaultBackground;
    final selectedLabel = isDefaultSelected
        ? l10n.settings_background_default_selected
        : l10n.settings_background_cosmic_selected;

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
                color: const Color.fromRGBO(255, 255, 255, 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color.fromRGBO(255, 255, 255, 0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.wallpaper,
                        size: 16,
                        color: Color.fromRGBO(255, 255, 255, 0.5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.settings_background,
                        key: const ValueKey('background-choice-title'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color.fromRGBO(255, 255, 255, 0.5),
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
                ? const Color.fromRGBO(255, 255, 255, 0.12)
                : const Color.fromRGBO(0, 0, 0, 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color.fromRGBO(255, 255, 255, 0.2)
                  : Colors.transparent,
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
                            ? const Color.fromRGBO(255, 255, 255, 0.95)
                            : const Color.fromRGBO(255, 255, 255, 0.55),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color.fromRGBO(255, 255, 255, 0.4),
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
