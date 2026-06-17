import 'package:flutter/material.dart';

import 'package:flutter_app/features/groups/domain/models/pending_sibling_device.dart';

/// View model for a pending sibling device awaiting a user trust decision (R2).
class PendingSiblingDeviceView {
  final PendingSiblingDevice device;
  final String memberLabel;
  final String? safetyNumber;

  const PendingSiblingDeviceView({
    required this.device,
    required this.memberLabel,
    this.safetyNumber,
  });
}

/// R2 trust-prompt: a same-user sibling device has announced itself and is
/// awaiting an explicit verify (compare its safety number) before admission.
/// Never auto-admitted — the user must Verify or Reject.
class PendingSiblingDevicePrompt extends StatelessWidget {
  final PendingSiblingDeviceView view;
  final VoidCallback onVerify;
  final VoidCallback onReject;

  const PendingSiblingDevicePrompt({
    super.key,
    required this.view,
    required this.onVerify,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('pending-sibling-device-${view.device.id}'),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices_other),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'New device for ${view.memberLabel}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'A new device wants to join this account. Verify its safety number '
              'matches the new device before approving.',
              style: theme.textTheme.bodySmall,
            ),
            if (view.safetyNumber != null) ...[
              const SizedBox(height: 8),
              Text(
                view.safetyNumber!,
                key: Key('pending-sibling-safety-${view.device.id}'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: Key('pending-sibling-reject-${view.device.id}'),
                  onPressed: onReject,
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: Key('pending-sibling-verify-${view.device.id}'),
                  onPressed: onVerify,
                  child: const Text('Verify & approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
