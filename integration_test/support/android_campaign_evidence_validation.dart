final class AndroidCampaignEvidenceValidation {
  const AndroidCampaignEvidenceValidation._(this.ok, this.detail);

  const AndroidCampaignEvidenceValidation.pass()
    : this._(true, 'artifact evidence is valid');

  const AndroidCampaignEvidenceValidation.fail(String detail)
    : this._(false, detail);

  final bool ok;
  final String detail;
}

typedef AndroidRuntimeProofValidator =
    AndroidCampaignEvidenceValidation Function(Map<String, Object?> proof);

/// Preserves the app-produced schema below the generic durable proof envelope.
///
/// `writeSimsArtifactEvidenceSync` owns the top-level `schema`, capability ID,
/// and validator IDs, so placing the runtime proof at the top level would
/// overwrite its scenario-specific schema.
Map<String, Object?> validatedAndroidRuntimeProofPayload({
  required Map<String, Object?> runtimeProof,
  required AndroidRuntimeProofValidator validate,
}) {
  final validation = validate(runtimeProof);
  if (!validation.ok) {
    throw FormatException(validation.detail);
  }
  return <String, Object?>{'runtimeProof': runtimeProof};
}

AndroidCampaignEvidenceValidation validateDurableAndroidCampaignArtifact({
  required Map<String, Object?> artifact,
  required String capabilityId,
  required String validatorId,
  required AndroidRuntimeProofValidator validateRuntimeProof,
}) {
  final validators = artifact['validatorIds'];
  if (artifact['schema'] != 'mknoon.sims.proof.v1' ||
      artifact['capabilityId'] != capabilityId ||
      validators is! List ||
      validators.length != 1 ||
      validators.single != validatorId) {
    return const AndroidCampaignEvidenceValidation.fail(
      'durable artifact envelope is not bound to the expected capability and validator',
    );
  }
  final value = artifact['runtimeProof'];
  if (value is! Map) {
    return const AndroidCampaignEvidenceValidation.fail(
      'durable artifact is missing its runtime proof',
    );
  }
  return validateRuntimeProof(
    value.map<String, Object?>((key, item) => MapEntry('$key', item)),
  );
}
