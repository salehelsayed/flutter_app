import '../../tool/sims/build_cache.dart';
import '../support/media_content_oracle.dart';
import 'contact_transfer_native_evidence.dart';

Future<List<String>> validateCandidatePlatformContractObservations(
  ContactTransferNativeEvidence evidence, {
  required String expectedArtifactSha256,
}) async {
  final failures = <String>[];
  final observed = evidence.observations;
  final artifact = await fingerprintMediaFile(
    evidence.file(observed['signedArtifactPath']),
  );
  final attestation = BuildAttestation.fromJson(
    await evidence.json(observed['buildAttestationPath']),
  );
  if (artifact.sha256Hex != expectedArtifactSha256 ||
      attestation.artifactDigest != artifact.sha256Hex ||
      observed['installedArtifactSha256'] != artifact.sha256Hex) {
    failures.add(
      'actual signed artifact, central attestation and installed candidate must match independently pinned exact bytes',
    );
  }
  final extracted = await evidence.json(observed['mergedPlatformContractPath']);
  final expected = await evidence.json(
    observed['expectedPlatformContractPath'],
  );
  if (extracted['artifactSha256'] != artifact.sha256Hex ||
      expected['candidateSource'] != evidence.receipt['candidateSource'] ||
      extracted['signatureVerified'] != true ||
      extracted['profileAllowsInstallation'] != true) {
    failures.add(
      'merged signed artifact contract/signature/provisioning required; source manifests do not substitute',
    );
  }
  bool sameValue(Object? left, Object? right) {
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every(
            (key) => right.containsKey(key) && sameValue(left[key], right[key]),
          );
    }
    if (left is List && right is List) {
      return left.length == right.length &&
          List.generate(
            left.length,
            (index) => index,
          ).every((index) => sameValue(left[index], right[index]));
    }
    return left == right;
  }

  for (final section in ['permissions', 'entitlements', 'usageDescriptions']) {
    final actual = journeyGapMap(extracted[section]);
    final expectedSection = journeyGapMap(expected[section]);
    if (!sameValue(actual, expectedSection)) {
      failures.add(
        'whole merged $section differs from exact candidate contract (extra, missing or changed nested values)',
      );
    }
  }
  if (journeyGapMap(expected['permissions']).isEmpty &&
      journeyGapMap(expected['entitlements']).isEmpty) {
    failures.add('nonempty platform-specific expected contract required');
  }
  final cases = journeyGapRows(observed['runtimeCases']);
  if (!cases.map((row) => row['case']).toSet().containsAll([
    'first_unlock',
    'permission_failure_recovery',
  ])) {
    failures.add(
      'actual first-unlock and supported permission/failure-recovery runtime cases required',
    );
  }
  for (final row in cases) {
    if (row['installedArtifactSha256'] != artifact.sha256Hex ||
        row['runId'] != evidence.receipt['runId'] ||
        row['nativeBoundaryObserved'] != true ||
        row['truthfulUiState'] != true ||
        row['identityPreservedAfterReopen'] != true ||
        row['recoveredUsable'] != true ||
        !evidence.files.containsKey(row['nativeObservationPath'])) {
      failures.add(
        '${row['case']}: exact installed signed candidate must cross the actual OS boundary and recover usable state',
      );
    }
  }
  return failures;
}

Future<void> main(List<String> arguments) async {
  final failures = <String>[];
  var evaluated = false;
  if (arguments.contains('--receipt')) {
    try {
      String option(String name) {
        final index = arguments.indexOf(name);
        if (index < 0 || index + 1 >= arguments.length) {
          throw FormatException('missing $name');
        }
        return arguments[index + 1];
      }

      final evidence = await ContactTransferNativeEvidence.load(
        arguments,
        journeyId: 'RELEASE-004',
        requiredKinds: [
          'exact-signed-artifact',
          'build-attestation',
          'merged-signed-platform-contract',
          'native-first-unlock',
          'native-failure-recovery',
        ],
      );
      evaluated = true;
      failures.addAll(
        await validateCandidatePlatformContractObservations(
          evidence,
          expectedArtifactSha256: option('--candidate-artifact-sha256'),
        ),
      );
    } on ContactTransferCaptureUnavailable {
      // Capture absence is NOT RUN; it is not an app failure.
    } on Object {
      failures.add(
        'RELEASE-004 observations are incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'RELEASE-004',
    ids: ['RG-001', 'RG-002', 'RELEASE-004'],
    captureGap:
        'No existing capture owner extracts and independently verifies this exact merged signed candidate contract plus supported actual first-unlock/permission-failure recovery; source manifests/fake gateways are insufficient.',
    prerequisites: [
      'Independently pin --candidate-artifact-sha256, exact candidate source/run, central attestation and the actual installed signed artifact.',
      'Future fapp captures verified signature/provisioning and merged permissions/entitlements/usage strings from that artifact, not source files.',
      'Capture available-platform actual first-unlock/failure-recovery boundaries, truthful user-facing state and preserved reopened identity; unavailable platform/hardware legs are N/A by project policy.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
