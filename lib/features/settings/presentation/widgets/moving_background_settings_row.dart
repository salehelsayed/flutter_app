import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_group.dart';

/// The background-motion preference, isolated from other settings rows.
class MovingBackgroundSettingsRow extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool>? onChanged;
  final String? errorText;

  const MovingBackgroundSettingsRow({
    super.key,
    required this.enabled,
    this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsListRow(
          key: const ValueKey('settings-row-moving-background'),
          icon: Icons.animation,
          label: l10n.settings_moving_background,
          subtitle: l10n.settings_moving_background_desc,
          trailing: Switch.adaptive(
            key: const ValueKey('settings-moving-background-switch'),
            value: enabled,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Semantics(
              liveRegion: true,
              child: Text(
                errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    );
  }
}
