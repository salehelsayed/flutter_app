import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../tool/sims/device_criteria.dart';
import 'sims_runtime_protocol.dart';

/// Runtime IDs and roles shared by the three Plan 258 Android transport proofs.
///
/// This file deliberately owns only evidence capture and fail-closed protocol
/// validation. It does not construct a fake P2P graph and it does not turn a
/// host fixture into a device proof. A dispatcher may call these builders only
/// after binding them to the production bridge, repositories, keepalive, and OS
/// connectivity source on the selected Android targets.
const String simsAndroidConnectivityRestoreScenarioId =
    'android.connectivity_restore_inbox_drain';
const String simsAndroidKeepaliveDropScenarioId =
    'android.keepalive_drop_skip_direct';
const String simsAndroidWakeTokenDirectionalityScenarioId =
    'android.wake_token_directionality';
const String simsAndroidWakeTokenProfileId = 'android.e2e.wake_token';

const String simsTransportSenderRole = 'sender';
const String simsTransportReceiverRole = 'receiver';
const String simsWakeTokenIssuerRole = 'issuer';
const String simsWakeTokenPresenterRole = 'presenter';

/// Validates the immutable part of a two-peer runtime invocation.
///
/// The universal runtime protocol already validates schema, profile equality,
/// run ID, and nonce. This check prevents a valid APK/profile from silently
/// executing the wrong transport role or using the standard build for the
/// emission-gated wake-token proof.
String? validateAndroidTransportInvocation(SimsRuntimeInvocation invocation) {
  final allowedRoles = switch (invocation.scenarioId) {
    simsAndroidConnectivityRestoreScenarioId ||
    simsAndroidKeepaliveDropScenarioId => const <String>{
      simsTransportSenderRole,
      simsTransportReceiverRole,
    },
    simsAndroidWakeTokenDirectionalityScenarioId => const <String>{
      simsWakeTokenIssuerRole,
      simsWakeTokenPresenterRole,
    },
    _ => null,
  };
  if (allowedRoles == null) {
    return 'unsupported Android transport scenario ${invocation.scenarioId}';
  }

  final expectedProfile = switch (invocation.scenarioId) {
    simsAndroidConnectivityRestoreScenarioId ||
    simsAndroidKeepaliveDropScenarioId => simsAndroidMainProfileId,
    simsAndroidWakeTokenDirectionalityScenarioId =>
      simsAndroidWakeTokenProfileId,
    _ => simsAndroidStandardProfileId,
  };
  if (invocation.profileId != expectedProfile) {
    return '${invocation.scenarioId} requires profile $expectedProfile';
  }
  if (!allowedRoles.contains(invocation.role)) {
    return '${invocation.scenarioId} does not support role ${invocation.role}';
  }
  return null;
}

/// A process-local capture of sanitized production flow-event names and times.
///
/// [emitFlowEvent] sanitizes details before invoking its debug sink. This class
/// drops every detail except a safe eight-hex message-ID prefix. Keepalive must
/// bind custody and recovery to the message returned by the real send; retaining
/// that already-truncated prefix is sufficient without retaining peer IDs,
/// messages, tokens, relay addresses, keys, or a full message ID. Exactly one
/// capture may own the process-wide sink at a time.
final class AndroidTransportFlowCapture {
  final List<_CapturedFlowEvent> _events = <_CapturedFlowEvent>[];
  bool _started = false;

  int get checkpoint => _events.length;

  void start() {
    if (_started) throw StateError('transport flow capture is already started');
    if (_activeFlowCapture != null) {
      throw StateError('another transport flow capture already owns the sink');
    }
    _activeFlowCapture = this;
    _started = true;
    debugSetFlowEventSink(recordSanitizedFlowEvent);
  }

  void stop() {
    if (!_started) return;
    if (identical(_activeFlowCapture, this)) {
      debugSetFlowEventSink(null);
      _activeFlowCapture = null;
    }
    _started = false;
  }

  @visibleForTesting
  void recordSanitizedFlowEvent(Map<String, dynamic> payload) {
    if (!_started) {
      throw StateError('transport flow capture must be started before use');
    }
    final event = payload['event'];
    if (event is! String || event.trim().isEmpty) {
      throw StateError('production flow event has no event name');
    }
    final details = payload['details'];
    final rawMessageId = details is Map ? details['id'] : null;
    final messageIdPrefix =
        rawMessageId is String &&
            RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(rawMessageId)
        ? rawMessageId.toLowerCase()
        : null;
    _events.add(
      _CapturedFlowEvent(
        name: event,
        observedAt: DateTime.now().toUtc(),
        messageIdPrefix: messageIdPrefix,
      ),
    );
  }

  List<String> namesSince(int checkpoint) => List<String>.unmodifiable(
    _eventsFrom(checkpoint).map((event) => event.name),
  );

  List<String> _namesBetween(int start, int end) => List<String>.unmodifiable(
    _eventsBetween(start, end).map((event) => event.name),
  );

  int elapsedMilliseconds({
    required int checkpoint,
    int? endCheckpoint,
    required String from,
    required String to,
    String? messageIdPrefix,
  }) {
    final events = _eventsBetween(checkpoint, endCheckpoint ?? _events.length);
    bool matches(_CapturedFlowEvent event, String name) =>
        event.name == name &&
        (messageIdPrefix == null || event.messageIdPrefix == messageIdPrefix);
    final fromIndex = events.indexWhere((event) => matches(event, from));
    if (fromIndex < 0) {
      throw StateError('required production event $from was not captured');
    }
    final toIndex = events.indexWhere(
      (event) => matches(event, to),
      fromIndex + 1,
    );
    if (toIndex < 0) {
      throw StateError(
        'required production event $to was not captured after $from',
      );
    }
    return events[toIndex].observedAt
        .difference(events[fromIndex].observedAt)
        .inMilliseconds;
  }

  List<_CapturedFlowEvent> _eventsFrom(int checkpoint) {
    return _eventsBetween(checkpoint, _events.length);
  }

  List<_CapturedFlowEvent> _eventsBetween(int start, int end) {
    if (start < 0 || start > _events.length) {
      throw RangeError.range(start, 0, _events.length, 'start');
    }
    if (end < start || end > _events.length) {
      throw RangeError.range(end, start, _events.length, 'end');
    }
    return _events.sublist(start, end);
  }

  int _correlatedEventIndex({
    required int start,
    required int end,
    required String event,
    required String messageIdPrefix,
  }) {
    for (var index = start; index < end; index++) {
      final candidate = _events[index];
      if (candidate.name == event &&
          candidate.messageIdPrefix == messageIdPrefix) {
        return index;
      }
    }
    return -1;
  }
}

AndroidTransportFlowCapture? _activeFlowCapture;

const String _localEvidenceSchema = 'mknoon.sims.transport-local-evidence.v1';

/// Sender-local half of the connectivity proof. It can never emit a terminal
/// passing artifact; the host must merge it with the receiver-local half from
/// the same run.
final class ConnectivitySenderEvidenceBuilder {
  ConnectivitySenderEvidenceBuilder(this.invocation) {
    _requireInvocation(
      invocation,
      scenarioId: simsAndroidConnectivityRestoreScenarioId,
      role: simsTransportSenderRole,
    );
  }

  final SimsRuntimeInvocation invocation;
  int _messagesQueued = 0;

  /// Record only sends that the real sender repository/bridge accepted for this
  /// run. A dispatcher must not populate this from staged config values.
  void recordQueuedMessage() => _messagesQueued++;

  Map<String, Object?> completeLocal() {
    if (_messagesQueued != 3) {
      throw StateError(
        'connectivity sender must observe exactly three accepted messages',
      );
    }
    return _localEvidence(invocation, <String, Object?>{
      'messagesQueued': _messagesQueued,
    });
  }
}

/// Receiver-local half of the connectivity proof. The restore window excludes
/// startup connectivity events and derives resume count from production events.
final class ConnectivityReceiverEvidenceBuilder {
  ConnectivityReceiverEvidenceBuilder({
    required this.invocation,
    required this.flow,
  }) {
    _requireInvocation(
      invocation,
      scenarioId: simsAndroidConnectivityRestoreScenarioId,
      role: simsTransportReceiverRole,
    );
  }

  final SimsRuntimeInvocation invocation;
  final AndroidTransportFlowCapture flow;
  int? _restoreWindow;
  int _messagesRendered = 0;

  /// Call after Android has reported the disconnected edge and before the host
  /// re-enables Wi-Fi. Startup connectivity events are thereby excluded.
  void beginForegroundRestoreWindow() {
    if (_restoreWindow != null) {
      throw StateError('connectivity restore window was already started');
    }
    _restoreWindow = flow.checkpoint;
  }

  /// Record only messages observed in the real receiver repository/UI stream.
  void recordRenderedMessage() => _messagesRendered++;

  Map<String, Object?> completeLocal() {
    final checkpoint = _restoreWindow;
    if (checkpoint == null) {
      throw StateError('connectivity restore window never started');
    }
    if (_messagesRendered != 3) {
      throw StateError(
        'connectivity receiver must observe exactly three rendered messages',
      );
    }
    final events = flow.namesSince(checkpoint);
    return _localEvidence(invocation, <String, Object?>{
      'messagesRendered': _messagesRendered,
      'events': events,
      'resumeEventsDuringWindow': events
          .where((event) => event.startsWith('APP_LIFECYCLE_RESUME_'))
          .length,
    });
  }
}

/// Merges independently captured sender and receiver observations. Only this
/// host-side step may emit `status: passed`.
Map<String, Object?> finalizeConnectivityRestoreEvidence({
  required Map<String, Object?> senderEvidence,
  required Map<String, Object?> receiverEvidence,
  required Iterable<String> deviceIds,
}) {
  _requireLocalPair(
    senderEvidence,
    receiverEvidence,
    scenarioId: simsAndroidConnectivityRestoreScenarioId,
    leftRole: simsTransportSenderRole,
    rightRole: simsTransportReceiverRole,
  );
  final artifact = <String, Object?>{
    'scenario': simsAndroidConnectivityRestoreScenarioId,
    'status': 'passed',
    'deviceIds': List<String>.unmodifiable(deviceIds),
    'messagesQueued': senderEvidence['messagesQueued'],
    'messagesRendered': receiverEvidence['messagesRendered'],
    'events': receiverEvidence['events'],
    'resumeEventsDuringWindow': receiverEvidence['resumeEventsDuringWindow'],
  };
  return _validated(artifact, validateConnectivityRestoreArtifact(artifact));
}

final class KeepaliveDropEvidenceBuilder {
  KeepaliveDropEvidenceBuilder({required this.invocation, required this.flow})
    : _campaignStart = flow.checkpoint {
    _requireInvocation(
      invocation,
      scenarioId: simsAndroidKeepaliveDropScenarioId,
      role: simsTransportSenderRole,
    );
  }

  final SimsRuntimeInvocation invocation;
  final AndroidTransportFlowCapture flow;
  final int _campaignStart;
  int? _sendWindow;
  int? _sendWindowEnd;
  String? _messageIdPrefix;

  /// Call only after the production `KEEPALIVE_PEER_DROP` event has been
  /// observed and immediately before invoking the real send use case.
  void beginDroppedPeerSendWindow() {
    final campaignEvents = flow.namesSince(_campaignStart);
    if (!campaignEvents.contains('KEEPALIVE_PEER_DROP')) {
      throw StateError(
        'cannot begin keepalive send before KEEPALIVE_PEER_DROP',
      );
    }
    if (_sendWindow != null) {
      throw StateError('keepalive send window was already started');
    }
    _sendWindow = flow.checkpoint;
  }

  /// Close the exact send window after the real send returns and bind its
  /// production begin/custody observations to that returned message ID.
  /// Recovery and keepalive re-arm happen after this checkpoint and therefore
  /// cannot pollute the no-discover/no-dial window.
  void endDroppedPeerSendWindow({required String messageId}) {
    final sendWindow = _sendWindow;
    if (sendWindow == null) {
      throw StateError('keepalive send window never started');
    }
    if (_sendWindowEnd != null) {
      throw StateError('keepalive send window was already ended');
    }
    final messageIdPrefix = _safeMessageIdPrefix(messageId);
    final end = flow.checkpoint;
    for (final event in const <String>[
      'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
      'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
    ]) {
      if (flow._correlatedEventIndex(
            start: sendWindow,
            end: end,
            event: event,
            messageIdPrefix: messageIdPrefix,
          ) <
          0) {
        throw StateError(
          'required production event $event was not captured for message '
          '$messageIdPrefix',
        );
      }
    }
    _messageIdPrefix = messageIdPrefix;
    _sendWindowEnd = end;
  }

  Map<String, Object?> completeLocal() {
    final sendWindow = _sendWindow;
    if (sendWindow == null) {
      throw StateError('keepalive send window never started');
    }
    final sendWindowEnd = _sendWindowEnd;
    final messageIdPrefix = _messageIdPrefix;
    if (sendWindowEnd == null || messageIdPrefix == null) {
      throw StateError('keepalive send window never ended with a message ID');
    }
    final campaignEnd = flow.checkpoint;
    final messageEvents = <Map<String, Object?>>[];
    for (final requirement in <({String event, int start, int end})>[
      (
        event: 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
        start: sendWindow,
        end: sendWindowEnd,
      ),
      (
        event: 'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
        start: sendWindow,
        end: sendWindowEnd,
      ),
      (
        event: 'DELIVERY_RECEIPT_APPLIED',
        start: sendWindowEnd,
        end: campaignEnd,
      ),
    ]) {
      final absoluteIndex = flow._correlatedEventIndex(
        start: requirement.start,
        end: requirement.end,
        event: requirement.event,
        messageIdPrefix: messageIdPrefix,
      );
      if (absoluteIndex < 0) {
        throw StateError(
          'required production event ${requirement.event} was not captured '
          'for message $messageIdPrefix',
        );
      }
      messageEvents.add(<String, Object?>{
        'event': requirement.event,
        'eventIndex': absoluteIndex - _campaignStart,
        'messageIdPrefix': messageIdPrefix,
      });
    }
    final events = flow.namesSince(_campaignStart);
    final sendWindowEvents = flow._namesBetween(sendWindow, sendWindowEnd);
    return _localEvidence(invocation, <String, Object?>{
      'events': events,
      'sendWindowEvents': sendWindowEvents,
      'messageIdPrefix': messageIdPrefix,
      'messageEvents': messageEvents,
      'custodyLatencyMs': flow.elapsedMilliseconds(
        checkpoint: sendWindow,
        endCheckpoint: sendWindowEnd,
        from: 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
        to: 'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
        messageIdPrefix: messageIdPrefix,
      ),
    });
  }
}

Map<String, Object?> finalizeKeepaliveDropEvidence({
  required Map<String, Object?> senderEvidence,
  required Iterable<String> deviceIds,
}) {
  _requireLocalEvidence(
    senderEvidence,
    scenarioId: simsAndroidKeepaliveDropScenarioId,
    role: simsTransportSenderRole,
  );
  final artifact = <String, Object?>{
    'scenario': simsAndroidKeepaliveDropScenarioId,
    'status': 'passed',
    'deviceIds': List<String>.unmodifiable(deviceIds),
    'events': senderEvidence['events'],
    'sendWindowEvents': senderEvidence['sendWindowEvents'],
    'messageIdPrefix': senderEvidence['messageIdPrefix'],
    'messageEvents': senderEvidence['messageEvents'],
    'custodyLatencyMs': senderEvidence['custodyLatencyMs'],
  };
  return _validated(artifact, validateKeepaliveDropArtifact(artifact));
}

/// Secret-safe wake-token evidence. Raw tokens are hashed immediately and are
/// never retained as fields, flow details, or artifact values.
///
/// The caller still has to source each observation from its named production
/// boundary: the native register dispatch, `ReceivedWakeTokenStore`, and the
/// real `inbox:store` bridge dispatch. Reusing one local store read for multiple
/// observations would not close the device proof.
final class WakeTokenIssuerEvidenceBuilder {
  WakeTokenIssuerEvidenceBuilder(this.invocation) {
    _requireInvocation(
      invocation,
      scenarioId: simsAndroidWakeTokenDirectionalityScenarioId,
      role: simsWakeTokenIssuerRole,
    );
  }

  final SimsRuntimeInvocation invocation;
  String? _registeredTokenSha256;

  void observeNativeRegistration(String token) {
    _registeredTokenSha256 = _hashToken(token);
  }

  Map<String, Object?> completeLocal() {
    if (_registeredTokenSha256 == null) {
      throw StateError('native wake-token registration was not observed');
    }
    return _localEvidence(invocation, <String, Object?>{
      'registeredTokenSha256': _registeredTokenSha256,
    });
  }
}

final class WakeTokenPresenterEvidenceBuilder {
  WakeTokenPresenterEvidenceBuilder(this.invocation) {
    _requireInvocation(
      invocation,
      scenarioId: simsAndroidWakeTokenDirectionalityScenarioId,
      role: simsWakeTokenPresenterRole,
    );
  }

  final SimsRuntimeInvocation invocation;
  String? _storedTokenSha256;
  String? _attachedTokenSha256;

  void observeReceivedTokenStore(String token) {
    _storedTokenSha256 = _hashToken(token);
  }

  void observeInboxStoreAttachment(String token) {
    _attachedTokenSha256 = _hashToken(token);
  }

  Map<String, Object?> completeLocal() {
    if (_storedTokenSha256 == null || _attachedTokenSha256 == null) {
      throw StateError(
        'received-store and inbox-attachment wake-token observations are required',
      );
    }
    return _localEvidence(invocation, <String, Object?>{
      'storedTokenSha256': _storedTokenSha256,
      'attachedTokenSha256': _attachedTokenSha256,
    });
  }
}

Map<String, Object?> finalizeWakeTokenDirectionalityEvidence({
  required Map<String, Object?> issuerEvidence,
  required Map<String, Object?> presenterEvidence,
  required Iterable<String> deviceIds,
}) {
  _requireLocalPair(
    issuerEvidence,
    presenterEvidence,
    scenarioId: simsAndroidWakeTokenDirectionalityScenarioId,
    leftRole: simsWakeTokenIssuerRole,
    rightRole: simsWakeTokenPresenterRole,
  );
  final artifact = <String, Object?>{
    'scenario': simsAndroidWakeTokenDirectionalityScenarioId,
    'status': 'passed',
    'deviceIds': List<String>.unmodifiable(deviceIds),
    'registeredTokenSha256': issuerEvidence['registeredTokenSha256'],
    'storedTokenSha256': presenterEvidence['storedTokenSha256'],
    'attachedTokenSha256': presenterEvidence['attachedTokenSha256'],
  };
  return _validated(artifact, validateWakeTokenArtifact(artifact));
}

Map<String, Object?> _localEvidence(
  SimsRuntimeInvocation invocation,
  Map<String, Object?> observations,
) => Map<String, Object?>.unmodifiable(<String, Object?>{
  'schema': _localEvidenceSchema,
  'status': 'observed',
  'scenario': invocation.scenarioId,
  'role': invocation.role,
  'runId': invocation.runId,
  'invocationNonce': invocation.nonce,
  ...observations,
});

void _requireInvocation(
  SimsRuntimeInvocation invocation, {
  required String scenarioId,
  required String role,
}) {
  final error = validateAndroidTransportInvocation(invocation);
  if (error != null) throw StateError(error);
  if (invocation.scenarioId != scenarioId || invocation.role != role) {
    throw StateError('$scenarioId requires local role $role');
  }
}

void _requireLocalEvidence(
  Map<String, Object?> evidence, {
  required String scenarioId,
  required String role,
}) {
  if (evidence['schema'] != _localEvidenceSchema ||
      evidence['status'] != 'observed' ||
      evidence['scenario'] != scenarioId ||
      evidence['role'] != role ||
      evidence['runId'] is! String ||
      (evidence['runId']! as String).isEmpty ||
      evidence['invocationNonce'] is! String ||
      (evidence['invocationNonce']! as String).isEmpty) {
    throw StateError('$scenarioId $role local evidence is invalid');
  }
}

void _requireLocalPair(
  Map<String, Object?> left,
  Map<String, Object?> right, {
  required String scenarioId,
  required String leftRole,
  required String rightRole,
}) {
  _requireLocalEvidence(left, scenarioId: scenarioId, role: leftRole);
  _requireLocalEvidence(right, scenarioId: scenarioId, role: rightRole);
  if (left['runId'] != right['runId']) {
    throw StateError('$scenarioId role evidence belongs to different runs');
  }
}

Map<String, Object?> _validated(
  Map<String, Object?> artifact,
  DeviceCriteriaResult validation,
) {
  if (!validation.ok) {
    throw StateError(
      'Android transport evidence rejected: ${validation.detail}',
    );
  }
  return Map<String, Object?>.unmodifiable(artifact);
}

String _hashToken(String token) {
  if (token.isEmpty) throw StateError('wake token observation is empty');
  return sha256.convert(utf8.encode(token)).toString();
}

String _safeMessageIdPrefix(String messageId) {
  if (messageId.length < 8) {
    throw StateError('keepalive send returned an invalid message ID');
  }
  final prefix = messageId.substring(0, 8).toLowerCase();
  if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(prefix)) {
    throw StateError('keepalive send returned a non-UUID message ID');
  }
  return prefix;
}

final class _CapturedFlowEvent {
  const _CapturedFlowEvent({
    required this.name,
    required this.observedAt,
    required this.messageIdPrefix,
  });

  final String name;
  final DateTime observedAt;
  final String? messageIdPrefix;
}
