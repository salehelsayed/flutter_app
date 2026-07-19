import 'package:flutter/material.dart';

import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Shared microphone-permission rationale sheet used by BOTH the 1:1 and group
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
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext)!;
      final scheme = Theme.of(sheetContext).colorScheme;
      return Padding(
        key: const ValueKey('mic-perm-sheet'),
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  Icons.mic_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.mic_perm_dialog_title,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.mic_perm_dialog_body,
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('mic-perm-not-now'),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(l10n.mic_perm_not_now),
                ),
                FilledButton.icon(
                  key: const ValueKey('mic-perm-open-settings'),
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await gateway.openAppSettings();
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(l10n.compose_open_settings),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
