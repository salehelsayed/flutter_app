import 'android_campaign_evidence_validation.dart';

const String androidDirectMediaBlobCustodyScenarioId =
    'android.direct_media_blob_custody';
const String androidDirectMediaBlobCustodyBuildProfileId =
    'android.e2e.direct_media_custody';
const String androidDirectMediaBlobCustodyArtifactValidatorId =
    'validateDirectMediaBlobCustodyArtifact';
const int androidDirectMediaBlobCustodyEvidenceSchemaVersion = 1;

const Set<String> _runtimeEvidenceKeys = <String>{
  'schemaVersion',
  'scenarioId',
  'senderRestartObserved',
  'attachmentCount',
  'preparedCiphertextSha256',
  'reopenedCiphertextSha256',
  'receiverCiphertextSha256',
  'receiverReopenSha256',
  'receiverPlaintextSha256',
  'receiverReopenPlaintextSha256',
  'strictCommitmentVerified',
  'envelopeExpiryWithinBlobBound',
  'ackSourcePinned',
  'relayProtectedAbsentAfterAck',
  'fixtureIdentitySha256',
};

/// Validates the non-secret device observations required by Plan 347.
///
/// The exact-key check is intentional. A device action cannot smuggle local
/// paths, relay IDs, message/blob IDs, keys, or nonces into the durable proof.
/// The fixture and ciphertext are represented only by lowercase SHA-256
/// digests.
AndroidCampaignEvidenceValidation validateAndroidDirectMediaBlobCustodyEvidence(
  Map<String, Object?> evidence,
) {
  if (!_sameKeys(evidence.keys.toSet(), _runtimeEvidenceKeys)) {
    return const AndroidCampaignEvidenceValidation.fail(
      'direct-media custody evidence must use the exact non-secret schema',
    );
  }
  if (evidence['schemaVersion'] !=
          androidDirectMediaBlobCustodyEvidenceSchemaVersion ||
      evidence['scenarioId'] != androidDirectMediaBlobCustodyScenarioId) {
    return const AndroidCampaignEvidenceValidation.fail(
      'direct-media custody evidence has the wrong schema or scenario',
    );
  }

  final attachmentCount = evidence['attachmentCount'];
  if (attachmentCount is! int || attachmentCount <= 0) {
    return const AndroidCampaignEvidenceValidation.fail(
      'direct-media custody evidence requires a positive attachment count',
    );
  }

  for (final field in const <String>[
    'senderRestartObserved',
    'strictCommitmentVerified',
    'envelopeExpiryWithinBlobBound',
    'ackSourcePinned',
    'relayProtectedAbsentAfterAck',
  ]) {
    if (evidence[field] != true) {
      return AndroidCampaignEvidenceValidation.fail(
        'direct-media custody evidence requires $field=true',
      );
    }
  }

  final ciphertextDigests = <Object?>[
    evidence['preparedCiphertextSha256'],
    evidence['reopenedCiphertextSha256'],
    evidence['receiverCiphertextSha256'],
    evidence['receiverReopenSha256'],
  ];
  if (ciphertextDigests.any((digest) => !_isLowercaseSha256(digest)) ||
      ciphertextDigests.toSet().length != 1) {
    return const AndroidCampaignEvidenceValidation.fail(
      'prepared, reopened, received, and receiver-reopened ciphertext hashes '
      'must be one exact lowercase SHA-256 value',
    );
  }
  final plaintextDigests = <Object?>[
    evidence['receiverPlaintextSha256'],
    evidence['receiverReopenPlaintextSha256'],
  ];
  if (plaintextDigests.any((digest) => !_isLowercaseSha256(digest)) ||
      plaintextDigests.toSet().length != 1) {
    return const AndroidCampaignEvidenceValidation.fail(
      'receiver committed and reopened plaintext hashes must match exactly',
    );
  }
  if (!_isLowercaseSha256(evidence['fixtureIdentitySha256'])) {
    return const AndroidCampaignEvidenceValidation.fail(
      'fixture identity must be represented by lowercase SHA-256 only',
    );
  }

  return const AndroidCampaignEvidenceValidation.pass();
}

AndroidCampaignEvidenceValidation
validateAndroidDirectMediaBlobCustodyDurableArtifact(
  Map<String, Object?> artifact,
) => validateDurableAndroidCampaignArtifact(
  artifact: artifact,
  capabilityId: androidDirectMediaBlobCustodyScenarioId,
  validatorId: androidDirectMediaBlobCustodyArtifactValidatorId,
  validateRuntimeProof: validateAndroidDirectMediaBlobCustodyEvidence,
);

Map<String, Object?> androidDirectMediaBlobCustodyDurablePayload(
  Map<String, Object?> runtimeEvidence,
) => validatedAndroidRuntimeProofPayload(
  runtimeProof: runtimeEvidence,
  validate: validateAndroidDirectMediaBlobCustodyEvidence,
);

bool _sameKeys(Set<String> actual, Set<String> expected) =>
    actual.length == expected.length && actual.containsAll(expected);

bool _isLowercaseSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
