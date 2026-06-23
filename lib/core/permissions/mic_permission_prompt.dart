import 'package:flutter/material.dart';

import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Shared microphone-permission rationale dialog used by BOTH the 1:1 and group
/// chat screens. Replaces the previous dead-end red snackbar
/// (`perm_microphone_record`): a user who can no longer be re-prompted in-app
/// now gets a rationale plus an "Open Settings" deep-link to recover.
///
/// Living in one helper (instead of two byte-identical inline copies) is the
/// invariant that keeps either screen from silently drifting back to a
/// dead-end toast.
///
/// "Open Settings" routes through the injected [gateway] so host tests spy on
/// the deep-link without hitting the real plugin; "Not now" simply dismisses.
Future<void> showMicPermissionDeniedPrompt(
  BuildContext context, {
  required MicPermissionGateway gateway,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      return AlertDialog(
        title: Text(l10n.mic_perm_dialog_title),
        content: Text(l10n.mic_perm_dialog_body),
        actions: [
          TextButton(
            key: const ValueKey('mic-perm-not-now'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.mic_perm_not_now),
          ),
          TextButton.icon(
            key: const ValueKey('mic-perm-open-settings'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              gateway.openAppSettings();
            },
            icon: const Icon(Icons.settings_outlined),
            label: Text(l10n.compose_open_settings),
          ),
        ],
      );
    },
  );
}
