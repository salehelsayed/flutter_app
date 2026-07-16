import 'android_campaign_evidence_validation.dart';
import 'android_critical_performance_budget.dart';
import 'sims_runtime_protocol.dart';

export 'android_critical_performance_budget.dart';

const String androidCriticalPerformanceEvidenceSchema =
    'mknoon.sims.android-critical-performance.v1';
const String androidCriticalPerformanceArtifactValidatorId =
    'performance.device.runtime_budget_artifact';

AndroidCampaignEvidenceValidation validateAndroidCriticalPerformanceInvocation(
  SimsRuntimeInvocation invocation,
) {
  if (invocation.profileId != simsAndroidStandardProfileId) {
    return const AndroidCampaignEvidenceValidation.fail(
      'critical performance requires android.e2e.standard',
    );
  }
  if (invocation.scenarioId != simsAndroidCriticalPerformanceScenarioId) {
    return const AndroidCampaignEvidenceValidation.fail(
      'critical performance scenario ID is mismatched',
    );
  }
  if (invocation.role != simsPrimaryRole) {
    return const AndroidCampaignEvidenceValidation.fail(
      'critical performance requires the primary runtime role',
    );
  }
  final targetId = invocation.values['targetId'];
  if (targetId is! String || !_isSafeToken(targetId)) {
    return const AndroidCampaignEvidenceValidation.fail(
      'critical performance requires an explicit safe targetId',
    );
  }
  if (invocation.values['targetKind'] != 'physical') {
    return const AndroidCampaignEvidenceValidation.fail(
      'critical performance requires an ADB-verified physical target',
    );
  }
  if (!_isSha256(invocation.values['buildArtifactSha256'])) {
    return const AndroidCampaignEvidenceValidation.fail(
      'critical performance requires the prepared APK SHA-256',
    );
  }
  return const AndroidCampaignEvidenceValidation.pass();
}

/// Validates the app-produced result before a host adapter wraps it in
/// content-addressed [SimsArtifactEvidence].
///
/// The proof is deliberately bound to Android engine timings, the production
/// Go MethodChannel, an explicit physical target, and the centrally prepared
/// standard-profile APK. Host/fake measurements cannot satisfy this schema.
AndroidCampaignEvidenceValidation validateAndroidCriticalPerformanceEvidence(
  Map<String, Object?> artifact,
) {
  if (artifact['schema'] != androidCriticalPerformanceEvidenceSchema) {
    return const AndroidCampaignEvidenceValidation.fail(
      'performance evidence schema is unsupported',
    );
  }
  if (artifact['scenario'] != simsAndroidCriticalPerformanceScenarioId ||
      artifact['status'] != 'passed') {
    return const AndroidCampaignEvidenceValidation.fail(
      'performance evidence is not a passing critical scenario',
    );
  }
  if (artifact['platform'] != 'android' ||
      artifact['physicalTarget'] != true ||
      artifact['runtimeDispatched'] != true) {
    return const AndroidCampaignEvidenceValidation.fail(
      'performance evidence lacks the physical Android runtime boundary',
    );
  }
  final targetId = artifact['targetId'];
  if (targetId is! String || !_isSafeToken(targetId)) {
    return const AndroidCampaignEvidenceValidation.fail(
      'performance evidence targetId is invalid',
    );
  }

  final runtime = _object(artifact['runtime']);
  if (runtime == null ||
      runtime['profileId'] != simsAndroidStandardProfileId ||
      runtime['scenarioId'] != simsAndroidCriticalPerformanceScenarioId ||
      runtime['role'] != simsPrimaryRole ||
      !_isSafeToken(runtime['runId']) ||
      !_isSafeToken(runtime['nonce'])) {
    return const AndroidCampaignEvidenceValidation.fail(
      'performance evidence runtime tuple is invalid',
    );
  }

  final sharedArtifact = _object(artifact['sharedArtifact']);
  if (sharedArtifact == null ||
      sharedArtifact['profileId'] != simsAndroidStandardProfileId ||
      !_isSha256(sharedArtifact['sha256'])) {
    return const AndroidCampaignEvidenceValidation.fail(
      'performance evidence is not bound to the shared prepared APK',
    );
  }

  final measurements = _object(artifact['measurements']);
  final feed = _object(measurements?['feedScroll']);
  final bridge = _object(measurements?['goBridge']);
  final frameCount = _integer(feed?['frameCount']);
  final averageBuildMs = _number(feed?['averageBuildMs']);
  final p99BuildMs = _number(feed?['p99BuildMs']);
  final worstBuildMs = _number(feed?['worstBuildMs']);
  if (feed?['source'] != androidFrameTimingMeasurementSource ||
      frameCount == null ||
      frameCount <= 0 ||
      averageBuildMs == null ||
      p99BuildMs == null ||
      worstBuildMs == null ||
      averageBuildMs < 0 ||
      p99BuildMs < averageBuildMs ||
      worstBuildMs < p99BuildMs) {
    return const AndroidCampaignEvidenceValidation.fail(
      'performance evidence has invalid Android frame measurements',
    );
  }

  final bridgeSamples = _integer(bridge?['sampleCount']);
  final bridgeP99Ms = _number(bridge?['p99Ms']);
  if (bridge?['source'] != androidGoBridgeMeasurementSource ||
      bridge?['command'] != 'node:status' ||
      bridge?['stateMutation'] != false ||
      bridgeSamples == null ||
      bridgeSamples < androidBridgeMinimumSamples ||
      bridgeP99Ms == null ||
      bridgeP99Ms < 0) {
    return const AndroidCampaignEvidenceValidation.fail(
      'performance evidence has invalid native bridge measurements',
    );
  }

  final assertions = artifact['budgetAssertions'];
  if (artifact['assertionsAttempted'] !=
          androidCriticalPerformanceAssertionCount ||
      assertions is! List) {
    return const AndroidCampaignEvidenceValidation.fail(
      'performance evidence did not attempt all four budgets',
    );
  }
  final assertionById = <String, Map<String, Object?>>{};
  for (final value in assertions) {
    final assertion = _object(value);
    final id = assertion?['id'];
    if (assertion == null || id is! String || assertionById.containsKey(id)) {
      return const AndroidCampaignEvidenceValidation.fail(
        'performance budget assertions are malformed or duplicated',
      );
    }
    assertionById[id] = assertion;
  }

  final expected = <String, ({double observed, double budget, String source})>{
    feedAverageBuildAssertionId: (
      observed: averageBuildMs,
      budget: androidFeedAverageBuildBudgetMs,
      source: androidFrameTimingMeasurementSource,
    ),
    feedP99BuildAssertionId: (
      observed: p99BuildMs,
      budget: androidFeedP99BuildBudgetMs,
      source: androidFrameTimingMeasurementSource,
    ),
    feedWorstBuildAssertionId: (
      observed: worstBuildMs,
      budget: androidFeedWorstBuildBudgetMs,
      source: androidFrameTimingMeasurementSource,
    ),
    bridgeP99AssertionId: (
      observed: bridgeP99Ms,
      budget: androidBridgeP99BudgetMs,
      source: androidGoBridgeMeasurementSource,
    ),
  };
  if (assertionById.length != expected.length) {
    return const AndroidCampaignEvidenceValidation.fail(
      'performance evidence has an incomplete budget assertion set',
    );
  }
  for (final entry in expected.entries) {
    final assertion = assertionById[entry.key];
    if (assertion == null ||
        assertion['passed'] != true ||
        assertion['comparison'] != 'lessThan' ||
        assertion['source'] != entry.value.source ||
        _number(assertion['observedMs']) != entry.value.observed ||
        _number(assertion['budgetMs']) != entry.value.budget ||
        entry.value.observed >= entry.value.budget) {
      return AndroidCampaignEvidenceValidation.fail(
        'performance budget ${entry.key} is missing, mismatched, or failed',
      );
    }
  }

  return const AndroidCampaignEvidenceValidation.pass();
}

Map<String, Object?> androidCriticalPerformanceDurablePayload(
  Map<String, Object?> runtimeProof,
) => validatedAndroidRuntimeProofPayload(
  runtimeProof: runtimeProof,
  validate: validateAndroidCriticalPerformanceEvidence,
);

AndroidCampaignEvidenceValidation
validateAndroidCriticalPerformanceDurableArtifact(
  Map<String, Object?> artifact,
) => validateDurableAndroidCampaignArtifact(
  artifact: artifact,
  capabilityId: simsAndroidCriticalPerformanceScenarioId,
  validatorId: androidCriticalPerformanceArtifactValidatorId,
  validateRuntimeProof: validateAndroidCriticalPerformanceEvidence,
);

Map<String, Object?>? _object(Object? value) {
  if (value is! Map) return null;
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

int? _integer(Object? value) => value is int ? value : null;

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _isSafeToken(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= 160 &&
    RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);
