import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'settings_group.dart';

/// Sits beside App diagnostics. A plain switch: off is as easy as on.
class ThoughtsMetricsSettingsSection extends StatelessWidget {
  const ThoughtsMetricsSettingsSection({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroupCard(
          label: l10n.settings_diagnostics_section,
          children: <Widget>[
            SettingsListRow(
              key: const ValueKey('settings-row-thoughts-metrics'),
              icon: Icons.insights_outlined,
              label: l10n.settings_thoughts_metrics_title,
              trailing: Switch.adaptive(
                key: const ValueKey('settings-thoughts-metrics-switch'),
                value: enabled,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        // Below the card, not a row subtitle: rows clip at two lines and
        // every part of this promise must stay readable.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
          child: Text(
            l10n.settings_thoughts_metrics_desc,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: context.backgroundReadableColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
