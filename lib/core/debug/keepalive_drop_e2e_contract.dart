/// Host-safe protocol shared by the production main-app keepalive actions and
/// the Android sims campaign.
const String keepaliveDropScenarioId = 'android.keepalive_drop_skip_direct';
const String keepaliveDropProfileId = 'android.e2e.main';
const String keepaliveDroppedSendAction = 'keepalive_dropped_send';
const String keepaliveRecoveryObserveAction = 'keepalive_recovery_observe';
const String keepaliveDroppedSendRequestSchema =
    'mknoon.sims.keepalive-dropped-send-request.v1';
const String keepaliveDroppedSendResultSchema =
    'mknoon.sims.keepalive-dropped-send-result.v1';
const String keepaliveRecoveryRequestSchema =
    'mknoon.sims.keepalive-recovery-request.v1';
const String keepaliveRecoveryResultSchema =
    'mknoon.sims.keepalive-recovery-result.v1';

const String _installedSimsBuildProfile = String.fromEnvironment(
  'SIMS_BUILD_PROFILE_ID',
);

String keepaliveDroppedSendStepId(String runId) => 'keepalive-send-$runId';

String keepaliveRecoveryStepId(String runId) => 'keepalive-recovery-$runId';

String keepaliveRunMessageText(String runId) =>
    'SIMS keepalive $runId dropped-peer send';

String? validateKeepaliveDroppedSendRequest(
  Map<String, Object?> request, {
  String installedProfileId = _installedSimsBuildProfile,
}) {
  final common = _validateCommon(
    request,
    schema: keepaliveDroppedSendRequestSchema,
    action: keepaliveDroppedSendAction,
    stepForRun: keepaliveDroppedSendStepId,
    installedProfileId: installedProfileId,
  );
  if (common != null) return common;
  final runId = request['runId']! as String;
  if (request['text'] != keepaliveRunMessageText(runId)) {
    return 'keepalive send text is not bound to the run';
  }
  return _validPeer(request['targetPeerId'])
      ? null
      : 'keepalive send targetPeerId is invalid';
}

String? validateKeepaliveRecoveryRequest(
  Map<String, Object?> request, {
  String installedProfileId = _installedSimsBuildProfile,
}) {
  final common = _validateCommon(
    request,
    schema: keepaliveRecoveryRequestSchema,
    action: keepaliveRecoveryObserveAction,
    stepForRun: keepaliveRecoveryStepId,
    installedProfileId: installedProfileId,
  );
  if (common != null) return common;
  if (!_validPeer(request['targetPeerId'])) {
    return 'keepalive recovery targetPeerId is invalid';
  }
  final messageId = request['messageId'];
  if (messageId is! String ||
      !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,40}$').hasMatch(messageId)) {
    return 'keepalive recovery messageId is invalid';
  }
  return null;
}

String keepaliveMessageIdPrefix(String messageId) {
  if (messageId.length < 8) {
    throw const FormatException('keepalive message ID is too short');
  }
  final prefix = messageId.substring(0, 8).toLowerCase();
  if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(prefix)) {
    throw const FormatException('keepalive message ID is not UUID-shaped');
  }
  return prefix;
}

String? _validateCommon(
  Map<String, Object?> request, {
  required String schema,
  required String action,
  required String Function(String runId) stepForRun,
  required String installedProfileId,
}) {
  if (installedProfileId != keepaliveDropProfileId) {
    return 'keepalive action requires installed profile '
        '$keepaliveDropProfileId';
  }
  if (request['schema'] != schema ||
      request['profileId'] != keepaliveDropProfileId ||
      request['scenario'] != keepaliveDropScenarioId ||
      request['role'] != 'sender' ||
      request['transport_action'] != action) {
    return 'keepalive action tuple is invalid';
  }
  final runId = request['runId'];
  final nonce = request['nonce'];
  if (!_validToken(runId, 80) || !_validToken(nonce, 128)) {
    return 'keepalive runId or nonce is invalid';
  }
  if (request['stepId'] != stepForRun(runId! as String)) {
    return 'keepalive stepId is not bound to the run';
  }
  return null;
}

bool _validToken(Object? value, int maxLength) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= maxLength &&
    RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);

bool _validPeer(Object? value) =>
    value is String && value.isNotEmpty && value.length <= 160;
