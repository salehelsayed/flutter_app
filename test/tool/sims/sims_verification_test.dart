import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/build_orchestrator.dart';
import '../../../tool/sims/manifest.dart';
import '../../../tool/sims/planner.dart';
import '../../../tool/sims/report.dart';
import '../../../tool/sims/scheduler.dart';
import '../../../tool/sims/verdict.dart';
import '../../../tool/sims/verification.dart';

const _manifestDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _sourceDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _artifactDigest =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _deviceDigest =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

CapabilitySpec _buildRow() => CapabilitySpec(
  id: 'build.android.standard',
  owner: 'test',
  proofBoundaryId: 'build.android.standard.attested',
  assertionIds: const <String>['build.attested'],
  lane: 'reliability',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'test'},
  required: true,
  command: const <String>['@prepare-build', 'android.standard'],
  buildProfileId: 'android.standard',
  dependencies: const <String>[],
  resources: const <ResourceLock>[
    ResourceLock(name: 'build:android.standard', access: ResourceAccess.write),
  ],
  targetCapabilities: const <String>[],
  allowedNaReason: null,
  artifactRequired: true,
  artifactValidator: 'sha256',
  active: true,
  declaredBuildException: false,
);

CapabilitySpec _deviceRow() => CapabilitySpec(
  id: 'android.proof',
  owner: 'test',
  proofBoundaryId: 'android.real-device',
  assertionIds: const <String>['android.proof.complete'],
  lane: 'reliability',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'test'},
  required: true,
  command: const <String>['runner', '--scenario', 'android.proof'],
  buildProfileId: 'android.standard',
  dependencies: const <String>['build.android.standard'],
  resources: const <ResourceLock>[
    ResourceLock(name: 'build:android.standard', access: ResourceAccess.read),
    ResourceLock(name: 'device:pixel', access: ResourceAccess.exclusive),
  ],
  targetCapabilities: const <String>['android.physical'],
  allowedNaReason: targetUnavailableNaReason,
  artifactRequired: false,
  artifactValidator: null,
  active: true,
  declaredBuildException: false,
);

SimsPlan _plan({required bool simultaneous, String? manifestDigest}) =>
    SimsPlan(
      mode: SimsMode.major,
      simultaneous: simultaneous,
      releaseEligibleCandidate: true,
      manifestDigest: manifestDigest ?? _manifestDigest,
      family: null,
      onlyId: null,
      rows: <CapabilitySpec>[_buildRow(), _deviceRow()],
    );

Map<String, Object?> _reportJson({
  required bool simultaneous,
  String? manifestDigest,
  String sourceDigest = _sourceDigest,
}) {
  final plan = _plan(
    simultaneous: simultaneous,
    manifestDigest: manifestDigest,
  );
  final buildVerdict = SimsVerdict.pass(
    'build.android.standard',
    assertionsAttempted: 1,
    artifactPresent: true,
  );
  final deviceVerdict = SimsVerdict.pass(
    'android.proof',
    assertionsAttempted: 1,
    artifactPresent: true,
  );
  final verdicts = <SimsVerdict>[buildVerdict, deviceVerdict];
  final ids = <String>{'build.android.standard', 'android.proof'};
  final assessment = SimsVerdictEvaluator().evaluate(
    plan: plan,
    attemptedIds: ids,
    verdicts: verdicts,
    cleanFullRun: true,
  );
  final base = DateTime.utc(2026, 7, 15, 8);
  final schedule = SimsScheduleResult(
    selectedIds: ids,
    attemptedIds: ids,
    verdicts: verdicts,
    traces: <SimsScheduleTrace>[
      SimsScheduleTrace(
        capabilityId: 'build.android.standard',
        startedAt: base,
        endedAt: base.add(const Duration(seconds: 1)),
        dependencyWait: Duration.zero,
        resources: _buildRow().resources,
      ),
      SimsScheduleTrace(
        capabilityId: 'android.proof',
        startedAt: base.add(const Duration(seconds: 1)),
        endedAt: base.add(const Duration(seconds: 2)),
        dependencyWait: const Duration(seconds: 1),
        resources: _deviceRow().resources,
      ),
    ],
    maxObservedConcurrency: 1,
  );
  return SimsReport(
    plan: plan,
    attemptedIds: ids,
    verdicts: verdicts,
    assessment: assessment,
    buildReport: const SimsBuildReport(
      requestedProfiles: 1,
      actualBuilds: 1,
      hits: 0,
      misses: 1,
      invalidations: <String>[],
      artifactDigests: <String, String>{'android.standard': _artifactDigest},
      declaredExceptions: <String>[],
    ),
    cleanFullRun: true,
    diagnosticContinuation: false,
    generatedAt: base,
    schedule: schedule,
    deviceAssignments: const <String, String>{
      'device:android-physical': 'pixel',
    },
    deviceInventoryDigest: _deviceDigest,
    sourceDigest: sourceDigest,
  ).toJson();
}

Map<String, Object?> _currentReportJson(
  SimsManifest manifest, {
  required bool simultaneous,
  required String sourceDigest,
}) {
  final plan = SimsPlanner(manifest).compile(
    mode: SimsMode.major,
    onlyId: 'analyzer.flutter',
    simultaneous: simultaneous,
  );
  final row = plan.rows.single;
  final verdict = SimsVerdict.pass(row.id, assertionsAttempted: 1);
  final assessment = SimsVerdictEvaluator().evaluate(
    plan: plan,
    attemptedIds: <String>{row.id},
    verdicts: <SimsVerdict>[verdict],
    cleanFullRun: false,
  );
  final base = DateTime.utc(2026, 7, 15, 9);
  return SimsReport(
    plan: plan,
    attemptedIds: <String>{row.id},
    verdicts: <SimsVerdict>[verdict],
    assessment: assessment,
    buildReport: SimsBuildReport.empty,
    cleanFullRun: false,
    diagnosticContinuation: false,
    generatedAt: base,
    sourceDigest: sourceDigest,
    schedule: SimsScheduleResult(
      selectedIds: <String>{row.id},
      attemptedIds: <String>{row.id},
      verdicts: <SimsVerdict>[verdict],
      traces: <SimsScheduleTrace>[
        SimsScheduleTrace(
          capabilityId: row.id,
          startedAt: base,
          endedAt: base.add(const Duration(seconds: 1)),
          dependencyWait: Duration.zero,
          resources: row.resources,
        ),
      ],
      maxObservedConcurrency: 1,
    ),
  ).toJson();
}

Map<String, Object?> _clone(Map<String, Object?> source) {
  final decoded = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  return decoded.map((key, value) => MapEntry(key, value));
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) {
    throw StateError('Expected a JSON object, got ${value.runtimeType}.');
  }
  return value.cast<String, Object?>();
}

List<Map<String, Object?>> _maps(Object? value) =>
    (value! as List).map((item) => _map(item)).toList(growable: false);

void main() {
  test(
    'report audit reconstructs IDs and assessment instead of trusting JSON',
    () {
      final valid = auditSimsReportJson(
        _reportJson(simultaneous: false),
        expectedManifestDigest: _manifestDigest,
        expectedSourceDigest: _sourceDigest,
      );
      expect(valid.errors, isEmpty);
      expect(valid.computedAssessment.releaseEligible, isTrue);

      final forged = _clone(_reportJson(simultaneous: false));
      forged['attemptedIds'] = <String>['build.android.standard'];
      _map(forged['assessment'])['releaseEligible'] = true;
      final audit = auditSimsReportJson(
        forged,
        expectedManifestDigest: _manifestDigest,
        expectedSourceDigest: _sourceDigest,
      );
      expect(audit.errors.join('\n'), contains('do not reconcile'));
      expect(
        audit.errors.join('\n'),
        contains('serialized assessment IDs differ'),
      );
    },
  );

  test('report audit requires a current whole-suite source digest', () {
    final missing = _clone(_reportJson(simultaneous: false))
      ..remove('sourceDigest');
    expect(
      auditSimsReportJson(missing).errors.join('\n'),
      contains('sourceDigest is required'),
    );

    final stale = auditSimsReportJson(
      _reportJson(simultaneous: false),
      expectedSourceDigest:
          'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    );
    expect(stale.errors.join('\n'), contains('does not match current source'));
  });

  test(
    'policy N/A requires the targetUnavailable blocker and current digests',
    () {
      final report = _clone(_reportJson(simultaneous: false));
      final verdicts = _maps(report['verdicts']);
      final scheduleVerdicts = _maps(_map(report['schedule'])['verdicts']);
      for (final collection in <List<Map<String, Object?>>>[
        verdicts,
        scheduleVerdicts,
      ]) {
        final verdict = collection.singleWhere(
          (item) => item['capabilityId'] == 'android.proof',
        );
        verdict
          ..remove('exitCode')
          ..['status'] = 'N/A'
          ..['assertionsAttempted'] = 0
          ..['artifactPresent'] = false
          ..['blocker'] = 'credentials'
          ..['targetCapabilityAvailable'] = false
          ..['reason'] = targetUnavailableNaReason;
      }
      report['verdicts'] = verdicts;
      _map(report['schedule'])['verdicts'] = scheduleVerdicts;
      final audit = auditSimsReportJson(
        report,
        expectedManifestDigest: '${_manifestDigest}x',
        expectedSourceDigest: '${_sourceDigest}x',
      );
      expect(audit.errors.join('\n'), contains('invalid N/A evidence'));
      expect(audit.errors.join('\n'), contains('current manifest'));
      expect(audit.errors.join('\n'), contains('current source'));
    },
  );

  test(
    'build counts, artifact hashes, and executed device assignments audit',
    () {
      final report = _clone(_reportJson(simultaneous: false));
      final builds = _map(report['builds']);
      builds
        ..['hits'] = 1
        ..['misses'] = 1
        ..['artifactDigests'] = <String, String>{
          'android.standard': 'not-a-digest',
        };
      report['builds'] = builds;
      _map(report['devices'])['assignments'] = <String, String>{};

      final audit = auditSimsReportJson(report);
      expect(audit.errors.join('\n'), contains('hits + misses'));
      expect(audit.errors.join('\n'), contains('not SHA-256'));
      expect(audit.errors.join('\n'), contains('no reported assignment'));
    },
  );

  test(
    'report audit rechecks runtime proof path digest and validator binding',
    () {
      final directory = Directory.systemTemp.createTempSync(
        'sims-report-artifact-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final proof = File('${directory.path}/proof.json')
        ..writeAsStringSync('{"status":"passed"}\n');
      final digest = sha256.convert(proof.readAsBytesSync()).toString();
      final report = _clone(_reportJson(simultaneous: false));
      final plan = _map(report['plan']);
      final rows = _maps(plan['rows']);
      final row = rows.singleWhere((item) => item['id'] == 'android.proof');
      row
        ..['artifactRequired'] = true
        ..['artifactValidator'] = 'proof';
      plan['rows'] = rows;
      report['plan'] = plan;

      final evidence = <String, Object?>{
        'path': proof.resolveSymbolicLinksSync(),
        'sha256': digest,
        'validatorIds': <String>['proof'],
      };
      final outerVerdicts = _maps(report['verdicts']);
      outerVerdicts.singleWhere(
        (item) => item['capabilityId'] == 'android.proof',
      )['artifactEvidence'] = evidence;
      report['verdicts'] = outerVerdicts;
      final scheduleVerdicts = _maps(_map(report['schedule'])['verdicts']);
      scheduleVerdicts.singleWhere(
        (item) => item['capabilityId'] == 'android.proof',
      )['artifactEvidence'] = evidence;
      _map(report['schedule'])['verdicts'] = scheduleVerdicts;

      expect(auditSimsReportJson(report).errors, isEmpty);

      proof.writeAsStringSync('{"status":"tampered"}\n');
      expect(
        auditSimsReportJson(report).errors.join('\n'),
        contains('SHA-256 mismatch'),
      );

      proof.writeAsStringSync('{"status":"passed"}\n');
      final forged = _clone(report);
      for (final verdicts in <List<Map<String, Object?>>>[
        _maps(forged['verdicts']),
        _maps(_map(forged['schedule'])['verdicts']),
      ]) {
        final artifactEvidence = _map(
          verdicts.singleWhere(
            (item) => item['capabilityId'] == 'android.proof',
          )['artifactEvidence'],
        );
        artifactEvidence['validatorIds'] = <String>['forged'];
        verdicts.singleWhere(
          (item) => item['capabilityId'] == 'android.proof',
        )['artifactEvidence'] = artifactEvidence;
      }
      forged['verdicts'] = _maps(forged['verdicts']);
      _map(forged['schedule'])['verdicts'] = _maps(
        _map(forged['schedule'])['verdicts'],
      );
      expect(
        auditSimsReportJson(forged).errors.join('\n'),
        contains('do not exactly match'),
      );

      proof.deleteSync();
      expect(
        auditSimsReportJson(report).errors.join('\n'),
        contains('not a regular file'),
      );
    },
  );

  test('schedule audit requires every trace and enforces order and locks', () {
    final missing = _clone(_reportJson(simultaneous: true));
    final missingSchedule = _map(missing['schedule']);
    missingSchedule['traces'] = _maps(
      missingSchedule['traces'],
    ).where((trace) => trace['capabilityId'] != 'android.proof').toList();
    missing['schedule'] = missingSchedule;
    expect(
      auditSimsReportJson(missing).errors.join('\n'),
      contains('traces are incomplete'),
    );

    final overlapping = _clone(_reportJson(simultaneous: true));
    final traces = _maps(_map(overlapping['schedule'])['traces']);
    final deviceTrace = traces.singleWhere(
      (trace) => trace['capabilityId'] == 'android.proof',
    );
    deviceTrace['startedAt'] = DateTime.utc(
      2026,
      7,
      15,
      8,
      0,
      0,
      500,
    ).toIso8601String();
    _map(overlapping['schedule'])
      ..['traces'] = traces
      ..['maxObservedConcurrency'] = 2;
    final errors = auditSimsReportJson(overlapping).errors.join('\n');
    expect(errors, contains('started before dependency'));
    expect(errors, contains('conflicting schedule locks overlap'));
  });

  test(
    'schedule equivalence accepts plans and audits execution reports',
    () async {
      final manifest = SimsManifest.loadSync(
        File('tool/sims/critical_features.json'),
      );
      final directory = Directory.systemTemp.createTempSync('sims-verify-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final serialPlan = _plan(
        simultaneous: false,
        manifestDigest: manifest.digest,
      );
      final simultaneousPlan = _plan(
        simultaneous: true,
        manifestDigest: manifest.digest,
      );
      final serialPlanFile = File('${directory.path}/serial-plan.json')
        ..writeAsStringSync(jsonEncode(serialPlan.toJson()));
      final simultaneousPlanFile = File('${directory.path}/parallel-plan.json')
        ..writeAsStringSync(jsonEncode(simultaneousPlan.toJson()));
      expect(
        await runSimsVerificationCommand(<String>[
          'verify-schedule-equivalence',
          serialPlanFile.path,
          simultaneousPlanFile.path,
        ]),
        0,
      );

      final currentSourceDigest = computeSimsSourceClosureDigest();
      final serialReport = _currentReportJson(
        manifest,
        simultaneous: false,
        sourceDigest: currentSourceDigest,
      );
      final simultaneousReport = _currentReportJson(
        manifest,
        simultaneous: true,
        sourceDigest: currentSourceDigest,
      );
      final serialReportFile = File('${directory.path}/serial-report.json')
        ..writeAsStringSync(jsonEncode(serialReport));
      final simultaneousReportFile = File(
        '${directory.path}/parallel-report.json',
      )..writeAsStringSync(jsonEncode(simultaneousReport));
      expect(
        await runSimsVerificationCommand(<String>[
          'verify-schedule-equivalence',
          serialReportFile.path,
          simultaneousReportFile.path,
        ]),
        0,
      );

      final forged = _clone(simultaneousReport);
      final verdicts = _maps(forged['verdicts']);
      final scheduleVerdicts = _maps(_map(forged['schedule'])['verdicts']);
      verdicts.single['detail'] = 'parallel-only-forgery';
      scheduleVerdicts.single['detail'] = 'parallel-only-forgery';
      forged['verdicts'] = verdicts;
      _map(forged['schedule'])['verdicts'] = scheduleVerdicts;
      simultaneousReportFile.writeAsStringSync(jsonEncode(forged));
      expect(
        await runSimsVerificationCommand(<String>[
          'verify-schedule-equivalence',
          serialReportFile.path,
          simultaneousReportFile.path,
        ]),
        1,
      );
    },
  );

  test(
    'current plan and report verification reject partial or stale evidence',
    () async {
      final manifest = SimsManifest.loadSync(
        File('tool/sims/critical_features.json'),
      );
      final directory = Directory.systemTemp.createTempSync('sims-current-');
      addTearDown(() => directory.deleteSync(recursive: true));

      final canonicalPlan = SimsPlanner(manifest).compile(mode: SimsMode.major);
      final planFile = File('${directory.path}/plan.json')
        ..writeAsStringSync(jsonEncode(canonicalPlan.toJson()));
      expect(
        await runSimsVerificationCommand(<String>[
          'verify-plan',
          planFile.path,
        ]),
        0,
      );

      final partialPlan = _clone(canonicalPlan.toJson());
      final partialRows = _maps(partialPlan['rows']).toList();
      final removedId = partialRows.removeLast()['id'];
      partialPlan
        ..['rows'] = partialRows
        ..['selectedIds'] = (partialPlan['selectedIds']! as List)
            .where((id) => id != removedId)
            .toList();
      planFile.writeAsStringSync(jsonEncode(partialPlan));
      expect(
        await runSimsVerificationCommand(<String>[
          'verify-plan',
          planFile.path,
        ]),
        1,
      );

      final sourceDigest = computeSimsSourceClosureDigest();
      final currentReport = _currentReportJson(
        manifest,
        simultaneous: false,
        sourceDigest: sourceDigest,
      );
      final reportFile = File('${directory.path}/report.json')
        ..writeAsStringSync(jsonEncode(currentReport));
      expect(
        await runSimsVerificationCommand(<String>[
          'verify-report',
          reportFile.path,
        ]),
        0,
      );

      final partialReport = _clone(currentReport);
      _map(partialReport['plan'])
        ..['onlyId'] = null
        ..['releaseEligibleCandidate'] = true;
      reportFile.writeAsStringSync(jsonEncode(partialReport));
      expect(
        await runSimsVerificationCommand(<String>[
          'verify-report',
          reportFile.path,
        ]),
        1,
      );

      final missingDigest = _clone(currentReport)..remove('sourceDigest');
      reportFile.writeAsStringSync(jsonEncode(missingDigest));
      expect(
        await runSimsVerificationCommand(<String>[
          'verify-report',
          reportFile.path,
        ]),
        1,
      );

      final staleDigest = _clone(currentReport)
        ..['sourceDigest'] = _sourceDigest;
      reportFile.writeAsStringSync(jsonEncode(staleDigest));
      expect(
        await runSimsVerificationCommand(<String>[
          'verify-report',
          reportFile.path,
        ]),
        1,
      );
    },
  );

  test('filesystem ownership rejects missing and forged critical owners', () {
    final directory = Directory.systemTemp.createTempSync('sims-owner-');
    addTearDown(() => directory.deleteSync(recursive: true));
    Directory(
      '${directory.path}/lib/features/alpha',
    ).createSync(recursive: true);
    final capability = CapabilitySpec(
      id: 'host.alpha',
      owner: 'test',
      proofBoundaryId: 'host.alpha.boundary',
      assertionIds: const <String>['alpha.covered'],
      lane: 'host-dart',
      modes: const <SimsMode>{SimsMode.major},
      families: const <String>{'test'},
      required: false,
      command: const <String>['flutter', 'test', 'alpha'],
      buildProfileId: 'host.process',
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
    const profile = BuildProfileSpec(
      id: 'host.process',
      platform: 'host',
      artifactKind: 'none',
      buildRequired: false,
      compileDefines: <String, String>{},
      declaredException: false,
    );

    final missing = SimsManifest(
      schemaVersion: 1,
      buildProfiles: const <BuildProfileSpec>[profile],
      capabilities: <CapabilitySpec>[capability],
      ownership: const <FeatureOwnership>[],
    );
    expect(
      validateSimsFilesystemOwnership(
        missing,
        repoRoot: directory,
        requiredCorePaths: const <String>{},
      ).join('\n'),
      contains('Missing critical ownership: lib/features/alpha'),
    );

    final forged = SimsManifest(
      schemaVersion: 1,
      buildProfiles: const <BuildProfileSpec>[profile],
      capabilities: <CapabilitySpec>[capability],
      ownership: const <FeatureOwnership>[
        FeatureOwnership(
          path: 'lib/features/alpha',
          capabilityId: 'host.alpha',
          critical: true,
          rationale: '',
        ),
      ],
    );
    expect(
      validateSimsFilesystemOwnership(
        forged,
        repoRoot: directory,
        requiredCorePaths: const <String>{},
      ).join('\n'),
      contains('inactive, optional, or non-major capability'),
    );
  });
}
