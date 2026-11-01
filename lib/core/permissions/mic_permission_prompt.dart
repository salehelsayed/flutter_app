import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final l10n = AppLocalizations.of(context)!;
  return _showPermissionDeniedPrompt(
    context,
    gateway: gateway,
    keyPrefix: 'mic-perm',
    icon: Icons.mic_rounded,
    title: l10n.mic_perm_dialog_title,
    body: l10n.mic_perm_dialog_body,
  );
}

/// image_picker's error when the OS refuses camera access.
bool isCameraAccessDenied(Object error) =>
    error is PlatformException && error.code == 'camera_access_denied';

/// The same recovery as the microphone sheet, for a refused camera.
Future<void> showCameraPermissionDeniedPrompt(
  BuildContext context, {
  required MicPermissionGateway gateway,
}) {
  return _showPermissionDeniedPrompt(
    context,
    gateway: gateway,
    keyPrefix: 'camera-perm',
    icon: Icons.photo_camera_outlined,
    body: AppLocalizations.of(context)!.perm_camera,
  );
}

Future<void> _showPermissionDeniedPrompt(
  BuildContext context, {
  required MicPermissionGateway gateway,
  required String keyPrefix,
  required IconData icon,
  String? title,
  required String body,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext)!;
      final scheme = Theme.of(sheetContext).colorScheme;
      return Padding(
        key: ValueKey('$keyPrefix-sheet'),
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
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(height: 16),
            if (title != null) ...[
              Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 8),
            ],
            Text(body, style: Theme.of(sheetContext).textTheme.bodyMedium),
            const SizedBox(height: 20),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                TextButton(
                  key: ValueKey('$keyPrefix-not-now'),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(l10n.mic_perm_not_now),
                ),
                FilledButton.icon(
                  key: ValueKey('$keyPrefix-open-settings'),
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
