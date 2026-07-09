@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';

import '_support/notification_tap_proof_artifact.dart';

void main() {
  test(
    'real ciphertext envelope staged then ingested renders before any drain and later drain does not duplicate',
    () async {
      await expect225ProofArtifact(
        testCase: 'TC-B11',
        scenario: 'tc_b11_payload_persist_pre_drain',
        requiredChecks: const [
          'realPeerCiphertext',
          'realGoBridgeClient',
          'realRelay',
          'stagedEnvelopeRead',
          'visibleBeforeDrain',
          'noDrainBeforeVisibility',
          'laterDrainNoDuplicate',
        ],
        blocker:
            'requires real peer ciphertext, GoBridgeClient, and local relay',
      );
    },
  );
}
