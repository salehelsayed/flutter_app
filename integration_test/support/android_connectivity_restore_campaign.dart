import 'package:flutter_app/core/debug/connectivity_restore_e2e_contract.dart';

import 'sims_runtime_protocol.dart';

/// Fail-closed contracts for the main-app connectivity campaign. The receiver
/// uses a dedicated pre-generic observer action so the E2E helper cannot create
/// the drain by calling its normal health-check/drain path.
const String connectivityRestoreWindowRequestSchema =
    connectivityRestoreObserveRequestSchema;
const String connectivityRestoreWindowAckSchema =
    'mknoon.sims.connectivity-restore-window-ack.v1';
const String connectivityRestoreWindowRequestFileName =
    'connectivity-restore-window.request.json';
const String connectivityRestoreWindowAckFileName =
    'connectivity-restore-window.ack.json';

List<String> connectivityRestoreMessageTexts(String runId) =>
    connectivityRestoreExpectedTexts(runId);

String connectivityRestoreSenderStepId(String runId) =>
    connectivityRestoreSendStepId(runId);

String? validateConnectivityRestoreInvocation(
  SimsRuntimeInvocation invocation,
) {
  if (invocation.schema != simsRuntimeConfigSchema) {
    return 'connectivity invocation requires schema $simsRuntimeConfigSchema';
  }
  if (invocation.profileId != simsAndroidMainProfileId) {
    return 'connectivity invocation requires profile $simsAndroidMainProfileId';
  }
  if (invocation.scenarioId != connectivityRestoreScenarioId) {
    return 'connectivity endpoint requires $connectivityRestoreScenarioId';
  }
  if (!const <String>{'sender', 'receiver'}.contains(invocation.role)) {
    return 'connectivity invocation requires sender or receiver role';
  }
  final expectedKind = invocation.role == 'sender' ? 'physical' : 'emulator';
  if (invocation.values['targetKind'] != expectedKind) {
    return 'connectivity ${invocation.role} requires targetKind $expectedKind';
  }
  final targetId = invocation.values['targetId'];
  if (targetId is! String ||
      targetId.isEmpty ||
      targetId.length > 160 ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(targetId)) {
    return 'connectivity invocation requires a safe targetId';
  }
  final digest = invocation.values['buildArtifactSha256'];
  if (digest is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    return 'connectivity invocation requires the prepared APK SHA-256';
  }
  return null;
}

String? validateConnectivityRestoreSendResult(
  Map<String, Object?> result, {
  required SimsRuntimeInvocation invocation,
}) {
  if (result['stepId'] != connectivityRestoreSenderStepId(invocation.runId) ||
      result['status'] != 'complete' ||
      result['success'] != true) {
    return 'sender production control result is not the completed run step';
  }
  final chatAction = _object(result['chatAction']);
  final sent = chatAction?['sent'];
  if (sent is! List || sent.length != 3) {
    return 'sender production control must report exactly three accepted sends';
  }
  final expectedTexts = connectivityRestoreMessageTexts(invocation.runId);
  final observedTexts = <String>[];
  final messageIds = <String>{};
  for (final value in sent) {
    final send = _object(value);
    if (send == null) return 'sender accepted-send entry is not an object';
    final text = send['text'];
    final messageId = send['messageId'];
    final targetPeerId = send['targetPeerId'];
    final transport = send['transport'];
    final status = send['status'];
    if (text is! String ||
        messageId is! String ||
        messageId.isEmpty ||
        targetPeerId is! String ||
        targetPeerId.isEmpty ||
        transport is! String ||
        !const <String>{'direct', 'relay', 'inbox'}.contains(transport) ||
        status is! String ||
        !const <String>{'delivered', 'inboxed'}.contains(status)) {
      return 'sender accepted-send entry is incomplete or not successful';
    }
    observedTexts.add(text);
    messageIds.add(messageId);
  }
  if (!_sameStrings(observedTexts, expectedTexts) || messageIds.length != 3) {
    return 'sender production observations do not match the three run-bound '
        'messages';
  }
  return null;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String? validateConnectivityRestoreWindowRequest(
  Map<String, Object?> request, {
  required SimsRuntimeInvocation invocation,
}) {
  if (request['schema'] != connectivityRestoreWindowRequestSchema ||
      request['scenario'] != invocation.scenarioId ||
      request['role'] != invocation.role ||
      request['runId'] != invocation.runId ||
      request['nonce'] != invocation.nonce ||
      request['receiverNetwork'] != 'disconnected' ||
      request['appForeground'] != true) {
    return 'restore-window request does not match the acknowledged receiver '
        'runtime tuple and disconnected foreground state';
  }
  return null;
}

Map<String, Object?>? _object(Object? value) {
  if (value is! Map) return null;
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}
