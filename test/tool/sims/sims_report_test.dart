import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/manifest.dart';
import '../../../tool/sims/planner.dart';
import '../../../tool/sims/report.dart';
import '../../../tool/sims/scheduler.dart';
import '../../../tool/sims/verdict.dart';

void main() {
  test(
    'plan and report JSON preserve stable selected attempted terminal IDs',
    () {
      final row = CapabilitySpec(
        id: 'host.dart.all',
        owner: 'test',
        proofBoundaryId: 'host.dart',
        assertionIds: const <String>['host.dart.paths'],
        lane: 'host-dart',
        modes: const <SimsMode>{SimsMode.major},
        families: const <String>{'infra'},
        required: true,
        command: const <String>['flutter', 'test'],
        buildProfileId: 'host.flutter_tester',
        dependencies: const <String>[],
        resources: const <ResourceLock>[
          ResourceLock(name: 'host.cpu', access: ResourceAccess.read),
        ],
        targetCapabilities: const <String>[],
        allowedNaReason: null,
        artifactRequired: false,
        artifactValidator: null,
        active: true,
        declaredBuildException: false,
      );
      final plan = SimsPlan(
        mode: SimsMode.major,
        simultaneous: false,
        releaseEligibleCandidate: true,
        manifestDigest: 'manifest',
        family: null,
        onlyId: null,
        rows: <CapabilitySpec>[row],
      );
      final verdict = SimsVerdict.pass(row.id, assertionsAttempted: 1);
      final assessment = SimsVerdictEvaluator().evaluate(
        plan: plan,
        attemptedIds: <String>{row.id},
        verdicts: <SimsVerdict>[verdict],
        cleanFullRun: true,
      );
      final report = SimsReport(
        plan: plan,
        attemptedIds: <String>{row.id},
        verdicts: <SimsVerdict>[verdict],
        assessment: assessment,
        buildReport: SimsBuildReport.empty,
        cleanFullRun: true,
        diagnosticContinuation: false,
        generatedAt: DateTime.utc(2026, 7, 14),
        sourceDigest:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        schedule: SimsScheduleResult(
          selectedIds: <String>{row.id},
          attemptedIds: <String>{row.id},
          verdicts: <SimsVerdict>[verdict],
          traces: const <SimsScheduleTrace>[],
          maxObservedConcurrency: 1,
        ),
        deviceAssignments: const <String, String>{
          'device:android-physical': 'pixel-usb',
        },
        deviceInventoryDigest: 'device-digest',
      );

      final decoded =
          jsonDecode(jsonEncode(report.toJson())) as Map<String, dynamic>;
      expect(decoded['selectedIds'], <String>[row.id]);
      expect(decoded['attemptedIds'], <String>[row.id]);
      expect(decoded['terminalIds'], <String>[row.id]);
      expect(
        (decoded['schedule'] as Map<String, dynamic>)['maxObservedConcurrency'],
        1,
      );
      expect(
        ((decoded['devices'] as Map<String, dynamic>)['assignments']
            as Map<String, dynamic>)['device:android-physical'],
        'pixel-usb',
      );
      expect(report.validationErrors, isEmpty);
    },
  );

  test('sensitive command values are hashed and never emitted', () {
    final redacted = redactCommand(const <String>[
      'runner',
      '--token=super-secret-token',
      '--safe=value',
    ]);
    expect(redacted.join(' '), isNot(contains('super-secret-token')));
    expect(redacted.join(' '), contains('sha256:'));
    expect(redacted, contains('--safe=value'));
  });

  test('build report preserves exact profile outcomes and elapsed times', () {
    const report = SimsBuildReport(
      requestedProfiles: 3,
      actualBuilds: 1,
      hits: 1,
      misses: 2,
      invalidations: <String>['android.main:wrongSource'],
      artifactDigests: <String, String>{
        'android.main':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'android.cached':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      },
      declaredExceptions: <String>[],
      builtProfileIds: <String>['android.main'],
      cacheHitProfileIds: <String>['android.cached'],
      failedProfileIds: <String>['ios.failed'],
      profileElapsedMs: <String, int>{
        'android.main': 82000,
        'android.cached': 11,
        'ios.failed': 2400,
      },
      totalElapsedMs: 84500,
    );

    final decoded = (jsonDecode(jsonEncode(report.toJson())) as Map)
        .cast<String, Object?>();
    final roundTrip = SimsBuildReport.fromJson(decoded);

    expect(roundTrip.builtProfileIds, <String>['android.main']);
    expect(roundTrip.cacheHitProfileIds, <String>['android.cached']);
    expect(roundTrip.failedProfileIds, <String>['ios.failed']);
    expect(roundTrip.profileElapsedMs['android.main'], 82000);
    expect(roundTrip.totalElapsedMs, 84500);
  });
}
