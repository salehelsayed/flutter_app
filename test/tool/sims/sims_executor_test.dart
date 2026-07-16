import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/executor.dart';
import '../../../tool/sims/manifest.dart';
import '../../../tool/sims/verdict.dart';

const _zeroDigest =
    '0000000000000000000000000000000000000000000000000000000000000000';

CapabilitySpec _buildRow(String profileId) => CapabilitySpec(
  id: 'build.$profileId',
  owner: 'test',
  proofBoundaryId: 'boundary.$profileId',
  assertionIds: <String>['assert.$profileId'],
  lane: 'build',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'test'},
  required: true,
  command: <String>['@prepare-build', profileId],
  buildProfileId: profileId,
  dependencies: const <String>[],
  resources: <ResourceLock>[
    ResourceLock(name: 'build:$profileId', access: ResourceAccess.write),
  ],
  targetCapabilities: const <String>[],
  allowedNaReason: null,
  artifactRequired: true,
  artifactValidator: 'build.attestation',
  active: true,
  declaredBuildException: false,
);

CapabilitySpec _processRow({
  required bool declaredBuildException,
  bool allowTargetUnavailable = false,
}) => CapabilitySpec(
  id: declaredBuildException ? 'fixture.allowed' : 'fixture.guarded',
  owner: 'test',
  proofBoundaryId: declaredBuildException
      ? 'boundary.allowed'
      : 'boundary.guarded',
  assertionIds: const <String>['assert.command'],
  lane: 'reliability',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'test'},
  required: true,
  command: const <String>[
    'bash',
    '-c',
    'flutter build apk || true; '
        'printf \'SIMS_RESULT_JSON={"status":"PASS",'
        '"assertionsAttempted":1,"artifactPresent":true,'
        '"printOnly":false}\\n\'',
  ],
  buildProfileId: 'host.fixture',
  dependencies: const <String>[],
  resources: const <ResourceLock>[
    ResourceLock(name: 'host.cpu', access: ResourceAccess.read),
  ],
  targetCapabilities: const <String>[],
  allowedNaReason: allowTargetUnavailable ? targetUnavailableNaReason : null,
  artifactRequired: false,
  artifactValidator: null,
  active: true,
  declaredBuildException: declaredBuildException,
);

CapabilitySpec _artifactRow() => CapabilitySpec(
  id: 'fixture.artifact-proof',
  owner: 'test',
  proofBoundaryId: 'boundary.artifact-proof',
  assertionIds: const <String>['assert.artifact-proof'],
  lane: 'reliability',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'test'},
  required: true,
  command: const <String>[
    'bash',
    '-c',
    r'''printf 'SIMS_RESULT_JSON=%s\n' "$SIMS_TEST_SENTINEL"''',
  ],
  buildProfileId: 'host.fixture',
  dependencies: const <String>[],
  resources: const <ResourceLock>[
    ResourceLock(name: 'host.cpu', access: ResourceAccess.read),
  ],
  targetCapabilities: const <String>[],
  allowedNaReason: null,
  artifactRequired: true,
  artifactValidator: 'fixture.validator',
  active: true,
  declaredBuildException: false,
);

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'sims-executor-test-',
    );
  });

  tearDown(() {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('prepared APK file satisfies a build row', () async {
    final artifact = File('${temporaryDirectory.path}/app.apk')
      ..writeAsStringSync('apk');
    final execution = await SimsProcessExecutor(
      logDirectory: Directory('${temporaryDirectory.path}/logs'),
      preparedArtifacts: <String, String>{
        'android.e2e.standard': artifact.path,
      },
    ).execute(_buildRow('android.e2e.standard'));

    expect(execution.verdict.status, SimsVerdictStatus.pass);
    expect(execution.verdict.artifactPresent, isTrue);
  });

  test('prepared Runner.app directory satisfies a build row', () async {
    final artifact = Directory('${temporaryDirectory.path}/Runner.app')
      ..createSync();
    File('${artifact.path}/Info.plist').writeAsStringSync('plist');
    final execution = await SimsProcessExecutor(
      logDirectory: Directory('${temporaryDirectory.path}/logs'),
      preparedArtifacts: <String, String>{'ios.simulator.e2e': artifact.path},
    ).execute(_buildRow('ios.simulator.e2e'));

    expect(execution.verdict.status, SimsVerdictStatus.pass);
    expect(execution.verdict.artifactPresent, isTrue);
  });

  test('missing prepared artifact remains blocked', () async {
    final execution = await SimsProcessExecutor(
      logDirectory: Directory('${temporaryDirectory.path}/logs'),
      preparedArtifacts: <String, String>{
        'ios.simulator.e2e': '${temporaryDirectory.path}/missing.app',
      },
    ).execute(_buildRow('ios.simulator.e2e'));

    expect(execution.verdict.status, SimsVerdictStatus.blocked);
    expect(execution.verdict.blocker, SimsBlockerKind.missingArtifact);
  });

  test('capability environment overrides global device assignments', () async {
    final row = _processRow(declaredBuildException: true).copyWith(
      command: const <String>[
        'bash',
        '-c',
        r'''printf 'assignment=%s\n' "$SIMS_DEVICE_ASSIGNMENTS_JSON"
printf 'SIMS_RESULT_JSON={"status":"PASS","assertionsAttempted":1,"artifactPresent":false,"printOnly":false}\n' ''',
      ],
    );
    final execution = await SimsProcessExecutor(
      logDirectory: Directory('${temporaryDirectory.path}/logs'),
      environment: <String, String>{
        ...Platform.environment,
        'SIMS_DEVICE_ASSIGNMENTS_JSON': '{"global":"device"}',
      },
      environmentByCapabilityId: <String, Map<String, String>>{
        row.id: <String, String>{
          'SIMS_DEVICE_ASSIGNMENTS_JSON': '{"row":"device"}',
        },
      },
    ).execute(row);

    expect(execution.verdict.status, SimsVerdictStatus.pass);
    expect(execution.stdoutText, contains('assignment={"row":"device"}'));
    expect(execution.stdoutText, isNot(contains('{"global":"device"}')));
  });

  test('child receives only its declared build-profile artifact', () async {
    final declared = File('${temporaryDirectory.path}/declared.apk')
      ..writeAsStringSync('declared');
    final unrelated = File('${temporaryDirectory.path}/unrelated.apk')
      ..writeAsStringSync('unrelated');
    final row = _processRow(declaredBuildException: true).copyWith(
      command: const <String>[
        'bash',
        '-c',
        r'''printf 'declared=%s\n' "$SIMS_ARTIFACT_HOST_FIXTURE"
printf 'unrelated=%s\n' "${SIMS_ARTIFACT_ANDROID_E2E_STANDARD-unset}"
printf 'SIMS_RESULT_JSON={"status":"PASS","assertionsAttempted":1,"artifactPresent":false,"printOnly":false}\n' ''',
      ],
    );

    final execution = await SimsProcessExecutor(
      logDirectory: Directory('${temporaryDirectory.path}/logs'),
      environment: <String, String>{
        ...Platform.environment,
        'SIMS_ARTIFACT_ANDROID_E2E_STANDARD': 'inherited-contamination',
      },
      preparedArtifacts: <String, String>{
        'host.fixture': declared.path,
        'android.e2e.standard': unrelated.path,
      },
    ).execute(row);

    expect(execution.verdict.status, SimsVerdictStatus.pass);
    expect(execution.stdoutText, contains('declared=${declared.path}'));
    expect(execution.stdoutText, contains('unrelated=unset'));
    expect(execution.stdoutText, isNot(contains(unrelated.path)));
    expect(execution.stdoutText, isNot(contains('inherited-contamination')));
  });

  test('undeclared child flutter build overrides a forged PASS', () async {
    final bin = Directory('${temporaryDirectory.path}/bin')..createSync();
    final flutter = File('${bin.path}/flutter')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    Process.runSync('chmod', <String>['700', flutter.path]);
    final execution = await SimsProcessExecutor(
      logDirectory: Directory('${temporaryDirectory.path}/logs'),
      environment: <String, String>{
        ...Platform.environment,
        'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
      },
    ).execute(_processRow(declaredBuildException: false));

    expect(execution.verdict.status, SimsVerdictStatus.fail);
    expect(execution.verdict.exitCode, 91);
    expect(execution.verdict.detail, contains('flutter build apk'));
  });

  test('declared child build exception bypasses the guard', () async {
    final bin = Directory('${temporaryDirectory.path}/bin')..createSync();
    final flutter = File('${bin.path}/flutter')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    Process.runSync('chmod', <String>['700', flutter.path]);
    final execution = await SimsProcessExecutor(
      logDirectory: Directory('${temporaryDirectory.path}/logs'),
      environment: <String, String>{
        ...Platform.environment,
        'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
      },
    ).execute(_processRow(declaredBuildException: true));

    expect(execution.verdict.status, SimsVerdictStatus.pass);
  });

  test(
    'structured sentinel survives tool output without a preceding newline',
    () async {
      final row = _processRow(declaredBuildException: true).copyWith(
        command: const <String>[
          'bash',
          '-c',
          'printf \'Running build hooks...SIMS_RESULT_JSON={"status":"PASS",'
              '"assertionsAttempted":1,"artifactPresent":true,'
              '"printOnly":false,"exitCode":0}\\n\'',
        ],
      );
      final execution = await SimsProcessExecutor(
        logDirectory: Directory('${temporaryDirectory.path}/logs'),
      ).execute(row);

      expect(execution.verdict.status, SimsVerdictStatus.pass);
      expect(execution.verdict.assertionsAttempted, 1);
    },
  );

  test('a forged zero-exit PASS cannot hide a nonzero process exit', () async {
    final row = _processRow(declaredBuildException: true).copyWith(
      command: const <String>[
        'bash',
        '-c',
        'printf \'SIMS_RESULT_JSON={"status":"PASS",'
            '"assertionsAttempted":1,"artifactPresent":true,'
            '"printOnly":false,"exitCode":0}\\n\'; exit 7',
      ],
    );
    final execution = await SimsProcessExecutor(
      logDirectory: Directory('${temporaryDirectory.path}/logs'),
    ).execute(row);

    expect(execution.verdict.status, SimsVerdictStatus.fail);
    expect(execution.verdict.exitCode, 7);
    expect(execution.verdict.detail, contains('does not match process exit 7'));
  });

  Future<SimsCommandExecution> executeArtifactSentinel(
    Map<String, Object?> sentinel,
  ) => SimsProcessExecutor(
    logDirectory: Directory('${temporaryDirectory.path}/logs'),
    environment: <String, String>{
      ...Platform.environment,
      'SIMS_TEST_SENTINEL': jsonEncode(sentinel),
    },
  ).execute(_artifactRow());

  Future<SimsCommandExecution> executeStructuredSentinel(
    Map<String, Object?> sentinel, {
    int processExitCode = 0,
  }) =>
      SimsProcessExecutor(
        logDirectory: Directory('${temporaryDirectory.path}/logs'),
        environment: <String, String>{
          ...Platform.environment,
          'SIMS_TEST_SENTINEL': jsonEncode(sentinel),
          'SIMS_TEST_EXIT': '$processExitCode',
        },
      ).execute(
        _processRow(
          declaredBuildException: true,
          allowTargetUnavailable: true,
        ).copyWith(
          command: const <String>[
            'bash',
            '-c',
            r'''printf 'SIMS_RESULT_JSON=%s\n' "$SIMS_TEST_SENTINEL"; exit "$SIMS_TEST_EXIT"''',
          ],
        ),
      );

  Map<String, Object?> passSentinel({Object? evidence}) => <String, Object?>{
    'status': 'PASS',
    'assertionsAttempted': 1,
    'artifactPresent': true,
    'printOnly': false,
    'exitCode': 0,
    'artifactEvidence': ?evidence,
  };

  test(
    'PASS rejects blocker target-unavailable reason and zero proof',
    () async {
      final contradictory = <Map<String, Object?>>[
        <String, Object?>{
          'status': 'PASS',
          'assertionsAttempted': 1,
          'artifactPresent': true,
          'printOnly': false,
          'blocker': 'credentials',
        },
        <String, Object?>{
          'status': 'PASS',
          'assertionsAttempted': 1,
          'artifactPresent': true,
          'printOnly': false,
          'targetCapabilityAvailable': false,
        },
        <String, Object?>{
          'status': 'PASS',
          'assertionsAttempted': 1,
          'artifactPresent': true,
          'printOnly': false,
          'reason': targetUnavailableNaReason,
        },
        <String, Object?>{
          'status': 'PASS',
          'assertionsAttempted': 0,
          'artifactPresent': true,
          'printOnly': false,
        },
      ];

      for (final sentinel in contradictory) {
        final execution = await executeStructuredSentinel(sentinel);
        expect(execution.verdict.status, SimsVerdictStatus.fail);
        expect(execution.verdict.blocker, SimsBlockerKind.harness);
        expect(execution.verdict.detail, contains('Invalid structured result'));
      }
    },
  );

  test('N/A rejects nonzero exit and proof-bearing contradictions', () async {
    Map<String, Object?> sentinel({
      int attempts = 0,
      bool artifactPresent = false,
      bool printOnly = false,
    }) => <String, Object?>{
      'status': 'N/A',
      'assertionsAttempted': attempts,
      'artifactPresent': artifactPresent,
      'printOnly': printOnly,
      'blocker': 'targetUnavailable',
      'targetCapabilityAvailable': false,
      'reason': targetUnavailableNaReason,
    };

    for (final execution in <SimsCommandExecution>[
      await executeStructuredSentinel(sentinel(), processExitCode: 7),
      await executeStructuredSentinel(sentinel(attempts: 1)),
      await executeStructuredSentinel(sentinel(artifactPresent: true)),
      await executeStructuredSentinel(sentinel(printOnly: true)),
    ]) {
      expect(execution.verdict.status, SimsVerdictStatus.fail);
      expect(execution.verdict.blocker, SimsBlockerKind.harness);
    }
  });

  test('artifactPresent true alone cannot forge an artifact PASS', () async {
    final execution = await executeArtifactSentinel(passSentinel());

    expect(execution.verdict.status, SimsVerdictStatus.fail);
    expect(execution.verdict.detail, contains('path, SHA-256'));
  });

  test('artifact PASS rejects a missing evidence path', () async {
    final execution = await executeArtifactSentinel(
      passSentinel(
        evidence: <String, Object?>{
          'path': '${temporaryDirectory.path}/missing-proof.json',
          'sha256': _zeroDigest,
          'validatorIds': <String>['fixture.validator'],
        },
      ),
    );

    expect(execution.verdict.status, SimsVerdictStatus.fail);
    expect(execution.verdict.detail, contains('not a regular file'));
  });

  test('artifact PASS rejects a wrong digest', () async {
    final proof = File('${temporaryDirectory.path}/proof.json')
      ..writeAsStringSync('{"ok":true}');
    final execution = await executeArtifactSentinel(
      passSentinel(
        evidence: <String, Object?>{
          'path': proof.path,
          'sha256': _zeroDigest,
          'validatorIds': <String>['fixture.validator'],
        },
      ),
    );

    expect(execution.verdict.status, SimsVerdictStatus.fail);
    expect(execution.verdict.detail, contains('SHA-256 mismatch'));
  });

  test('artifact PASS rejects validator IDs not bound to the row', () async {
    final proof = File('${temporaryDirectory.path}/proof.json')
      ..writeAsStringSync('{"ok":true}');
    final execution = await executeArtifactSentinel(
      passSentinel(
        evidence: <String, Object?>{
          'path': proof.path,
          'sha256': sha256.convert(proof.readAsBytesSync()).toString(),
          'validatorIds': <String>['different.validator'],
        },
      ),
    );

    expect(execution.verdict.status, SimsVerdictStatus.fail);
    expect(execution.verdict.detail, contains('do not exactly match'));
  });

  test('valid durable evidence is verified and persisted on PASS', () async {
    final proof = File('${temporaryDirectory.path}/proof.json')
      ..writeAsStringSync('{"ok":true}');
    final digest = sha256.convert(proof.readAsBytesSync()).toString();
    final execution = await executeArtifactSentinel(
      passSentinel(
        evidence: <String, Object?>{
          'path': proof.path,
          'sha256': digest,
          'validatorIds': <String>['fixture.validator'],
        },
      ),
    );

    expect(execution.verdict.status, SimsVerdictStatus.pass);
    expect(execution.verdict.artifactEvidence, isNotNull);
    final canonicalPath = proof.resolveSymbolicLinksSync();
    expect(execution.verdict.artifactEvidence!.path, canonicalPath);
    expect(execution.verdict.artifactEvidence!.sha256Digest, digest);
    expect(execution.verdict.toJson()['artifactEvidence'], <String, Object?>{
      'path': canonicalPath,
      'sha256': digest,
      'validatorIds': <String>['fixture.validator'],
    });
    final roundTrip = SimsVerdict.fromJson(execution.verdict.toJson());
    expect(roundTrip.artifactEvidence!.sha256Digest, digest);
  });
}
