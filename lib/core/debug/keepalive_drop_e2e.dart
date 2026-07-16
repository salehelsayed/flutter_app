import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/keepalive_drop_e2e_contract.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

typedef KeepaliveE2EResultWriter =
    Future<void> Function(Map<String, dynamic> result);

bool isKeepaliveDropE2EAction(Object? action) =>
    action == keepaliveDroppedSendAction ||
    action == keepaliveRecoveryObserveAction;

Future<void> runKeepaliveDropE2EAction({
  required Map<String, dynamic> config,
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  required KeepaliveE2EResultWriter writeResult,
}) async {
  final action = config['transport_action'];
  try {
    final result = action == keepaliveDroppedSendAction
        ? await _runDroppedSend(
            config: config,
            p2pService: p2pService,
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            messageRepo: messageRepo,
          )
        : await _observeRecovery(
            config: config,
            p2pService: p2pService,
            messageRepo: messageRepo,
            writeResult: writeResult,
          );
    await writeResult(result);
  } catch (error, stackTrace) {
    await writeResult(<String, dynamic>{
      'schema': action == keepaliveRecoveryObserveAction
          ? keepaliveRecoveryResultSchema
          : keepaliveDroppedSendResultSchema,
      'stepId': config['stepId'],
      'status': 'failed',
      'success': false,
      if (config['runId'] is String) 'runId': config['runId'],
      if (config['nonce'] is String) 'nonce': config['nonce'],
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
  } finally {
    setE2EFlowEventSink(null);
  }
}

Future<Map<String, dynamic>> _runDroppedSend({
  required Map<String, dynamic> config,
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
}) async {
  final request = config.cast<String, Object?>();
  final requestFailure = validateKeepaliveDroppedSendRequest(request);
  if (requestFailure != null) throw FormatException(requestFailure);
  if (p2pService is! PeerDropSignal) {
    throw StateError('production P2P service has no peer-drop signal');
  }
  final targetPeerId = config['targetPeerId']! as String;
  final text = config['text']! as String;
  final signal = p2pService as PeerDropSignal;
  final latchedBefore = signal.isPeerSuspectedDropped(targetPeerId);
  final connectedBefore = p2pService.isConnectedToPeer(targetPeerId);
  final localBefore = p2pService.isLocalPeer(targetPeerId);
  if (!latchedBefore || connectedBefore || localBefore) {
    throw StateError(
      'keepalive send precondition failed: latch=$latchedBefore '
      'connected=$connectedBefore local=$localBefore',
    );
  }

  final identity = await identityRepo.loadIdentity();
  final recipient = await contactRepo.getContact(targetPeerId);
  if (identity == null || recipient == null) {
    throw StateError('keepalive send identity/contact is unavailable');
  }

  final flow = <_CapturedKeepaliveEvent>[];
  setE2EFlowEventSink((payload) {
    flow.add(_CapturedKeepaliveEvent.fromPayload(payload));
  });
  final (sendResult, message) = await sendChatMessage(
    p2pService: p2pService,
    messageRepo: messageRepo,
    targetPeerId: targetPeerId,
    text: text,
    senderPeerId: identity.peerId,
    senderUsername: identity.username,
    bridge: bridge,
    recipientMlKemPublicKey: recipient.mlKemPublicKey,
  );
  setE2EFlowEventSink(null);
  if (sendResult != SendChatMessageResult.success || message == null) {
    throw StateError('real keepalive send failed with $sendResult');
  }

  final prefix = keepaliveMessageIdPrefix(message.id);
  final begin = _correlated(
    flow,
    'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
    prefix,
  );
  final custody = _correlated(flow, 'CHAT_MSG_SEND_CUSTODY_CONFIRMED', prefix);
  final skipIndex = flow.indexWhere(
    (event) => event.name == 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP',
  );
  if (begin == null ||
      custody == null ||
      skipIndex <= begin.index ||
      custody.index <= begin.index) {
    throw StateError('keepalive send events are missing or out of order');
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
  final attempted = flow
      .map((event) => event.name)
      .where(forbidden.contains)
      .toList(growable: false);
  if (attempted.isNotEmpty) {
    throw StateError('keepalive send attempted a direct leg: $attempted');
  }
  final custodyLatencyMs = custody.event.observedAt
      .difference(begin.event.observedAt)
      .inMilliseconds;
  if (custodyLatencyMs < 0 || custodyLatencyMs >= 1000) {
    throw StateError('keepalive relay custody exceeded one second');
  }
  final latchedAfter = signal.isPeerSuspectedDropped(targetPeerId);
  if (!latchedAfter) {
    throw StateError('keepalive drop latch cleared during the dropped send');
  }

  return <String, dynamic>{
    'schema': keepaliveDroppedSendResultSchema,
    'profileId': keepaliveDropProfileId,
    'scenario': keepaliveDropScenarioId,
    'role': 'sender',
    'stepId': config['stepId'],
    'status': 'complete',
    'success': true,
    'runId': config['runId'],
    'nonce': config['nonce'],
    'messageId': message.id,
    'messageIdPrefix': prefix,
    'text': text,
    'transport': message.transport,
    'messageStatus': message.status,
    'dropLatchedBeforeSend': latchedBefore,
    'dropLatchedAfterSend': latchedAfter,
    'connectedBeforeSend': connectedBefore,
    'localBeforeSend': localBefore,
    'sendWindowEvents': flow.map((event) => event.name).toList(growable: false),
    'messageEvents': <Map<String, Object?>>[
      begin.event.toEvidence(
        'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
        prefix,
        begin.index,
      ),
      custody.event.toEvidence(
        'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
        prefix,
        custody.index,
      ),
    ],
    'custodyLatencyMs': custodyLatencyMs,
  };
}

Future<Map<String, dynamic>> _observeRecovery({
  required Map<String, dynamic> config,
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required KeepaliveE2EResultWriter writeResult,
}) async {
  final request = config.cast<String, Object?>();
  final requestFailure = validateKeepaliveRecoveryRequest(request);
  if (requestFailure != null) throw FormatException(requestFailure);
  if (p2pService is! PeerDropSignal) {
    throw StateError('production P2P service has no peer-drop signal');
  }
  final targetPeerId = config['targetPeerId']! as String;
  final messageId = config['messageId']! as String;
  final prefix = keepaliveMessageIdPrefix(messageId);
  final targetPrefix = targetPeerId.length > 10
      ? targetPeerId.substring(0, 10)
      : targetPeerId;
  final signal = p2pService as PeerDropSignal;
  if (!signal.isPeerSuspectedDropped(targetPeerId)) {
    throw StateError('keepalive recovery observer armed without a drop latch');
  }

  final flow = <_CapturedKeepaliveEvent>[];
  setE2EFlowEventSink((payload) {
    flow.add(_CapturedKeepaliveEvent.fromPayload(payload));
  });
  await writeResult(<String, dynamic>{
    'schema': keepaliveRecoveryResultSchema,
    'profileId': keepaliveDropProfileId,
    'scenario': keepaliveDropScenarioId,
    'role': 'sender',
    'stepId': config['stepId'],
    'status': 'armed',
    'success': true,
    'runId': config['runId'],
    'nonce': config['nonce'],
    'messageIdPrefix': prefix,
    'dropLatched': true,
  });

  final timeoutMs = ((config['timeoutMs'] as num?)?.toInt() ?? 120000)
      .clamp(1000, 180000)
      .toInt();
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (DateTime.now().isBefore(deadline)) {
    final receipt = _correlated(flow, 'DELIVERY_RECEIPT_APPLIED', prefix);
    final pingIndex = flow.indexWhere(
      (event) =>
          event.name == 'P2P_SERVICE_PEER_PING_SUCCESS' &&
          event.peerIdPrefix == targetPrefix,
    );
    final row = await messageRepo.getMessage(messageId);
    final latchCleared = !signal.isPeerSuspectedDropped(targetPeerId);
    if (receipt != null &&
        pingIndex >= 0 &&
        latchCleared &&
        row?.status == 'delivered') {
      setE2EFlowEventSink(null);
      return <String, dynamic>{
        'schema': keepaliveRecoveryResultSchema,
        'profileId': keepaliveDropProfileId,
        'scenario': keepaliveDropScenarioId,
        'role': 'sender',
        'stepId': config['stepId'],
        'status': 'complete',
        'success': true,
        'runId': config['runId'],
        'nonce': config['nonce'],
        'messageIdPrefix': prefix,
        'dropLatchedAfterRecovery': false,
        'messageStatus': row!.status,
        'events': flow.map((event) => event.name).toList(growable: false),
        'receiptEvent': receipt.event.toEvidence(
          'DELIVERY_RECEIPT_APPLIED',
          prefix,
          receipt.index,
        ),
        'postDropPeerPingObserved': true,
      };
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError('keepalive recovery receipt/re-arm timed out');
}

({int index, _CapturedKeepaliveEvent event})? _correlated(
  List<_CapturedKeepaliveEvent> events,
  String name,
  String messageIdPrefix,
) {
  final index = events.indexWhere(
    (event) => event.name == name && event.messageIdPrefix == messageIdPrefix,
  );
  if (index < 0) return null;
  return (index: index, event: events[index]);
}

final class _CapturedKeepaliveEvent {
  const _CapturedKeepaliveEvent({
    required this.name,
    required this.observedAt,
    required this.messageIdPrefix,
    required this.peerIdPrefix,
  });

  factory _CapturedKeepaliveEvent.fromPayload(Map<String, dynamic> payload) {
    final name = payload['event'];
    final observedAt = DateTime.tryParse('${payload['ts']}');
    if (name is! String || name.isEmpty || observedAt == null) {
      throw const FormatException('keepalive flow event is malformed');
    }
    final details = payload['details'];
    final rawId = details is Map ? details['id'] : null;
    final rawPeer = details is Map ? details['peerId'] : null;
    return _CapturedKeepaliveEvent(
      name: name,
      observedAt: observedAt.toUtc(),
      messageIdPrefix:
          rawId is String && RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(rawId)
          ? rawId.toLowerCase()
          : null,
      peerIdPrefix: rawPeer is String && rawPeer.length <= 12 ? rawPeer : null,
    );
  }

  final String name;
  final DateTime observedAt;
  final String? messageIdPrefix;
  final String? peerIdPrefix;

  Map<String, Object?> toEvidence(
    String expectedEvent,
    String prefix,
    int eventIndex,
  ) => <String, Object?>{
    'event': expectedEvent,
    'eventIndex': eventIndex,
    'messageIdPrefix': prefix,
  };
}
