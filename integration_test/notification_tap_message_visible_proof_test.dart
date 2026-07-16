// Capture-owned artifact binding. It performs no device action and is invoked
// only after the notification capture owner writes the TC-B12 artifacts.
library;

import 'package:flutter_test/flutter_test.dart';

import '_support/notification_tap_proof_artifact.dart';

void main() {
  test('payload_fast_path_ios_receiver', () async {
    await expect225ProofArtifact(
      testCase: 'TC-B12',
      scenario: 'payload_fast_path_ios_receiver',
      requiredChecks: const [
        'iosReceiver',
        'apnsDelivered',
        'nseStagingOn',
        'nse04P0WithStagingOn',
        'airplaneModeBeforeTap',
        'messageVisibleFromStagedEnvelope',
        'noRelayDrainBeforeVisibility',
      ],
      blocker:
          'requires iPhone receiver, APNs/NSE, full airplane-mode tap proof, and NSE 04-P0 assertions',
    );
  });

  test('payload_fast_path_android_receiver', () async {
    await expect225ProofArtifact(
      testCase: 'TC-B12',
      scenario: 'payload_fast_path_android_receiver',
      requiredChecks: const [
        'androidReceiver',
        'fcmDelivered',
        'backgroundIsolateStaged',
        'airplaneModeBeforeTap',
        'messageVisibleFromStagedEnvelope',
        'noRelayDrainBeforeVisibility',
      ],
      blocker:
          'requires Android receiver, FCM background isolate staging, and full airplane-mode tap proof',
    );
  });

  test('payload_fast_path_cold_kill', () async {
    await expect225ProofArtifact(
      testCase: 'TC-B12',
      scenario: 'payload_fast_path_cold_kill',
      requiredChecks: const [
        'receiverTerminatedBeforeTap',
        'notificationTapColdLaunchedApp',
        'startupIngestRan',
        'messageVisibleFromStagedEnvelope',
        'noRelayDrainBeforeVisibility',
      ],
      blocker:
          'requires force-stop/terminate before notification tap and cold-launch staged-envelope ingest proof',
    );
  });
}
