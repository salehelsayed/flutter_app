import '../../tool/sims/build_cache.dart';
import '../support/media_content_oracle.dart';
import 'contact_transfer_native_evidence.dart';

Future<List<String>> validateSignedUpgradePreservationObservations(
  ContactTransferNativeEvidence evidence, {
  required String publishedSource,
  required String publishedArtifactSha256,
  required String candidateArtifactSha256,
}) async {
  final failures = <String>[];
  final observed = evidence.observations;
  final previous = await fingerprintMediaFile(
    evidence.file(observed['publishedArtifactPath']),
  );
  final candidate = await fingerprintMediaFile(
    evidence.file(observed['candidateArtifactPath']),
  );
  final attestation = BuildAttestation.fromJson(
    await evidence.json(observed['candidateAttestationPath']),
  );
  final provenance = await evidence.json(observed['publishedProvenancePath']);
  if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(publishedSource) ||
      previous.sha256Hex != publishedArtifactSha256 ||
      candidate.sha256Hex != candidateArtifactSha256 ||
      previous.sha256Hex == candidate.sha256Hex ||
      attestation.artifactDigest != candidate.sha256Hex ||
      provenance['publishedSource'] != publishedSource ||
      provenance['artifactSha256'] != previous.sha256Hex ||
      provenance['publishedReleaseIdentity'] is! String ||
      (provenance['publishedReleaseIdentity'] as String).isEmpty) {
    failures.add(
      'actual independently pinned previous-published and exact candidate artifact bytes/identities required',
    );
  }
  final signing = await evidence.json(observed['signingVerificationPath']);
  if (signing['publishedArtifactSha256'] != previous.sha256Hex ||
      signing['candidateArtifactSha256'] != candidate.sha256Hex ||
      signing['upgradeSignatureCompatible'] != true ||
      signing['candidateSignatureValid'] != true ||
      signing['publishedSignatureValid'] != true ||
      observed['installMode'] != 'in_place_upgrade' ||
      observed['uninstallOrDataClearCount'] != 0) {
    failures.add(
      'actual compatible signed in-place upgrade required; version names or source builds are insufficient',
    );
  }
  final before = await evidence.json(observed['beforeUpgradeStatePath']);
  final after = await evidence.json(observed['afterUpgradeReopenStatePath']);
  for (final key in [
    'identityPeerId',
    'identityKeySha256',
    'contactsSha256',
    'groupsSha256',
    'directHistorySha256',
    'groupHistorySha256',
    'unreadStateSha256',
    'trustStateSha256',
    'quietRecoveryMetadataSha256',
  ]) {
    if (before[key] is! String ||
        (before[key] as String).isEmpty ||
        before[key] != after[key] ||
        key.endsWith('Sha256') &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch('${before[key]}')) {
      failures.add('$key must survive actual signed upgrade and cold reopen');
    }
  }
  for (final row in journeyGapRows(observed['retainedMedia'])) {
    final original = await fingerprintMediaFile(
      evidence.file(row['beforeFullFilePath']),
    );
    final upgraded = await fingerprintMediaFile(
      evidence.file(row['afterFullFilePath']),
    );
    if (!original.sameBytes(upgraded) ||
        row['nativeOpenAfterUpgrade'] != true) {
      failures.add(
        'retained full media must preserve exact bytes and native usability after upgrade',
      );
    }
  }
  if (journeyGapRows(observed['retainedMedia']).isEmpty) {
    failures.add('retained full media observations required');
  }
  final exchanges = journeyGapRows(observed['oldNewExchanges']);
  if (exchanges.length != 2 ||
      !exchanges.map((row) => row['direction']).toSet().containsAll([
        'old_to_new',
        'new_to_old',
      ]) ||
      exchanges.any(
        (row) =>
            row['sentText'] != row['receivedText'] ||
            (row['sentText'] as String).isEmpty ||
            row['receivedCountAfterReopen'] != 1 ||
            row['oldArtifactSha256'] != previous.sha256Hex ||
            row['newArtifactSha256'] != candidate.sha256Hex,
      )) {
    failures.add(
      'normal actual old/new signed peers must exchange exact first content both ways and retain it once',
    );
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
        journeyId: 'RG-001',
        requiredKinds: [
          'actual-published-artifact',
          'exact-signed-candidate',
          'published-release-provenance',
          'signature-verification',
          'upgrade-before-after',
          'retained-full-media',
          'old-new-peer-exchange',
        ],
      );
      evaluated = true;
      failures.addAll(
        await validateSignedUpgradePreservationObservations(
          evidence,
          publishedSource: option('--published-source'),
          publishedArtifactSha256: option('--published-artifact-sha256'),
          candidateArtifactSha256: option('--candidate-artifact-sha256'),
        ),
      );
    } on ContactTransferCaptureUnavailable {
      // Capture absence is NOT RUN; it is not an app failure.
    } on Object {
      failures.add(
        'RG-001 observations are incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'RG-001',
    ids: ['RG-001'],
    captureGap:
        'No existing native previous-published -> newer signed-candidate preservation/interoperability capture owner. AndroidInstallOverGuard admits only same-version restoration and cannot provide this upgrade.',
    prerequisites: [
      'Provide actual previous-published signed artifact/release provenance and exact signed candidate; independently pin --published-source, --published-artifact-sha256 and --candidate-artifact-sha256.',
      'Future fapp performs a real in-place upgrade retaining account/keys/contacts/groups/history/unread/trust/quiet metadata/full media, then ordinary old/new first-message exchange both ways.',
      'Central BuildAttestation and full-file digests are checked but do not prove signing, installed runtime or published identity by themselves; no version-name/source-only pass.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
