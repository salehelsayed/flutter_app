import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/diagnostics/app_diagnostics.dart';
import 'call_diagnostics_settings_section.dart';

class AppDiagnosticsSettingsSection extends StatelessWidget {
  const AppDiagnosticsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CallDiagnosticsSettingsSection(
      enabled: AppDiagnostics.instance.enabledListenable,
      setEnabled: AppDiagnostics.instance.setEnabled,
      exportPreview: AppDiagnostics.instance.exportPreview,
      clear: AppDiagnostics.instance.clear,
      status: AppDiagnostics.instance.status,
      title: l10n.settings_app_diagnostics_title,
      switchLabel: l10n.settings_app_diagnostics_switch,
      summary: l10n.settings_app_diagnostics_summary,
      details: l10n.settings_app_diagnostics_details,
      supportCodes: true,
    );
  }
}
