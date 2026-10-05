import '../../tool/sims/artifact_evidence.dart';

/// Classifies a production journey result for the SIMS executor.
///
/// SIMS accepts FAIL only with a blocker classification; without one, a real
/// journey failure is rejected as an invalid harness result and its cause is
/// hidden. Production journeys own their assertions, so FAIL is `test`.
Map<String, Object?> withProductionFailureBlocker(
  Map<String, Object?> result,
) => <String, Object?>{
  ...result,
  if (result['status'] == 'FAIL') 'blocker': 'test',
};

/// Standard production journey result, already classified.
Map<String, Object?> productionSimsResult({
  required bool passed,
  required int assertionsAttempted,
  required String detail,
  SimsArtifactEvidence? evidence,
}) => withProductionFailureBlocker(<String, Object?>{
  'status': passed ? 'PASS' : 'FAIL',
  'assertionsAttempted': assertionsAttempted,
  'artifactPresent': passed,
  'printOnly': false,
  'exitCode': passed ? 0 : 1,
  'detail': detail,
  if (evidence != null) 'artifactEvidence': evidence.toJson(),
});
