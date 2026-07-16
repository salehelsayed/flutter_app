import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_critical_performance_evidence.dart';
import '../../integration_test/support/sims_runtime_protocol.dart';
import '../../tool/sims/artifact_evidence.dart';

const _artifactDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

SimsRuntimeInvocation _invocation({
  String profileId = simsAndroidStandardProfileId,
  Map<String, Object?>? values,
}) => SimsRuntimeInvocation(
  schema: simsRuntimeConfigSchema,
  profileId: profileId,
  scenarioId: simsAndroidCriticalPerformanceScenarioId,
  role: simsPrimaryRole,
  runId: 'run-performance-1',
  nonce: 'nonce-performance-1',
  values:
      values ??
      const <String, Object?>{
        'targetId': 'pixel-physical',
        'targetKind': 'physical',
        'buildArtifactSha256': _artifactDigest,
      },
);

Map<String, Object?> _evidence() => <String, Object?>{
  'schema': androidCriticalPerformanceEvidenceSchema,
  'scenario': simsAndroidCriticalPerformanceScenarioId,
  'status': 'passed',
  'platform': 'android',
  'physicalTarget': true,
  'targetId': 'pixel-physical',
  'runtimeDispatched': true,
  'runtime': <String, Object?>{
    'profileId': simsAndroidStandardProfileId,
    'scenarioId': simsAndroidCriticalPerformanceScenarioId,
    'role': simsPrimaryRole,
    'runId': 'run-performance-1',
    'nonce': 'nonce-performance-1',
  },
  'sharedArtifact': <String, Object?>{
    'profileId': simsAndroidStandardProfileId,
    'sha256': _artifactDigest,
  },
  'measurements': <String, Object?>{
    'feedScroll': <String, Object?>{
      'source': androidFrameTimingMeasurementSource,
      'frameCount': 60,
      'averageBuildMs': 4.0,
      'p99BuildMs': 10.0,
      'worstBuildMs': 20.0,
    },
    'goBridge': <String, Object?>{
      'source': androidGoBridgeMeasurementSource,
      'command': 'node:status',
      'stateMutation': false,
      'sampleCount': 200,
      'p50Ms': 1.0,
      'p95Ms': 2.0,
      'p99Ms': 3.0,
    },
  },
  'assertionsAttempted': androidCriticalPerformanceAssertionCount,
  'budgetAssertions': <Map<String, Object?>>[
    <String, Object?>{
      'id': feedAverageBuildAssertionId,
      'source': androidFrameTimingMeasurementSource,
      'comparison': 'lessThan',
      'observedMs': 4.0,
      'budgetMs': androidFeedAverageBuildBudgetMs,
      'passed': true,
    },
    <String, Object?>{
      'id': feedP99BuildAssertionId,
      'source': androidFrameTimingMeasurementSource,
      'comparison': 'lessThan',
      'observedMs': 10.0,
      'budgetMs': androidFeedP99BuildBudgetMs,
      'passed': true,
    },
    <String, Object?>{
      'id': feedWorstBuildAssertionId,
      'source': androidFrameTimingMeasurementSource,
      'comparison': 'lessThan',
      'observedMs': 20.0,
      'budgetMs': androidFeedWorstBuildBudgetMs,
      'passed': true,
    },
    <String, Object?>{
      'id': bridgeP99AssertionId,
      'source': androidGoBridgeMeasurementSource,
      'comparison': 'lessThan',
      'observedMs': 3.0,
      'budgetMs': androidBridgeP99BudgetMs,
      'passed': true,
    },
  ],
};

void main() {
  test('runtime invocation binds physical target and shared APK digest', () {
    expect(
      validateAndroidCriticalPerformanceInvocation(_invocation()).ok,
      isTrue,
    );

    expect(
      validateAndroidCriticalPerformanceInvocation(
        _invocation(
          values: const <String, Object?>{
            'targetId': 'pixel-physical',
            'targetKind': 'emulator',
            'buildArtifactSha256': _artifactDigest,
          },
        ),
      ).ok,
      isFalse,
    );
    expect(
      validateAndroidCriticalPerformanceInvocation(
        _invocation(profileId: 'android.production_fcm'),
      ).ok,
      isFalse,
    );
  });

  test('real Android frame and Go bridge budgets form valid evidence', () {
    expect(validateAndroidCriticalPerformanceEvidence(_evidence()).ok, isTrue);
  });

  test('performance result is durable and bound to its exact validator', () {
    final directory = Directory.systemTemp.createTempSync(
      'sims-performance-evidence-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final evidence = writeSimsArtifactEvidenceSync(
      directory: directory,
      capabilityId: simsAndroidCriticalPerformanceScenarioId,
      validatorIds: const <String>[
        androidCriticalPerformanceArtifactValidatorId,
      ],
      payload: androidCriticalPerformanceDurablePayload(_evidence()),
    );

    final durableJson = jsonDecode(File(evidence.path).readAsStringSync());
    expect(durableJson, isA<Map>());
    expect(
      validateAndroidCriticalPerformanceDurableArtifact(
        (durableJson as Map).map<String, Object?>(
          (key, value) => MapEntry('$key', value),
        ),
      ).ok,
      isTrue,
    );

    expect(
      auditSimsArtifactEvidence(
        evidence: evidence,
        expectedValidatorIds: const <String>[
          androidCriticalPerformanceArtifactValidatorId,
        ],
      ).isValid,
      isTrue,
    );
    expect(
      auditSimsArtifactEvidence(
        evidence: evidence,
        expectedValidatorIds: const <String>['wrong.validator'],
      ).isValid,
      isFalse,
    );
  });

  test('missing, slow, fake, or unattested measurements fail closed', () {
    final missingAssertion = _evidence();
    (missingAssertion['budgetAssertions']! as List).removeLast();
    expect(
      validateAndroidCriticalPerformanceEvidence(missingAssertion).ok,
      isFalse,
    );

    final slowBridge = _evidence();
    final measurements = slowBridge['measurements']! as Map<String, Object?>;
    final bridge = measurements['goBridge']! as Map<String, Object?>;
    bridge['p99Ms'] = 75.0;
    final assertions = slowBridge['budgetAssertions']! as List;
    final bridgeAssertion = assertions.last as Map<String, Object?>;
    bridgeAssertion['observedMs'] = 75.0;
    bridgeAssertion['passed'] = false;
    expect(validateAndroidCriticalPerformanceEvidence(slowBridge).ok, isFalse);

    final fakeSource = _evidence();
    final fakeMeasurements =
        fakeSource['measurements']! as Map<String, Object?>;
    (fakeMeasurements['feedScroll']! as Map<String, Object?>)['source'] =
        'host.fake.FrameTiming';
    expect(validateAndroidCriticalPerformanceEvidence(fakeSource).ok, isFalse);

    final unattested = _evidence();
    (unattested['sharedArtifact']! as Map<String, Object?>)['sha256'] =
        'not-a-digest';
    expect(validateAndroidCriticalPerformanceEvidence(unattested).ok, isFalse);
  });
}
