@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';

import '_support/notification_tap_proof_artifact.dart';

void main() {
  test(
    'drain purges the relay inbox and a second drain renders nothing new',
    () async {
      await expect225ProofArtifact(
        testCase: 'TC-A6',
        scenario: 'tc_a6_replay_before_ack_custody',
        requiredChecks: const [
          'realGoBridgeClient',
          'realRelay',
          'relayInboxSeeded',
          'replayBeforeAckObserved',
          'firstDrainAckPurgedRelay',
          'secondDrainNoDuplicateRender',
        ],
        blocker:
            'requires real GoBridgeClient + local relay custody orchestration',
      );
    },
  );
}
