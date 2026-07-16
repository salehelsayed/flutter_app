import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/artifact_evidence.dart';
import '../../../tool/sims/checkpoint.dart';
import '../../../tool/sims/verdict.dart';

SimsCheckpoint _checkpoint({
  Map<String, String> buildArtifactDigests = const <String, String>{
    'android.e2e.standard': 'artifact-a',
  },
  List<SimsVerdict>? passedVerdicts,
}) => SimsCheckpoint(
  failedId: 'android.keepalive_drop_skip_direct',
  manifestDigest: 'manifest-a',
  sourceDigest: 'source-a',
  deviceDigest: 'devices-a',
  buildArtifactDigests: buildArtifactDigests,
  redactedCommand: const <String>['runner', '--token=<redacted>'],
  targetAssignments: const <String, String>{'sender': 'pixel-usb'},
  targetStateDigests: const <String, String>{'pixel-usb': 'state-a'},
  logPaths: const <String>['build/sims/logs/keepalive.log'],
  failureClass: SimsFailureClass.product,
  passedIds: const <String>['host.dart.all'],
  passedVerdicts:
      passedVerdicts ??
      <SimsVerdict>[SimsVerdict.pass('host.dart.all', assertionsAttempted: 1)],
  nextId: 'android.voice_recorder_native_smoke',
  createdAt: DateTime.utc(2026, 7, 14),
  finalCleanRunRequired: true,
);

void main() {
  test(
    'failure checkpoint round trips stable ID digests targets and classification',
    () {
      final checkpoint = SimsCheckpoint.fromJson(_checkpoint().toJson());
      expect(checkpoint.failedId, 'android.keepalive_drop_skip_direct');
      expect(checkpoint.manifestDigest, 'manifest-a');
      expect(checkpoint.targetAssignments['sender'], 'pixel-usb');
      expect(
        checkpoint.buildArtifactDigests['android.e2e.standard'],
        'artifact-a',
      );
      expect(checkpoint.failureClass, SimsFailureClass.product);
      expect(checkpoint.passedVerdicts.single.capabilityId, 'host.dart.all');
    },
  );

  test('checkpoint retains exact artifact evidence for prior passes', () {
    final checkpoint = SimsCheckpoint.fromJson(
      _checkpoint(
        passedVerdicts: <SimsVerdict>[
          SimsVerdict.pass(
            'host.dart.all',
            assertionsAttempted: 2,
            artifactPresent: true,
            artifactEvidence: const SimsArtifactEvidence(
              path: '/tmp/prior-proof.json',
              sha256Digest:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              validatorIds: <String>['validatePriorProof'],
            ),
          ),
        ],
      ).toJson(),
    );

    final prior = checkpoint.passedVerdicts.single;
    expect(prior.assertionsAttempted, 2);
    expect(prior.artifactEvidence?.path, '/tmp/prior-proof.json');
    expect(prior.artifactEvidence?.validatorIds, <String>[
      'validatePriorProof',
    ]);
  });

  test(
    'only retry then resume skips prior passes and requires final clean major',
    () {
      final flow = _checkpoint().retryResumePlan(const <String>[
        'host.dart.all',
        'android.keepalive_drop_skip_direct',
        'android.voice_recorder_native_smoke',
        'performance.host',
      ]);
      expect(flow.retryIds, <String>['android.keepalive_drop_skip_direct']);
      expect(flow.resumeIds, <String>[
        'android.voice_recorder_native_smoke',
        'performance.host',
      ]);
      expect(flow.finalCleanRunRequired, isTrue);
    },
  );

  test('manifest source device or artifact mismatch invalidates resume', () {
    final checkpoint = _checkpoint();
    expect(
      checkpoint
          .validateResume(
            manifestDigest: 'manifest-a',
            sourceDigest: 'source-a',
            deviceDigest: 'devices-a',
            buildArtifactDigests: const <String, String>{
              'android.e2e.standard': 'artifact-a',
            },
          )
          .isValid,
      isTrue,
    );

    for (final validation in <CheckpointValidation>[
      checkpoint.validateResume(
        manifestDigest: 'manifest-b',
        sourceDigest: 'source-a',
        deviceDigest: 'devices-a',
        buildArtifactDigests: checkpoint.buildArtifactDigests,
      ),
      checkpoint.validateResume(
        manifestDigest: 'manifest-a',
        sourceDigest: 'source-b',
        deviceDigest: 'devices-a',
        buildArtifactDigests: checkpoint.buildArtifactDigests,
      ),
      checkpoint.validateResume(
        manifestDigest: 'manifest-a',
        sourceDigest: 'source-a',
        deviceDigest: 'devices-b',
        buildArtifactDigests: checkpoint.buildArtifactDigests,
      ),
      checkpoint.validateResume(
        manifestDigest: 'manifest-a',
        sourceDigest: 'source-a',
        deviceDigest: 'devices-a',
        buildArtifactDigests: const <String, String>{
          'android.e2e.standard': 'artifact-b',
        },
      ),
    ]) {
      expect(validation.isValid, isFalse);
    }
  });

  test(
    'focused repair accepts changed source and artifact but freezes manifest and devices',
    () {
      final checkpoint = _checkpoint();
      final repaired = checkpoint.validateResume(
        manifestDigest: 'manifest-a',
        sourceDigest: 'source-b',
        deviceDigest: 'devices-a',
        buildArtifactDigests: const <String, String>{
          'android.e2e.standard': 'artifact-b',
        },
        relevantBuildProfileIds: const <String>{'android.e2e.standard'},
        allowRepairInputChanges: true,
      );
      expect(repaired.isValid, isTrue);

      for (final validation in <CheckpointValidation>[
        checkpoint.validateResume(
          manifestDigest: 'manifest-b',
          sourceDigest: 'source-b',
          deviceDigest: 'devices-a',
          buildArtifactDigests: const <String, String>{
            'android.e2e.standard': 'artifact-b',
          },
          allowRepairInputChanges: true,
        ),
        checkpoint.validateResume(
          manifestDigest: 'manifest-a',
          sourceDigest: 'source-b',
          deviceDigest: 'devices-b',
          buildArtifactDigests: const <String, String>{
            'android.e2e.standard': 'artifact-b',
          },
          allowRepairInputChanges: true,
        ),
      ]) {
        expect(validation.isValid, isFalse);
      }
    },
  );

  test(
    'focused repair tolerates unrelated inventory churn with exact selected-target continuity',
    () {
      final checkpoint = _checkpoint();
      final validation = checkpoint.validateResume(
        manifestDigest: 'manifest-a',
        sourceDigest: 'source-b',
        deviceDigest: 'devices-b',
        buildArtifactDigests: const <String, String>{
          'android.e2e.standard': 'artifact-b',
        },
        allowRepairInputChanges: true,
        currentTargetAssignments: checkpoint.targetAssignments,
        currentTargetStateDigests: checkpoint.targetStateDigests,
      );

      expect(validation.isValid, isTrue);
    },
  );

  test(
    'focused repair rejects incomplete rebound or changed selected-target evidence',
    () {
      final checkpoint = _checkpoint();
      final candidates =
          <({Map<String, String>? assignments, Map<String, String>? states})>[
            (
              assignments: const <String, String>{'sender': 'replacement-usb'},
              states: const <String, String>{'replacement-usb': 'state-a'},
            ),
            (
              assignments: checkpoint.targetAssignments,
              states: const <String, String>{'pixel-usb': 'state-b'},
            ),
            (
              assignments: const <String, String>{
                'sender': 'pixel-usb',
                'observer': 'extra-usb',
              },
              states: const <String, String>{
                'pixel-usb': 'state-a',
                'extra-usb': 'state-extra',
              },
            ),
            (
              assignments: checkpoint.targetAssignments,
              states: const <String, String>{
                'pixel-usb': 'state-a',
                'extra-usb': 'state-extra',
              },
            ),
            (assignments: checkpoint.targetAssignments, states: const {}),
            (assignments: null, states: null),
          ];

      for (final candidate in candidates) {
        final validation = checkpoint.validateResume(
          manifestDigest: 'manifest-a',
          sourceDigest: 'source-b',
          deviceDigest: 'devices-b',
          buildArtifactDigests: checkpoint.buildArtifactDigests,
          allowRepairInputChanges: true,
          currentTargetAssignments: candidate.assignments,
          currentTargetStateDigests: candidate.states,
        );
        expect(validation.isValid, isFalse);
        expect(validation.reasons, contains('device matrix changed'));
      }
    },
  );

  test(
    'resume accepts new profiles but rechecks every checkpoint artifact',
    () {
      final checkpoint = _checkpoint();
      expect(
        checkpoint
            .validateResume(
              manifestDigest: 'manifest-a',
              sourceDigest: 'source-a',
              deviceDigest: 'devices-a',
              buildArtifactDigests: const <String, String>{
                'android.e2e.standard': 'artifact-a',
                'ios.simulator.e2e': 'artifact-new',
              },
            )
            .isValid,
        isTrue,
      );
    },
  );

  test(
    'only retry validates its relevant profile subset and preserves evidence',
    () {
      final checkpoint = _checkpoint(
        buildArtifactDigests: const <String, String>{
          'android.e2e.standard': 'artifact-standard',
          'ios.simulator.e2e': 'artifact-ios',
        },
      );

      final validation = checkpoint.validateResume(
        manifestDigest: 'manifest-a',
        sourceDigest: 'source-a',
        deviceDigest: 'devices-a',
        buildArtifactDigests: const <String, String>{
          'android.e2e.standard': 'artifact-standard',
        },
        relevantBuildProfileIds: const <String>{'android.e2e.standard'},
      );

      expect(validation.isValid, isTrue);
      expect(checkpoint.buildArtifactDigests, <String, String>{
        'android.e2e.standard': 'artifact-standard',
        'ios.simulator.e2e': 'artifact-ios',
      });

      for (final current in const <Map<String, String>>[
        <String, String>{'android.e2e.standard': 'changed'},
        <String, String>{},
      ]) {
        expect(
          checkpoint
              .validateResume(
                manifestDigest: 'manifest-a',
                sourceDigest: 'source-a',
                deviceDigest: 'devices-a',
                buildArtifactDigests: current,
                relevantBuildProfileIds: const <String>{'android.e2e.standard'},
              )
              .isValid,
          isFalse,
        );
      }
    },
  );
}
