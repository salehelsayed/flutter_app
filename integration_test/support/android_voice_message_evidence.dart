import 'android_campaign_evidence_validation.dart';
import 'sims_runtime_protocol.dart';

const String androidVoiceMessageEvidenceSchema =
    'mknoon.sims.android-voice-message-e2e.v1';
const String androidVoiceMessageArtifactValidatorId =
    'validateVoiceMessageArtifact';

/// Validates one role's runtime envelope before any microphone, identity, or
/// transport state is changed.
///
/// This contract intentionally does not register an E2E handler by itself. A
/// host driver must keep both app processes alive, exchange only public peer
/// material, drive the production send/receive stack, and aggregate both role
/// results before [validateAndroidVoiceMessageEvidence] can pass.
AndroidCampaignEvidenceValidation validateAndroidVoiceMessageRoleInvocation(
  SimsRuntimeInvocation invocation,
) {
  if (invocation.profileId != simsAndroidMainProfileId ||
      invocation.scenarioId != simsAndroidVoiceMessageScenarioId) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message role requires the shared main-app profile and exact scenario',
    );
  }
  if (invocation.role != simsVoiceMessageSenderRole &&
      invocation.role != simsVoiceMessageReceiverRole) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message role must be sender or receiver',
    );
  }
  final targetId = invocation.values['targetId'];
  final counterpartTargetId = invocation.values['counterpartTargetId'];
  if (!_isSafeToken(targetId) ||
      !_isSafeToken(counterpartTargetId) ||
      targetId == counterpartTargetId) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message role requires two distinct explicit Android target IDs',
    );
  }
  final expectedKind = invocation.role == simsVoiceMessageSenderRole
      ? 'physical'
      : 'emulator';
  if (invocation.values['targetKind'] != expectedKind) {
    return AndroidCampaignEvidenceValidation.fail(
      'voice-message ${invocation.role} requires targetKind=$expectedKind',
    );
  }
  if (!_isSha256(invocation.values['buildArtifactSha256']) ||
      !_isSafeToken(invocation.values['campaignId'])) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message role lacks its campaign/build-artifact binding',
    );
  }
  return const AndroidCampaignEvidenceValidation.pass();
}

/// Requires a real two-target record -> production send -> production receive
/// -> download -> playback journey with byte identity across the endpoints.
///
/// Host/fake logic cannot satisfy this validator: both production Go bridge
/// flags, the native recorder, incoming listener, media downloader, and native
/// audio player are mandatory. The payload also rejects embedded raw audio or
/// secret key material; durable evidence stores hashes and IDs only.
AndroidCampaignEvidenceValidation validateAndroidVoiceMessageEvidence(
  Map<String, Object?> artifact,
) {
  if (artifact['schema'] != androidVoiceMessageEvidenceSchema ||
      artifact['scenario'] != simsAndroidVoiceMessageScenarioId ||
      artifact['status'] != 'passed' ||
      artifact['platform'] != 'android' ||
      artifact['runtimeDispatched'] != true) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message evidence lacks its passing Android runtime boundary',
    );
  }
  final sensitiveKey = _firstSensitiveKey(artifact);
  if (sensitiveKey != null) {
    return AndroidCampaignEvidenceValidation.fail(
      'voice-message evidence contains forbidden sensitive field $sensitiveKey',
    );
  }

  final runId = artifact['runId'];
  if (!_isSafeToken(runId)) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message evidence runId is invalid',
    );
  }
  final buildArtifact = _object(artifact['sharedArtifact']);
  if (buildArtifact == null ||
      buildArtifact['profileId'] != simsAndroidMainProfileId ||
      !_isSha256(buildArtifact['sha256'])) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message evidence is not bound to the shared prepared APK',
    );
  }

  final deviceIds = _stringList(artifact['deviceIds']);
  final targetKinds = _object(artifact['targetKinds']);
  if (deviceIds == null ||
      deviceIds.length != 2 ||
      deviceIds.toSet().length != 2 ||
      deviceIds.any((id) => !_isSafeToken(id)) ||
      targetKinds?['sender'] != 'physical' ||
      targetKinds?['receiver'] != 'emulator') {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message evidence requires a physical Android sender and emulator receiver',
    );
  }

  final sender = _object(artifact['sender']);
  final receiver = _object(artifact['receiver']);
  final transport = _object(artifact['transport']);
  if (sender == null || receiver == null || transport == null) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message evidence is missing sender, receiver, or transport proof',
    );
  }
  if (sender['role'] != simsVoiceMessageSenderRole ||
      receiver['role'] != simsVoiceMessageReceiverRole ||
      sender['deviceId'] != deviceIds[0] ||
      receiver['deviceId'] != deviceIds[1]) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message role/device assignments are inconsistent',
    );
  }

  final senderDigest = sender['recordedPlaintextSha256'];
  final receiverDigest = receiver['downloadedPlaintextSha256'];
  final senderBytes = _positiveInt(sender['recordedSizeBytes']);
  final receiverBytes = _positiveInt(receiver['downloadedSizeBytes']);
  final recordedDurationMs = _positiveInt(sender['recordedDurationMs']);
  final playbackDurationMs = _positiveInt(receiver['playbackDurationMs']);
  if (sender['permissionPregranted'] != true ||
      sender['realRecordPlugin'] != true ||
      sender['mime'] != 'audio/mp4' ||
      !_isSha256(senderDigest) ||
      senderBytes == null ||
      recordedDurationMs == null ||
      recordedDurationMs < 1500) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message sender lacks a real nonempty native recording',
    );
  }

  final messageId = sender['messageId'];
  final attachmentId = sender['attachmentId'];
  if (sender['productionSendVoiceMessage'] != true ||
      sender['productionGoBridge'] != true ||
      sender['sendResult'] != 'success' ||
      !_isSafeToken(messageId) ||
      !_isSafeToken(attachmentId) ||
      !_isSha256(sender['receiverPeerIdSha256']) ||
      !const <String>{
        'delivered',
        'inboxed',
      }.contains(sender['messageStatus']) ||
      !const <String>{
        'direct',
        'relay',
        'inbox',
      }.contains(sender['messageTransport'])) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message sender did not prove the production send path',
    );
  }

  if (receiver['productionIncomingListener'] != true ||
      receiver['productionGoBridge'] != true ||
      receiver['messagePersisted'] != true ||
      receiver['realMediaDownload'] != true ||
      receiver['downloadStatus'] != 'done' ||
      receiver['messageId'] != messageId ||
      receiver['attachmentId'] != attachmentId ||
      receiver['ownPeerIdSha256'] != sender['receiverPeerIdSha256'] ||
      !_isSha256(receiverDigest) ||
      receiverDigest != senderDigest ||
      receiverBytes == null ||
      receiverBytes != senderBytes) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message receiver did not persist/download the exact sent bytes',
    );
  }

  if (receiver['realAudioPlayerPlugin'] != true ||
      receiver['playbackStarted'] != true ||
      receiver['playbackProgressObserved'] != true ||
      receiver['playbackCompleted'] != true ||
      receiver['playbackStopped'] != true ||
      playbackDurationMs == null ||
      (playbackDurationMs - recordedDurationMs).abs() > 1500 ||
      sender['temporaryRecordingDeleted'] != true ||
      receiver['durableAttachmentRetained'] != true) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message playback or endpoint cleanup is incomplete',
    );
  }

  if (transport['realRelayMediaUpload'] != true ||
      transport['senderCustodyAccepted'] != true ||
      transport['realMessageDelivery'] != true ||
      transport['realRelayMediaDownload'] != true ||
      transport['senderReceiverPeerMatch'] != true ||
      transport['usedFakeNetwork'] == true ||
      transport['usedHostFileTransfer'] == true ||
      artifact['assertionsAttempted'] != 1) {
    return const AndroidCampaignEvidenceValidation.fail(
      'voice-message transport is fake, incomplete, or unreconciled',
    );
  }

  return const AndroidCampaignEvidenceValidation.pass();
}

Map<String, Object?> androidVoiceMessageDurablePayload(
  Map<String, Object?> runtimeProof,
) => validatedAndroidRuntimeProofPayload(
  runtimeProof: runtimeProof,
  validate: validateAndroidVoiceMessageEvidence,
);

AndroidCampaignEvidenceValidation validateAndroidVoiceMessageDurableArtifact(
  Map<String, Object?> artifact,
) => validateDurableAndroidCampaignArtifact(
  artifact: artifact,
  capabilityId: simsAndroidVoiceMessageScenarioId,
  validatorId: androidVoiceMessageArtifactValidatorId,
  validateRuntimeProof: validateAndroidVoiceMessageEvidence,
);

Map<String, Object?>? _object(Object? value) {
  if (value is! Map) return null;
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

List<String>? _stringList(Object? value) {
  if (value is! List || value.any((item) => item is! String)) return null;
  return value.cast<String>();
}

int? _positiveInt(Object? value) => value is int && value > 0 ? value : null;

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _isSafeToken(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= 160 &&
    RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);

String? _firstSensitiveKey(Object? value, [String path = r'$']) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = '${entry.key}';
      final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (const <String>{
        'rawaudio',
        'audiobase64',
        'encryptionkey',
        'privatekey',
        'mlkemsecret',
        'mnemonic',
        'waketoken',
      }.any(normalized.contains)) {
        return '$path.$key';
      }
      final nested = _firstSensitiveKey(entry.value, '$path.$key');
      if (nested != null) return nested;
    }
  } else if (value is List) {
    for (var index = 0; index < value.length; index += 1) {
      final nested = _firstSensitiveKey(value[index], '$path[$index]');
      if (nested != null) return nested;
    }
  }
  return null;
}
