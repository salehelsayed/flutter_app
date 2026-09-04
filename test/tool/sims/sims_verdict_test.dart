import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/manifest.dart';
import '../../../tool/sims/planner.dart';
import '../../../tool/sims/verdict.dart';

CapabilitySpec _row({
  String id = 'critical.row',
  bool required = true,
  bool artifactRequired = false,
  bool allowTargetUnavailable = false,
}) => CapabilitySpec(
  id: id,
  owner: 'test',
  proofBoundaryId: 'boundary.$id',
  assertionIds: <String>['assert.$id'],
  lane: 'host-dart',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'test'},
  required: required,
  command: const <String>['true'],
  buildProfileId: 'host.flutter_tester',
  dependencies: const <String>[],
  resources: const <ResourceLock>[
    ResourceLock(name: 'host.cpu', access: ResourceAccess.read),
  ],
  targetCapabilities: const <String>[],
  allowedNaReason: allowTargetUnavailable ? targetUnavailableNaReason : null,
  artifactRequired: artifactRequired,
  artifactValidator: null,
  active: true,
  declaredBuildException: false,
);

SimsPlan _plan(CapabilitySpec row) => SimsPlan(
  mode: SimsMode.major,
  simultaneous: false,
  releaseEligibleCandidate: true,
  manifestDigest: 'manifest',
  family: null,
  onlyId: null,
  rows: <CapabilitySpec>[row],
);

void main() {
  test(
    'restoration blocker round trips and unknown blockers stay rejected',
    () {
      final verdict = SimsVerdict.fromJson(<String, Object?>{
        'capabilityId': 'android.foreground_webrtc_audio',
        'status': 'FAIL',
        'assertionsAttempted': 0,
        'exitCode': 1,
        'artifactPresent': false,
        'printOnly': false,
        'blocker': 'restoration',
      });

      expect(verdict.blocker?.name, 'restoration');
      expect(verdict.toJson()['blocker'], 'restoration');
      expect(
        () => SimsVerdict.fromJson(<String, Object?>{
          'capabilityId': 'android.foreground_webrtc_audio',
          'status': 'FAIL',
          'assertionsAttempted': 0,
          'exitCode': 1,
          'artifactPresent': false,
          'printOnly': false,
          'blocker': 'futureFailurePhase',
        }),
        throwsArgumentError,
      );
    },
  );

  test(
    'mandatory skip blocked zero-attempt print-only and missing artifact never pass',
    () {
      final row = _row(artifactRequired: true);
      final evaluator = SimsVerdictEvaluator();
      final invalid = <SimsVerdict>[
        SimsVerdict.skip(row.id, detail: 'skipped'),
        SimsVerdict.blocked(row.id, blocker: SimsBlockerKind.credentials),
        SimsVerdict.pass(row.id, assertionsAttempted: 0, artifactPresent: true),
        SimsVerdict.pass(
          row.id,
          assertionsAttempted: 1,
          artifactPresent: true,
          printOnly: true,
        ),
        SimsVerdict.pass(
          row.id,
          assertionsAttempted: 1,
          artifactPresent: false,
        ),
      ];

      for (final verdict in invalid) {
        final assessment = evaluator.evaluate(
          plan: _plan(row),
          attemptedIds: <String>{row.id},
          verdicts: <SimsVerdict>[verdict],
          cleanFullRun: true,
        );
        expect(
          assessment.releaseEligible,
          isFalse,
          reason: verdict.toJson().toString(),
        );
      }
    },
  );

  test('N/A requires an unavailable live target capability', () {
    final row = _row(allowTargetUnavailable: true);
    final evaluator = SimsVerdictEvaluator();

    final valid = evaluator.evaluate(
      plan: _plan(row),
      attemptedIds: <String>{row.id},
      verdicts: <SimsVerdict>[
        SimsVerdict.notApplicable(
          row.id,
          blocker: SimsBlockerKind.targetUnavailable,
          targetCapabilityAvailable: false,
          reason: targetUnavailableNaReason,
        ),
      ],
      cleanFullRun: true,
    );
    expect(valid.releaseEligible, isTrue);

    for (final blocker in <SimsBlockerKind>[
      SimsBlockerKind.credentials,
      SimsBlockerKind.permissions,
      SimsBlockerKind.missingArtifact,
      SimsBlockerKind.deviceLost,
    ]) {
      final invalid = evaluator.evaluate(
        plan: _plan(row),
        attemptedIds: <String>{row.id},
        verdicts: <SimsVerdict>[
          SimsVerdict.notApplicable(
            row.id,
            blocker: blocker,
            targetCapabilityAvailable: false,
            reason: targetUnavailableNaReason,
          ),
        ],
        cleanFullRun: true,
      );
      expect(invalid.releaseEligible, isFalse);
    }
  });

  test('direct contradictory PASS and N/A objects never satisfy a row', () {
    final passRow = _row();
    expect(
      SimsVerdict(
        capabilityId: passRow.id,
        status: SimsVerdictStatus.pass,
        assertionsAttempted: 1,
        exitCode: 0,
        artifactPresent: true,
        printOnly: false,
        blocker: SimsBlockerKind.credentials,
        targetCapabilityAvailable: false,
        reason: targetUnavailableNaReason,
        detail: '',
      ).satisfies(passRow),
      isFalse,
    );

    final naRow = _row(allowTargetUnavailable: true);
    expect(
      SimsVerdict(
        capabilityId: naRow.id,
        status: SimsVerdictStatus.notApplicable,
        assertionsAttempted: 1,
        exitCode: 7,
        artifactPresent: true,
        printOnly: true,
        blocker: SimsBlockerKind.targetUnavailable,
        targetCapabilityAvailable: false,
        reason: targetUnavailableNaReason,
        detail: '',
      ).satisfies(naRow),
      isFalse,
    );
  });

  test('aggregate selected attempted and terminal IDs reconcile exactly', () {
    final row = _row();
    final evaluator = SimsVerdictEvaluator();
    final pass = SimsVerdict.pass(row.id, assertionsAttempted: 1);

    expect(
      evaluator
          .evaluate(
            plan: _plan(row),
            attemptedIds: const <String>{},
            verdicts: <SimsVerdict>[pass],
            cleanFullRun: true,
          )
          .releaseEligible,
      isFalse,
    );
    expect(
      evaluator
          .evaluate(
            plan: _plan(row),
            attemptedIds: <String>{row.id},
            verdicts: const <SimsVerdict>[],
            cleanFullRun: true,
          )
          .releaseEligible,
      isFalse,
    );
  });

  test(
    'diagnostic continuation and partial retry cannot produce release green',
    () {
      final row = _row();
      final pass = SimsVerdict.pass(row.id, assertionsAttempted: 1);
      final evaluator = SimsVerdictEvaluator();

      for (final assessment in <SimsReleaseAssessment>[
        evaluator.evaluate(
          plan: _plan(row),
          attemptedIds: <String>{row.id},
          verdicts: <SimsVerdict>[pass],
          cleanFullRun: false,
        ),
        evaluator.evaluate(
          plan: _plan(row),
          attemptedIds: <String>{row.id},
          verdicts: <SimsVerdict>[pass],
          cleanFullRun: true,
          diagnosticContinuation: true,
        ),
      ]) {
        expect(assessment.releaseEligible, isFalse);
      }
    },
  );
}
