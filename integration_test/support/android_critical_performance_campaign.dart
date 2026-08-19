import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_support/canonical_runtime_device_test_lease.dart';
import '../feed_performance_test.dart';
import 'android_critical_performance_evidence.dart';
import 'sims_runtime_protocol.dart';

const int _bridgeWarmupSamples = 10;
const int _bridgeMeasuredSamples = 200;

/// Runs the device-critical performance proof from the universal sims APK.
///
/// Unlike the historical `PERF_TARGET` and `BENCHMARK` entrypoints, this is a
/// callable runtime action. It therefore reuses `android.e2e.standard` and
/// cannot trigger a scenario-specific rebuild. The two measurements cross
/// boundaries that host tests cannot: real engine FrameTiming on Android and
/// the production Dart -> native Go MethodChannel.
Future<Map<String, Object?>> runAndroidCriticalPerformanceCampaign(
  WidgetTester tester,
  SimsRuntimeInvocation invocation,
) async {
  final invocationValidation = validateAndroidCriticalPerformanceInvocation(
    invocation,
  );
  expect(invocationValidation.ok, isTrue, reason: invocationValidation.detail);
  expect(
    Platform.isAndroid,
    isTrue,
    reason: 'performance.device.critical is an Android device proof',
  );

  final feed = await runFeedScrollCriticalPerformance(tester);
  final bridge = await _measureProductionGoBridge();

  final assertions = <Map<String, Object?>>[
    _budgetAssertion(
      id: feedAverageBuildAssertionId,
      source: androidFrameTimingMeasurementSource,
      observedMs: feed.averageBuildMs,
      budgetMs: androidFeedAverageBuildBudgetMs,
    ),
    _budgetAssertion(
      id: feedP99BuildAssertionId,
      source: androidFrameTimingMeasurementSource,
      observedMs: feed.p99BuildMs,
      budgetMs: androidFeedP99BuildBudgetMs,
    ),
    _budgetAssertion(
      id: feedWorstBuildAssertionId,
      source: androidFrameTimingMeasurementSource,
      observedMs: feed.worstBuildMs,
      budgetMs: androidFeedWorstBuildBudgetMs,
    ),
    _budgetAssertion(
      id: bridgeP99AssertionId,
      source: androidGoBridgeMeasurementSource,
      observedMs: bridge.p99Ms,
      budgetMs: androidBridgeP99BudgetMs,
    ),
  ];
  for (final assertion in assertions) {
    expect(
      assertion['passed'],
      isTrue,
      reason:
          '${assertion['id']} observed ${assertion['observedMs']}ms, '
          'budget ${assertion['budgetMs']}ms',
    );
  }

  final artifact = <String, Object?>{
    'schema': androidCriticalPerformanceEvidenceSchema,
    'scenario': simsAndroidCriticalPerformanceScenarioId,
    'status': 'passed',
    'platform': 'android',
    'physicalTarget': true,
    'targetId': invocation.values['targetId'],
    'runtimeDispatched': true,
    'runtime': <String, Object?>{
      'profileId': invocation.profileId,
      'scenarioId': invocation.scenarioId,
      'role': invocation.role,
      'runId': invocation.runId,
      'nonce': invocation.nonce,
    },
    'sharedArtifact': <String, Object?>{
      'profileId': invocation.profileId,
      'sha256': invocation.values['buildArtifactSha256'],
    },
    'measurements': <String, Object?>{
      'feedScroll': <String, Object?>{
        'source': androidFrameTimingMeasurementSource,
        ...feed.toJson(),
      },
      'goBridge': <String, Object?>{
        'source': androidGoBridgeMeasurementSource,
        'command': 'node:status',
        'stateMutation': false,
        'sampleCount': bridge.sampleCount,
        'p50Ms': bridge.p50Ms,
        'p95Ms': bridge.p95Ms,
        'p99Ms': bridge.p99Ms,
      },
    },
    'assertionsAttempted': assertions.length,
    'budgetAssertions': assertions,
  };
  final evidenceValidation = validateAndroidCriticalPerformanceEvidence(
    artifact,
  );
  expect(evidenceValidation.ok, isTrue, reason: evidenceValidation.detail);
  return artifact;
}

Map<String, Object?> _budgetAssertion({
  required String id,
  required String source,
  required double observedMs,
  required double budgetMs,
}) => <String, Object?>{
  'id': id,
  'source': source,
  'comparison': 'lessThan',
  'observedMs': observedMs,
  'budgetMs': budgetMs,
  'passed': observedMs < budgetMs,
};

Future<_BridgePerformanceResult> _measureProductionGoBridge() async {
  // Self-guarded here rather than at `sims_dispatcher.dart`, which is the
  // shared prebuilt-APK entrypoint for EVERY sims scenario. Only this one
  // crosses the Go bridge; leasing the dispatcher would attach the Go runtime
  // and open the probe database for `android.voice_recorder_native_smoke` too,
  // which needs neither.
  final runtimeLease = CanonicalRuntimeDeviceTestLease(
    binding: 'android-critical-performance-device-test',
  );
  await runtimeLease.acquire();
  final bridge = GoBridgeClient();
  try {
    await bridge.initialize();
    _requireSuccessfulNodeStatus(await bridge.send(_nodeStatusCommand));

    for (var index = 0; index < _bridgeWarmupSamples; index += 1) {
      _requireSuccessfulNodeStatus(await bridge.send(_nodeStatusCommand));
    }

    final timingsMs = <double>[];
    for (var index = 0; index < _bridgeMeasuredSamples; index += 1) {
      final stopwatch = Stopwatch()..start();
      _requireSuccessfulNodeStatus(await bridge.send(_nodeStatusCommand));
      stopwatch.stop();
      timingsMs.add(stopwatch.elapsedMicroseconds / 1000.0);
    }
    timingsMs.sort();
    return _BridgePerformanceResult(
      sampleCount: timingsMs.length,
      p50Ms: _percentile(timingsMs, 50),
      p95Ms: _percentile(timingsMs, 95),
      p99Ms: _percentile(timingsMs, 99),
    );
  } finally {
    bridge.dispose();
    await runtimeLease.release();
  }
}

const String _nodeStatusCommand = '{"cmd":"node:status","payload":{}}';

Map<String, Object?> _decodeBridgeObject(String encoded) {
  final decoded = jsonDecode(encoded);
  if (decoded is! Map) {
    throw const FormatException('Go bridge response root must be an object');
  }
  return decoded.map<String, Object?>((key, value) => MapEntry('$key', value));
}

void _requireSuccessfulNodeStatus(String encoded) {
  final response = _decodeBridgeObject(encoded);
  if (response['ok'] != true) {
    throw StateError('production node:status failed: $response');
  }
}

double _percentile(List<double> sorted, int percentile) {
  if (sorted.isEmpty) throw StateError('performance sample is empty');
  final rank = (percentile / 100) * (sorted.length - 1);
  final lower = rank.floor();
  final upper = rank.ceil();
  if (lower == upper) return sorted[lower];
  final fraction = rank - lower;
  return sorted[lower] + ((sorted[upper] - sorted[lower]) * fraction);
}

final class _BridgePerformanceResult {
  const _BridgePerformanceResult({
    required this.sampleCount,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
  });

  final int sampleCount;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
}
