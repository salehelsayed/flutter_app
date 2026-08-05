/// Pure, build-free validators for Plan 258 real-device evidence.
///
/// Device orchestrators own capture. These functions deliberately accept only
/// decoded JSON maps so the same fail-closed criteria can run in unit tests,
/// post-capture CLIs, and the aggregate sims report verifier.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

const String privateMediaOutboxPhysicalSenderTargetRole =
    'physical_android_sender';
const String privateMediaOutboxEmulatorReceiverTargetRole =
    'android_emulator_receiver';

/// Returns a domain- and role-separated digest suitable for durable evidence.
///
/// The ADB target ID stays in the local orchestration boundary. Only this
/// one-way value is permitted in the retained private-media outbox artifact.
String privateMediaOutboxTargetSha256({
  required String role,
  required String adbTargetId,
}) {
  if (role != privateMediaOutboxPhysicalSenderTargetRole &&
      role != privateMediaOutboxEmulatorReceiverTargetRole) {
    throw ArgumentError.value(role, 'role', 'unsupported target role');
  }
  if (adbTargetId.trim().isEmpty) {
    throw ArgumentError.value(adbTargetId, 'adbTargetId', 'must be nonempty');
  }
  return sha256
      .convert(
        utf8.encode(
          'android.connectivity_restore_media_outbox|target|$role|$adbTargetId',
        ),
      )
      .toString();
}

final class DeviceCriteriaResult {
  const DeviceCriteriaResult._(this.ok, this.detail);

  const DeviceCriteriaResult.pass(String detail) : this._(true, detail);
  const DeviceCriteriaResult.fail(String detail) : this._(false, detail);

  final bool ok;
  final String detail;
}

DeviceCriteriaResult validateConnectivityRestoreArtifact(
  Map<String, Object?> artifact,
) {
  final common = _passedScenario(
    artifact,
    'android.connectivity_restore_inbox_drain',
  );
  if (!common.ok) return common;
  if (artifact['messagesQueued'] != 3 || artifact['messagesRendered'] != 3) {
    return const DeviceCriteriaResult.fail(
      'connectivity proof requires exactly three queued and rendered messages',
    );
  }
  if (artifact['resumeEventsDuringWindow'] != 0) {
    return const DeviceCriteriaResult.fail(
      'connectivity proof must not use an app-resume drain',
    );
  }
  final events = _strings(artifact['events']);
  if (events.any((event) => event.startsWith('APP_LIFECYCLE_RESUME_'))) {
    return const DeviceCriteriaResult.fail(
      'connectivity proof contains an app-resume event in the restore window',
    );
  }
  const required = <String>{
    'P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN',
    'P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS',
    'P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM',
  };
  final missing = required.difference(events.toSet());
  if (missing.isNotEmpty) {
    return DeviceCriteriaResult.fail(
      'connectivity proof is missing events: ${missing.join(', ')}',
    );
  }
  final restoreIndex = events.indexOf('P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN');
  if (events.indexOf('P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS') <=
          restoreIndex ||
      events.indexOf('P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM') <=
          restoreIndex) {
    return const DeviceCriteriaResult.fail(
      'connectivity drain and rewarm must occur after the restored edge',
    );
  }
  if (!_hasTwoDistinctNonemptyIds(artifact['deviceIds'])) {
    return const DeviceCriteriaResult.fail(
      'connectivity proof requires two distinct nonempty Android target IDs',
    );
  }
  return const DeviceCriteriaResult.pass(
    'network-change drain, no-resume delivery, and peer rewarm proven',
  );
}

/// Strict Plan 260 proof for the production private-media offline outbox.
///
/// Latency is retained as an informational trend value. PASS is determined by
/// source-qualified causality, exact issuance counts, and receiver delivery.
DeviceCriteriaResult validatePrivateMediaOutboxRestoreArtifact(
  Map<String, Object?> artifact,
) {
  final common = _passedScenario(
    artifact,
    'android.connectivity_restore_media_outbox',
  );
  if (!common.ok) return common;
  const topLevelKeys = <String>{
    'schemaVersion',
    'scenario',
    'status',
    'physicalSenderTargetSha256',
    'emulatorReceiverTargetSha256',
    'phases',
  };
  if (artifact.keys.toSet().difference(topLevelKeys).isNotEmpty ||
      topLevelKeys.difference(artifact.keys.toSet()).isNotEmpty) {
    return const DeviceCriteriaResult.fail(
      'private-media outbox artifact must use the exact safe top-level schema',
    );
  }
  if (artifact['schemaVersion'] != 1) {
    return const DeviceCriteriaResult.fail(
      'private-media outbox artifact requires schemaVersion 1',
    );
  }
  final physicalSenderTargetSha256 = artifact['physicalSenderTargetSha256'];
  final emulatorReceiverTargetSha256 = artifact['emulatorReceiverTargetSha256'];
  if (!_isLowercaseSha256(physicalSenderTargetSha256) ||
      !_isLowercaseSha256(emulatorReceiverTargetSha256) ||
      physicalSenderTargetSha256 == emulatorReceiverTargetSha256) {
    return const DeviceCriteriaResult.fail(
      'private-media outbox proof requires distinct role-salted Android '
      'target hashes',
    );
  }
  final rawPhases = artifact['phases'];
  if (rawPhases is! List || rawPhases.length != 2) {
    return const DeviceCriteriaResult.fail(
      'private-media outbox proof requires exactly two phases',
    );
  }
  for (var index = 0; index < rawPhases.length; index++) {
    final rawPhase = rawPhases[index];
    if (rawPhase is! Map) {
      return DeviceCriteriaResult.fail(
        'private-media outbox phase ${index + 1} is not an object',
      );
    }
    final phase = rawPhase.cast<String, Object?>();
    final validation = _validatePrivateMediaOutboxPhase(
      phase,
      expectedPhase: index + 1,
    );
    if (!validation.ok) return validation;
  }
  return const DeviceCriteriaResult.pass(
    'private-media outbox causality, exact attempts, and delivery proven',
  );
}

DeviceCriteriaResult _validatePrivateMediaOutboxPhase(
  Map<String, Object?> phase, {
  required int expectedPhase,
}) {
  const keys = <String>{
    'phase',
    'runCorrelationSha256',
    'attachmentSha256',
    'queuedNoRed',
    'pauseResumeRemainedQueued',
    'offlineResumeAttemptCount',
    'zeroPostRestoreUiActions',
    'receiverExactMediaDelivered',
    'encryptionPreparedCount',
    'uploadRequestCount',
    'envelopeCount',
    'receiveCount',
    'networkRestoredClaimCount',
    'postRestoreEncryptionCount',
    'postRestoreUploadCount',
    'restoreRetryLatencyMs',
    'events',
  };
  if (phase.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(phase.keys.toSet()).isNotEmpty) {
    return DeviceCriteriaResult.fail(
      'private-media outbox phase $expectedPhase must use the exact safe schema',
    );
  }
  if (phase['phase'] != expectedPhase ||
      !_isLowercaseSha256(phase['runCorrelationSha256']) ||
      !_isLowercaseSha256(phase['attachmentSha256'])) {
    return DeviceCriteriaResult.fail(
      'private-media outbox phase $expectedPhase has invalid identity hashes',
    );
  }
  if (phase['queuedNoRed'] != true ||
      phase['zeroPostRestoreUiActions'] != true ||
      phase['receiverExactMediaDelivered'] != true) {
    return DeviceCriteriaResult.fail(
      'private-media outbox phase $expectedPhase did not remain honest or deliver',
    );
  }
  if (expectedPhase == 2 && phase['pauseResumeRemainedQueued'] != true) {
    return const DeviceCriteriaResult.fail(
      'private-media outbox phase 2 must remain queued across pause/resume',
    );
  }
  if (expectedPhase == 1 && phase['pauseResumeRemainedQueued'] != false) {
    return const DeviceCriteriaResult.fail(
      'private-media outbox phase 1 must not forge pause/resume evidence',
    );
  }
  if (phase['offlineResumeAttemptCount'] != 0) {
    return DeviceCriteriaResult.fail(
      'private-media outbox phase $expectedPhase issued an offline resume attempt',
    );
  }
  const exactCounts = <String, int>{
    'encryptionPreparedCount': 2,
    'uploadRequestCount': 2,
    'envelopeCount': 1,
    'receiveCount': 1,
    'networkRestoredClaimCount': 1,
    'postRestoreEncryptionCount': 1,
    'postRestoreUploadCount': 1,
  };
  for (final entry in exactCounts.entries) {
    if (phase[entry.key] != entry.value) {
      return DeviceCriteriaResult.fail(
        'private-media outbox phase $expectedPhase requires '
        '${entry.key}=${entry.value}',
      );
    }
  }
  final latency = phase['restoreRetryLatencyMs'];
  if (latency is! int || latency < 0) {
    return DeviceCriteriaResult.fail(
      'private-media outbox phase $expectedPhase must record nonnegative '
      'restoreRetryLatencyMs informationally',
    );
  }

  final rawEvents = phase['events'];
  if (rawEvents is! List || rawEvents.length != 6) {
    return DeviceCriteriaResult.fail(
      'private-media outbox phase $expectedPhase requires the exact causal chain',
    );
  }
  const expectedEvents = <String>[
    'PENDING_RETRIER_NETWORK_RESTORED_TRIGGER',
    'MEDIA_UPLOAD_LEASE_CLAIMED',
    'MEDIA_ENCRYPTION_PREPARED',
    'MEDIA_UPLOAD_START',
    'CHAT_MSG_SEND_SUCCESS',
    'PRIVATE_MEDIA_OUTBOX_E2E_RECEIVED',
  ];
  final runHash = phase['runCorrelationSha256'];
  final attachmentHash = phase['attachmentSha256'];
  for (var index = 0; index < rawEvents.length; index++) {
    final rawEvent = rawEvents[index];
    if (rawEvent is! Map) {
      return DeviceCriteriaResult.fail(
        'private-media outbox phase $expectedPhase event $index is not an object',
      );
    }
    final event = rawEvent.cast<String, Object?>();
    final expectedKeys = index == 0
        ? const <String>{'event', 'runCorrelationSha256'}
        : index == 1
        ? const <String>{
            'event',
            'source',
            'runCorrelationSha256',
            'attachmentSha256',
          }
        : const <String>{'event', 'runCorrelationSha256', 'attachmentSha256'};
    if (event.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(event.keys.toSet()).isNotEmpty ||
        event['event'] != expectedEvents[index] ||
        event['runCorrelationSha256'] != runHash ||
        (index > 0 && event['attachmentSha256'] != attachmentHash)) {
      return DeviceCriteriaResult.fail(
        'private-media outbox phase $expectedPhase causal event $index is invalid',
      );
    }
    if (index == 1 && event['source'] != 'network_restored') {
      return DeviceCriteriaResult.fail(
        'private-media outbox phase $expectedPhase causal claim is not '
        'source=network_restored',
      );
    }
  }
  return DeviceCriteriaResult.pass(
    'private-media outbox phase $expectedPhase accepted',
  );
}

DeviceCriteriaResult validateKeepaliveDropArtifact(
  Map<String, Object?> artifact,
) {
  final common = _passedScenario(
    artifact,
    'android.keepalive_drop_skip_direct',
  );
  if (!common.ok) return common;
  final events = _strings(artifact['events']);
  const drop = 'KEEPALIVE_PEER_DROP';
  const sendBegin = 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN';
  const skipped = 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP';
  const custody = 'CHAT_MSG_SEND_CUSTODY_CONFIRMED';
  const recovery = 'DELIVERY_RECEIPT_APPLIED';
  const rearmed = 'P2P_SERVICE_PEER_PING_SUCCESS';
  final missing = <String>[
    if (!events.contains(drop)) drop,
    if (!events.contains(sendBegin)) sendBegin,
    if (!events.contains(skipped)) skipped,
    if (!events.contains(custody)) custody,
    if (!events.contains(recovery)) recovery,
    if (!events.contains(rearmed)) rearmed,
  ];
  if (missing.isNotEmpty) {
    return DeviceCriteriaResult.fail(
      'keepalive proof is missing production events: ${missing.join(', ')}',
    );
  }
  final messageIdPrefix = artifact['messageIdPrefix'];
  if (messageIdPrefix is! String ||
      !RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(messageIdPrefix)) {
    return const DeviceCriteriaResult.fail(
      'keepalive proof requires a safe eight-character message ID prefix',
    );
  }
  final correlated = _messageEventEvidence(artifact['messageEvents']);
  final sendBeginEvidence = _findCorrelatedMessageEvent(
    correlated,
    event: sendBegin,
    messageIdPrefix: messageIdPrefix,
    events: events,
  );
  final custodyEvidence = _findCorrelatedMessageEvent(
    correlated,
    event: custody,
    messageIdPrefix: messageIdPrefix,
    events: events,
  );
  final recoveryEvidence = _findCorrelatedMessageEvent(
    correlated,
    event: recovery,
    messageIdPrefix: messageIdPrefix,
    events: events,
  );
  if (sendBeginEvidence == null ||
      custodyEvidence == null ||
      recoveryEvidence == null) {
    return const DeviceCriteriaResult.fail(
      'keepalive begin, custody, and receipt must carry the returned message ID',
    );
  }

  final dropIndex = events.indexOf(drop);
  final skipIndex = _indexAfter(events, skipped, dropIndex);
  final rearmIndex = _indexAfter(events, rearmed, skipIndex);
  final sendTerminalIndex = skipIndex > custodyEvidence.eventIndex
      ? skipIndex
      : custodyEvidence.eventIndex;
  if (sendBeginEvidence.eventIndex <= dropIndex ||
      skipIndex <= sendBeginEvidence.eventIndex ||
      custodyEvidence.eventIndex <= sendBeginEvidence.eventIndex ||
      recoveryEvidence.eventIndex <= sendTerminalIndex ||
      rearmIndex <= sendTerminalIndex) {
    return const DeviceCriteriaResult.fail(
      'keepalive drop, skip, custody, recovery, and re-arm are out of order',
    );
  }
  if (!_hasTwoDistinctNonemptyIds(artifact['deviceIds'])) {
    return const DeviceCriteriaResult.fail(
      'keepalive proof requires two distinct nonempty Android target IDs',
    );
  }
  final sendWindowEvents = _strings(artifact['sendWindowEvents']);
  if (sendWindowEvents.isEmpty ||
      !sendWindowEvents.contains(sendBegin) ||
      !sendWindowEvents.contains(skipped) ||
      !sendWindowEvents.contains(custody)) {
    return const DeviceCriteriaResult.fail(
      'keepalive proof requires a bounded send window with begin, skip, and custody',
    );
  }
  const forbidden = <String>{
    'P2P_SERVICE_DISCOVER_PEER',
    'P2P_SERVICE_DISCOVER_PEER_BEGIN',
    'P2P_SERVICE_DISCOVER_PEER_SUCCESS',
    'P2P_SERVICE_DISCOVER_PEER_NOT_FOUND',
    'P2P_SERVICE_DISCOVER_PEER_EXCEPTION',
    'P2P_SERVICE_DIAL_PEER',
    'P2P_SERVICE_DIAL_PEER_BEGIN',
    'P2P_SERVICE_DIAL_PEER_SUCCESS',
    'P2P_SERVICE_DIAL_PEER_ERROR',
    'P2P_SERVICE_DIAL_PEER_EXCEPTION',
  };
  final attempted = forbidden.intersection(sendWindowEvents.toSet());
  if (attempted.isNotEmpty) {
    return DeviceCriteriaResult.fail(
      'keepalive-dropped send attempted a forbidden direct leg: '
      '${attempted.join(', ')}',
    );
  }
  final custodyMs = artifact['custodyLatencyMs'];
  if (custodyMs is! num || custodyMs < 0 || custodyMs >= 1000) {
    return const DeviceCriteriaResult.fail(
      'relay custody must be measured and remain below one second',
    );
  }
  return const DeviceCriteriaResult.pass(
    'drop latch skipped direct dial while custody, recovery, and re-arm passed',
  );
}

DeviceCriteriaResult validateWakeTokenArtifact(Map<String, Object?> artifact) {
  final common = _passedScenario(artifact, 'android.wake_token_directionality');
  if (!common.ok) return common;

  for (final entry in artifact.entries) {
    final key = entry.key.toLowerCase();
    if ((key.contains('token') || key.contains('secret')) &&
        !key.endsWith('sha256') &&
        entry.value != null) {
      return DeviceCriteriaResult.fail(
        'wake proof contains forbidden secret-bearing field ${entry.key}',
      );
    }
  }

  final values = <Object?>[
    artifact['registeredTokenSha256'],
    artifact['storedTokenSha256'],
    artifact['attachedTokenSha256'],
  ];
  final hashes = values.whereType<String>().toList(growable: false);
  final sha256 = RegExp(r'^[0-9a-fA-F]{64}$');
  if (hashes.length != 3 || hashes.any((value) => !sha256.hasMatch(value))) {
    return const DeviceCriteriaResult.fail(
      'wake proof requires three SHA-256 values and no raw token',
    );
  }
  if (hashes.toSet().length != 1) {
    return const DeviceCriteriaResult.fail(
      'registered, stored, and attached wake-token hashes differ',
    );
  }
  if (!_hasTwoDistinctNonemptyIds(artifact['deviceIds'])) {
    return const DeviceCriteriaResult.fail(
      'wake proof requires two distinct nonempty Android target IDs',
    );
  }
  return const DeviceCriteriaResult.pass(
    'registered, stored, and attached wake-token hashes are equal',
  );
}

DeviceCriteriaResult validateVoiceRecorderArtifact(
  Map<String, Object?> artifact,
) {
  final common = _passedScenario(
    artifact,
    'android.voice_recorder_native_smoke',
  );
  if (!common.ok) return common;
  if (artifact['permissionPregranted'] != true) {
    return const DeviceCriteriaResult.fail(
      'microphone permission was not pregranted by the harness',
    );
  }
  if (artifact['realRecordPlugin'] != true) {
    return const DeviceCriteriaResult.fail(
      'recording did not cross the real native record plugin',
    );
  }
  if (artifact['mime'] != 'audio/mp4' || artifact['decodable'] != true) {
    return const DeviceCriteriaResult.fail(
      'recording is not a decodable audio/mp4 artifact',
    );
  }
  final size = artifact['sizeBytes'];
  final duration = artifact['durationMs'];
  if (size is! num || size <= 0 || duration is! num || duration < 1500) {
    return const DeviceCriteriaResult.fail(
      'recording must be nonempty and at least 1500ms long',
    );
  }
  if (artifact['temporaryFileDeleted'] != true) {
    return const DeviceCriteriaResult.fail(
      'recording cleanup did not delete the temporary file',
    );
  }
  return const DeviceCriteriaResult.pass(
    'real native recorder produced and cleaned a decodable M4A',
  );
}

DeviceCriteriaResult validateScenarioReconciliation({
  required Iterable<String> selected,
  required Iterable<String> attempted,
  required Iterable<String> terminal,
}) {
  final selectedList = selected.toList(growable: false);
  final attemptedList = attempted.toList(growable: false);
  final terminalList = terminal.toList(growable: false);
  if (_hasDuplicates(selectedList) ||
      _hasDuplicates(attemptedList) ||
      _hasDuplicates(terminalList)) {
    return const DeviceCriteriaResult.fail(
      'scenario reconciliation contains duplicate IDs',
    );
  }
  if (!_sameStrings(selectedList, attemptedList) ||
      !_sameStrings(selectedList, terminalList)) {
    return const DeviceCriteriaResult.fail(
      'selected, attempted, and terminal scenario IDs differ',
    );
  }
  return const DeviceCriteriaResult.pass(
    'selected, attempted, and terminal scenario IDs reconcile exactly',
  );
}

DeviceCriteriaResult validateTopologyNotApplicable(
  Map<String, Object?> artifact,
) {
  if (artifact['status'] != 'notApplicable' ||
      artifact['reasonCode'] != 'target_topology_unavailable') {
    return const DeviceCriteriaResult.fail(
      'topology N/A requires the target_topology_unavailable reason',
    );
  }
  if (artifact['attempted'] != false || artifact['boundaryProven'] != false) {
    return const DeviceCriteriaResult.fail(
      'topology N/A cannot claim an attempt or proof boundary',
    );
  }
  return const DeviceCriteriaResult.pass(
    'topology is visibly N/A without claiming proof',
  );
}

DeviceCriteriaResult validateNotificationArtifact(
  Map<String, Object?> artifact,
) {
  final secretBearingField = _findNotificationSecretBearingField(artifact);
  if (secretBearingField != null) {
    return DeviceCriteriaResult.fail(
      'notification proof contains forbidden secret-bearing field '
      '$secretBearingField',
    );
  }
  final scenario = artifact['scenario'];
  if (scenario is! String || !_notificationRequirements.containsKey(scenario)) {
    return const DeviceCriteriaResult.fail('unknown notification scenario');
  }
  final common = _passedScenario(artifact, scenario);
  if (!common.ok) return common;
  if (scenario == 'payload_fast_path_ios_receiver') {
    final durable = _validateIosNotificationDurableArtifact(artifact);
    if (!durable.ok) return durable;
  }
  final expectedPlatform = scenario == 'payload_fast_path_ios_receiver'
      ? 'ios'
      : 'android';
  if (artifact['platform'] != expectedPlatform) {
    return DeviceCriteriaResult.fail(
      '$scenario requires the $expectedPlatform platform boundary',
    );
  }
  if (_strings(artifact['devices']).length < 2) {
    return const DeviceCriteriaResult.fail(
      'notification proof requires two explicit device IDs',
    );
  }
  final capturedAt = artifact['capturedAt'];
  if (capturedAt is! String || DateTime.tryParse(capturedAt) == null) {
    return const DeviceCriteriaResult.fail(
      'notification proof requires a valid capture timestamp',
    );
  }
  final checksValue = artifact['checks'];
  if (checksValue is! Map) {
    return const DeviceCriteriaResult.fail(
      'notification proof requires a checks object',
    );
  }
  final missing = _notificationRequirements[scenario]!
      .where((check) => checksValue[check] != true)
      .toList(growable: false);
  if (missing.isNotEmpty) {
    return DeviceCriteriaResult.fail(
      '$scenario is missing required checks: ${missing.join(', ')}',
    );
  }
  return DeviceCriteriaResult.pass(
    '$scenario satisfies its real provider/relay/device criteria',
  );
}

DeviceCriteriaResult _validateIosNotificationDurableArtifact(
  Map<String, Object?> artifact,
) {
  const expectedKeys = <String>{
    'schema',
    'capabilityId',
    'validatorIds',
    'testCase',
    'recoveryTestCase',
    'scenario',
    'status',
    'platform',
    'capturedAt',
    'messageVisibleAt',
    'networkRestoredAt',
    'recoveryCompletedAt',
    'recoveryZeroBadgeObservedAt',
    'devices',
    'checks',
    'runId',
    'nonce',
    'recoveryRunId',
    'recoveryNonce',
    'preparedApplicationSha256',
    'providerRequestSha256',
    'payloadProducerSha256',
    'apnsPayloadSha256',
    'recoveryApnsPayloadSha256',
    'childBuildCount',
    'manualActionCount',
    'recoveryCounts',
    'evidenceSha256',
    'buildProfile',
    'stagingEnvironment',
    'candidateAppRevision',
    'candidateRelayRevision',
    'candidateRelaySha256',
    'automationReceiptSha256',
    'recoveryAutomationReceiptSha256',
  };
  final artifactKeys = artifact.keys.toSet();
  if (artifactKeys.difference(expectedKeys).isNotEmpty ||
      expectedKeys.difference(artifactKeys).isNotEmpty) {
    return const DeviceCriteriaResult.fail(
      'iOS notification proof fields must match the exact durable schema',
    );
  }

  if (artifact['schema'] != 'mknoon.sims.proof.v1' ||
      artifact['capabilityId'] != 'notifications.ios_payload_fast_path' ||
      !_sameStrings(_strings(artifact['validatorIds']), const <String>[
        'validateNotificationArtifact',
      ]) ||
      artifact['testCase'] != 'TC-B12' ||
      artifact['recoveryTestCase'] != 'TC-333-08' ||
      artifact['buildProfile'] != 'ios.device.production' ||
      artifact['stagingEnvironment'] != 'staging') {
    return const DeviceCriteriaResult.fail(
      'iOS notification proof provenance does not match the selected sims row',
    );
  }

  if (artifact['childBuildCount'] != 0 || artifact['manualActionCount'] != 0) {
    return const DeviceCriteriaResult.fail(
      'iOS notification proof requires zero child builds and manual actions',
    );
  }

  for (final key in const <String>[
    'runId',
    'nonce',
    'recoveryRunId',
    'recoveryNonce',
  ]) {
    if (!_isSafeNotificationRunToken(artifact[key])) {
      return DeviceCriteriaResult.fail(
        'iOS notification proof $key must be a safe run token',
      );
    }
  }

  for (final key in const <String>[
    'candidateAppRevision',
    'candidateRelayRevision',
  ]) {
    if (!_isSafeNotificationProvenanceString(artifact[key])) {
      return DeviceCriteriaResult.fail(
        'iOS notification proof $key must be a safe nonempty string',
      );
    }
  }

  for (final key in const <String>[
    'preparedApplicationSha256',
    'providerRequestSha256',
    'payloadProducerSha256',
    'apnsPayloadSha256',
    'recoveryApnsPayloadSha256',
    'candidateRelaySha256',
    'automationReceiptSha256',
    'recoveryAutomationReceiptSha256',
  ]) {
    if (!_isLowercaseSha256(artifact[key])) {
      return DeviceCriteriaResult.fail(
        'iOS notification proof $key must be lowercase SHA-256',
      );
    }
  }
  if (artifact['runId'] == artifact['recoveryRunId'] ||
      artifact['nonce'] == artifact['recoveryNonce']) {
    return const DeviceCriteriaResult.fail(
      'iOS notification fast-path and recovery legs must have distinct '
      'run and nonce bindings',
    );
  }

  final devices = artifact['devices'];
  if (devices is! List ||
      devices.length != 2 ||
      devices.any((device) => !_isSafeNotificationProvenanceString(device)) ||
      devices.toSet().length != 2) {
    return const DeviceCriteriaResult.fail(
      'iOS notification proof requires exactly two distinct bounded device IDs',
    );
  }

  final capturedAt = artifact['capturedAt'];
  final capturedTimestamp = capturedAt is String
      ? DateTime.tryParse(capturedAt)
      : null;
  if (capturedTimestamp == null || !capturedTimestamp.isUtc) {
    return const DeviceCriteriaResult.fail(
      'iOS notification proof capturedAt must be a UTC timestamp',
    );
  }

  final messageVisibleAt = artifact['messageVisibleAt'] is String
      ? DateTime.tryParse(artifact['messageVisibleAt']! as String)
      : null;
  final networkRestoredAt = artifact['networkRestoredAt'] is String
      ? DateTime.tryParse(artifact['networkRestoredAt']! as String)
      : null;
  if (messageVisibleAt == null ||
      !messageVisibleAt.isUtc ||
      networkRestoredAt == null ||
      !networkRestoredAt.isUtc ||
      networkRestoredAt.isBefore(messageVisibleAt)) {
    return const DeviceCriteriaResult.fail(
      'iOS notification proof requires ordered UTC visibility and network '
      'restoration timestamps',
    );
  }

  final recoveryCompletedAt = artifact['recoveryCompletedAt'] is String
      ? DateTime.tryParse(artifact['recoveryCompletedAt']! as String)
      : null;
  final recoveryZeroBadgeObservedAt =
      artifact['recoveryZeroBadgeObservedAt'] is String
      ? DateTime.tryParse(artifact['recoveryZeroBadgeObservedAt']! as String)
      : null;
  if (recoveryCompletedAt == null ||
      !recoveryCompletedAt.isUtc ||
      recoveryZeroBadgeObservedAt == null ||
      !recoveryZeroBadgeObservedAt.isUtc ||
      recoveryZeroBadgeObservedAt.isBefore(recoveryCompletedAt)) {
    return const DeviceCriteriaResult.fail(
      'iOS notification recovery requires ordered UTC completion and final '
      'zero-badge observation timestamps',
    );
  }

  const exactRecoveryCounts = <String, int>{
    'badgeBefore': 1,
    'badgeAfter': 0,
    'deliveredBefore': 1,
    'deliveredWithSentinel': 2,
    'deliveredAfter': 1,
  };
  final recoveryCounts = artifact['recoveryCounts'];
  if (recoveryCounts is! Map ||
      recoveryCounts.keys
          .toSet()
          .difference(exactRecoveryCounts.keys.toSet())
          .isNotEmpty ||
      exactRecoveryCounts.keys
          .toSet()
          .difference(recoveryCounts.keys.toSet())
          .isNotEmpty ||
      exactRecoveryCounts.entries.any(
        (entry) => recoveryCounts[entry.key] != entry.value,
      )) {
    return const DeviceCriteriaResult.fail(
      'iOS notification recovery counts must prove exact A/C retirement',
    );
  }

  final checks = artifact['checks'];
  final requiredChecks =
      _notificationRequirements['payload_fast_path_ios_receiver']!;
  if (checks is! Map ||
      checks.keys.toSet().difference(requiredChecks).isNotEmpty ||
      requiredChecks.difference(checks.keys.toSet()).isNotEmpty) {
    return const DeviceCriteriaResult.fail(
      'iOS notification proof checks must match the exact TC-B12 schema',
    );
  }

  const evidenceKeys = <String>{
    'preparedApplication',
    'payloadProducer',
    'apnsPayload',
    'providerReceipt',
    'providerCleanupReceipt',
    'relayLog',
    'nseLog',
    'recipientLog',
    'uiAutomationLog',
    'stagedEnvelope',
    'recoveryPreparedApplication',
    'recoveryPayloadProducer',
    'recoveryApnsPayload',
    'recoveryProviderReceipt',
    'recoveryProviderCleanupReceipt',
    'notificationRecoveryReceipt',
    'recoveryRelayLog',
    'recoveryNseLog',
    'recoveryRecipientLog',
    'recoveryUiAutomationLog',
    'recoveryStagedEnvelope',
  };
  final evidence = artifact['evidenceSha256'];
  if (evidence is! Map ||
      evidence.keys.toSet().difference(evidenceKeys).isNotEmpty ||
      evidenceKeys.difference(evidence.keys.toSet()).isNotEmpty) {
    return const DeviceCriteriaResult.fail(
      'iOS notification proof evidenceSha256 fields must match the exact '
      'automation receipt schema',
    );
  }
  for (final key in evidenceKeys) {
    if (!_isLowercaseSha256(evidence[key])) {
      return DeviceCriteriaResult.fail(
        'iOS notification proof evidenceSha256.$key must be lowercase SHA-256',
      );
    }
  }
  if (evidence['preparedApplication'] !=
          artifact['preparedApplicationSha256'] ||
      evidence['payloadProducer'] != artifact['payloadProducerSha256'] ||
      evidence['apnsPayload'] != artifact['apnsPayloadSha256'] ||
      evidence['recoveryPreparedApplication'] !=
          artifact['preparedApplicationSha256'] ||
      evidence['recoveryPayloadProducer'] !=
          artifact['payloadProducerSha256'] ||
      evidence['recoveryApnsPayload'] !=
          artifact['recoveryApnsPayloadSha256']) {
    return const DeviceCriteriaResult.fail(
      'iOS notification proof generated-evidence digest chain is broken',
    );
  }

  return const DeviceCriteriaResult.pass(
    'iOS durable proof provenance and evidence digest chain are complete',
  );
}

String? _findNotificationSecretBearingField(
  Object? value, [
  String path = r'$',
]) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final normalized = key
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .toLowerCase();
      if (_notificationSecretKeys.contains(normalized) && entry.value != null) {
        return '$path.$key';
      }
      final nested = _findNotificationSecretBearingField(
        entry.value,
        '$path.$key',
      );
      if (nested != null) return nested;
    }
    return null;
  }
  if (value is Iterable) {
    var index = 0;
    for (final item in value) {
      final nested = _findNotificationSecretBearingField(item, '$path[$index]');
      if (nested != null) return nested;
      index += 1;
    }
    return null;
  }
  if (value is String &&
      (value.contains('BEGIN PRIVATE KEY') ||
          value.contains('BEGIN EC PRIVATE KEY'))) {
    return path;
  }
  return null;
}

const Set<String> _notificationSecretKeys = <String>{
  'token',
  'apnstoken',
  'fcmtoken',
  'ciphertext',
  'privatekey',
  'secret',
  'secretkey',
  'mnemonic',
  'authorization',
  'password',
};

bool _isLowercaseSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _isSafeNotificationProvenanceString(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value == value.trim() &&
    value.length <= 512 &&
    !value.contains(RegExp(r'[\x00-\x1f\x7f]'));

bool _isSafeNotificationRunToken(Object? value) =>
    value is String &&
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value);

const Map<String, Set<String>> _notificationRequirements =
    <String, Set<String>>{
      'tc_a6_replay_before_ack_custody': <String>{
        'realGoBridgeClient',
        'realRelay',
        'relayInboxSeeded',
        'replayBeforeAckObserved',
        'firstDrainAckPurgedRelay',
        'secondDrainNoDuplicateRender',
      },
      'tc_b11_payload_persist_pre_drain': <String>{
        'realPeerCiphertext',
        'realGoBridgeClient',
        'realRelay',
        'stagedEnvelopeRead',
        'visibleBeforeDrain',
        'noDrainBeforeVisibility',
        'laterDrainNoDuplicate',
      },
      'payload_fast_path_android_receiver': <String>{
        'androidReceiver',
        'fcmDelivered',
        'backgroundIsolateStaged',
        'airplaneModeBeforeTap',
        'messageVisibleFromStagedEnvelope',
        'noRelayDrainBeforeVisibility',
      },
      'payload_fast_path_cold_kill': <String>{
        'receiverTerminatedBeforeTap',
        'notificationTapColdLaunchedApp',
        'startupIngestRan',
        'messageVisibleFromStagedEnvelope',
        'noRelayDrainBeforeVisibility',
      },
      'payload_fast_path_ios_receiver': <String>{
        'iosReceiver',
        'apnsDelivered',
        'nseStagingOn',
        'nse04P0WithStagingOn',
        'airplaneModeBeforeTap',
        'messageVisibleFromStagedEnvelope',
        'noRelayDrainBeforeVisibility',
        'networkRestored',
        'appTerminatedAfterCapture',
        'badgePermissionEnabled',
        'providerPayloadBadgeAbsent',
        'deliveredNotificationBadgeWasNil',
        'recoveryClaimUnique',
        'runnerAbsoluteBadgeConverged',
        'exactOwnedNotificationRetired',
        'unrelatedSentinelSurvived',
        'zeroBadgePublished',
      },
    };

DeviceCriteriaResult _passedScenario(
  Map<String, Object?> artifact,
  String expected,
) {
  if (artifact['scenario'] != expected) {
    return DeviceCriteriaResult.fail(
      'artifact scenario ${artifact['scenario']} does not match $expected',
    );
  }
  if (artifact['status'] != 'passed') {
    return DeviceCriteriaResult.fail(
      '$expected has non-passing status ${artifact['status']}',
    );
  }
  return const DeviceCriteriaResult.pass('common metadata accepted');
}

List<String> _strings(Object? value) {
  if (value is! Iterable) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}

int _indexAfter(List<String> events, String event, int after) {
  if (after < -1) return -1;
  for (var index = after + 1; index < events.length; index++) {
    if (events[index] == event) return index;
  }
  return -1;
}

List<_MessageEventEvidence> _messageEventEvidence(Object? value) {
  if (value is! Iterable) return const <_MessageEventEvidence>[];
  final result = <_MessageEventEvidence>[];
  for (final item in value) {
    if (item is! Map) continue;
    final event = item['event'];
    final eventIndex = item['eventIndex'];
    final messageIdPrefix = item['messageIdPrefix'];
    if (event is String && eventIndex is int && messageIdPrefix is String) {
      result.add(
        _MessageEventEvidence(
          event: event,
          eventIndex: eventIndex,
          messageIdPrefix: messageIdPrefix,
        ),
      );
    }
  }
  return result;
}

_MessageEventEvidence? _findCorrelatedMessageEvent(
  List<_MessageEventEvidence> evidence, {
  required String event,
  required String messageIdPrefix,
  required List<String> events,
}) {
  for (final item in evidence) {
    if (item.event == event &&
        item.messageIdPrefix.toLowerCase() == messageIdPrefix.toLowerCase() &&
        item.eventIndex >= 0 &&
        item.eventIndex < events.length &&
        events[item.eventIndex] == event) {
      return item;
    }
  }
  return null;
}

final class _MessageEventEvidence {
  const _MessageEventEvidence({
    required this.event,
    required this.eventIndex,
    required this.messageIdPrefix,
  });

  final String event;
  final int eventIndex;
  final String messageIdPrefix;
}

bool _hasTwoDistinctNonemptyIds(Object? value) {
  final ids = _strings(
    value,
  ).map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
  return ids.length >= 2;
}

bool _hasDuplicates(List<String> values) =>
    values.toSet().length != values.length;

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
