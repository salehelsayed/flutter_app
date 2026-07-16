import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/runtime_dispatch.dart';

void main() {
  test(
    'one installed artifact acknowledges two nonce-bound scenarios without rebuilding',
    () {
      final dispatcher = SimsRuntimeDispatcher(
        installedProfileId: 'android.e2e.standard',
        artifactDigest: 'artifact-sha256',
      );

      for (final scenario in const <String>['connectivity', 'keepalive']) {
        final config = SimsRuntimeConfig(
          schema: simsRuntimeConfigSchema,
          profileId: 'android.e2e.standard',
          scenarioId: scenario,
          role: 'receiver',
          runId: 'run-$scenario',
          nonce: 'nonce-$scenario',
          values: const <String, Object?>{},
        );
        final staged = dispatcher.stage(config);
        final acknowledgement = dispatcher.acknowledge(
          staged,
          profileId: config.profileId,
          scenarioId: config.scenarioId,
          nonce: config.nonce,
        );
        expect(acknowledgement.accepted, isTrue);
      }

      expect(dispatcher.launchCount, 2);
      expect(dispatcher.buildCount, 0);
      expect(dispatcher.artifactDigest, 'artifact-sha256');
    },
  );

  test(
    'missing stale corrupt or wrong-profile config cannot fall back to a scenario',
    () {
      final dispatcher = SimsRuntimeDispatcher(
        installedProfileId: 'android.e2e.standard',
        artifactDigest: 'artifact-sha256',
      );
      final valid = SimsRuntimeConfig(
        schema: simsRuntimeConfigSchema,
        profileId: 'android.e2e.standard',
        scenarioId: 'connectivity',
        role: 'receiver',
        runId: 'run-1',
        nonce: 'nonce-current',
        values: const <String, Object?>{},
      );

      expect(dispatcher.decodeAndValidate(null).accepted, isFalse);
      expect(dispatcher.decodeAndValidate('{not-json').accepted, isFalse);
      expect(
        dispatcher
            .decodeAndValidate(
              jsonEncode(
                valid.copyWith(profileId: 'android.e2e.wake_token').toJson(),
              ),
            )
            .accepted,
        isFalse,
      );

      final staged = dispatcher.stage(valid);
      expect(
        dispatcher
            .acknowledge(
              staged,
              profileId: valid.profileId,
              scenarioId: valid.scenarioId,
              nonce: 'stale-nonce',
            )
            .accepted,
        isFalse,
      );
      expect(dispatcher.lastAcceptedScenario, isNull);
    },
  );

  test(
    'scenario reset restores process data identity permission notification and network state',
    () {
      const baseline = SimsRuntimeState(
        processRunning: false,
        appDataDigest: 'clean-data',
        identityDigest: 'identity-a',
        grantedPermissions: <String>{'android.permission.RECORD_AUDIO'},
        notificationCount: 0,
        networkEnabled: true,
        installedArtifactDigest: 'artifact-sha256',
      );
      const dirty = SimsRuntimeState(
        processRunning: true,
        appDataDigest: 'scenario-data',
        identityDigest: 'identity-b',
        grantedPermissions: <String>{},
        notificationCount: 3,
        networkEnabled: false,
        installedArtifactDigest: 'artifact-sha256',
      );

      final restored = SimsRuntimeResetter.restore(
        current: dirty,
        baseline: baseline,
      );
      expect(restored, baseline);
      expect(restored.installedArtifactDigest, dirty.installedArtifactDigest);
    },
  );
}
