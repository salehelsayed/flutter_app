import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/chat_console_logger.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Interactive send budget for local WiFi attempts.
const Duration interactiveLocalBudget = Duration(milliseconds: 1500);

/// Interactive send budget for the overall direct send path.
const Duration interactiveDirectBudget = Duration(seconds: 4);

/// Result of sending a chat message.
enum SendChatMessageResult {
  success,
  nodeNotRunning,
  invalidMessage,
  peerNotFound,
  dialFailed,
  sendFailed,
}

const _uuid = Uuid();

/// Sends a chat message to a contact via P2P and persists it locally.
///
/// 1. Validates text is non-empty
/// 2. Checks P2P node is running
/// 3. Builds MessagePayload with UUID
/// 4. Serializes to JSON envelope
/// 5. Discovers peer, dials, sends via p2pService (with 3x retries)
/// 6. Persists via messageRepo.saveMessage()
///
/// Returns (result, ConversationMessage?) — message is non-null on success or failure (persisted).
Future<(SendChatMessageResult, ConversationMessage?)> sendChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String? messageId,
  String? timestamp,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
}) async {
  final targetPrefix = targetPeerId.length > 10
      ? targetPeerId.substring(0, 10)
      : targetPeerId;
  final textPreview = buildTextPreview(text);

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_START',
    details: {'targetPeerId': targetPrefix, 'textPreview': textPreview},
  );

  // 1. Validate
  if (text.trim().isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {'reason': 'empty_text'},
    );
    return (SendChatMessageResult.invalidMessage, null);
  }

  // 2. Check P2P node
  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_NODE_NOT_RUNNING',
      details: {},
    );
    return (SendChatMessageResult.nodeNotRunning, null);
  }

  // 3. Build payload
  final resolvedMessageId = messageId ?? _uuid.v4();
  final resolvedTimestamp =
      timestamp ?? DateTime.now().toUtc().toIso8601String();

  final payload = MessagePayload(
    id: resolvedMessageId,
    text: text,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    timestamp: resolvedTimestamp,
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'queued',
    text: text,
  );

  // 4. Serialize (v2 encrypted envelope if ML-KEM key available, v1 plaintext otherwise)
  String jsonString;
  if (bridge != null && recipientMlKemPublicKey != null) {
    try {
      final innerJson = payload.toInnerJson();
      final encryptResult = await callEncryptMessage(
        bridge: bridge,
        recipientMlKemPublicKey: recipientMlKemPublicKey,
        plaintext: innerJson,
      );
      if (encryptResult['ok'] != true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_ENCRYPT_FAILED',
          details: {
            'errorCode': encryptResult['errorCode'],
            'errorMessage': encryptResult['errorMessage'],
          },
        );
        return (SendChatMessageResult.sendFailed, null);
      }
      jsonString = MessagePayload.buildEncryptedEnvelope(
        senderPeerId: senderPeerId,
        kem: encryptResult['kem'] as String,
        ciphertext: encryptResult['ciphertext'] as String,
        nonce: encryptResult['nonce'] as String,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_ENCRYPT_ERROR',
        details: {'error': e.toString()},
      );
      return (SendChatMessageResult.sendFailed, null);
    }
  } else {
    jsonString = payload.toJson();
  }

  logChatWireEnvelope(
    direction: 'OUT',
    messageId: resolvedMessageId,
    wireJson: jsonString,
  );

  // 4.5. Check for existing connected peer first (connection reuse).
  // If the peer is already connected, try to send directly without
  // rediscovering — this is the fastest interactive path.
  final isAlreadyConnected = p2pService.currentState.connections
      .any((c) => c.peerId == targetPeerId);

  if (isAlreadyConnected) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_REUSE_CONNECTION',
      details: {'targetPeerId': targetPrefix},
    );
    try {
      final sendResult = await p2pService.sendMessageWithReply(
        targetPeerId,
        jsonString,
        timeoutMs: interactiveDirectBudget.inMilliseconds,
      );
      if (sendResult.sent) {
        final status = sendResult.acknowledged ? 'delivered' : 'sent';
        final message = payload.toConversationMessage(
          contactPeerId: targetPeerId,
          isIncoming: false,
          status: status,
        );
        await messageRepo.saveMessage(message);
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_SUCCESS',
          details: {
            'id': resolvedMessageId.substring(0, 8),
            'status': status,
            'via': 'reuse',
            'textPreview': textPreview,
          },
        );
        logChatOutgoing(
          messageId: resolvedMessageId,
          toPeerId: targetPeerId,
          status: status,
          text: text,
        );
        return (SendChatMessageResult.success, message);
      }
    } catch (_) {
      // Connection reuse failed — fall through to race
    }
  }

  // 5. Race: local WiFi and direct discover/dial/send in parallel.
  // The first successful path wins and is the only one to persist.
  final isLocalPeer = p2pService.isLocalPeer(targetPeerId);

  // Build race futures
  final raceFutures = <Future<_RaceResult>>[];

  // Local WiFi path (bounded by interactiveLocalBudget)
  if (isLocalPeer) {
    raceFutures.add(
      _tryLocalSend(p2pService, targetPeerId, jsonString, senderPeerId)
          .timeout(interactiveLocalBudget, onTimeout: () => _RaceResult.failed('local_timeout')),
    );
  }

  // Direct discover/dial/send path (bounded by interactiveDirectBudget)
  raceFutures.add(
    _tryDirectSend(p2pService, targetPeerId, jsonString)
        .timeout(interactiveDirectBudget, onTimeout: () => _RaceResult.failed('direct_timeout')),
  );

  // Race: first successful result wins.
  // We use a completer to commit only the first success.
  final completer = Completer<_RaceResult>();
  var pendingCount = raceFutures.length;
  final failures = <String>[];

  for (final future in raceFutures) {
    future.then((result) {
      if (result.success && !completer.isCompleted) {
        completer.complete(result);
      } else {
        failures.add(result.reason ?? 'unknown');
        pendingCount--;
        if (pendingCount <= 0 && !completer.isCompleted) {
          // All paths failed
          completer.complete(_RaceResult.failed(failures.join(', ')));
        }
      }
    }).catchError((Object e) {
      failures.add(e.toString());
      pendingCount--;
      if (pendingCount <= 0 && !completer.isCompleted) {
        completer.complete(_RaceResult.failed(failures.join(', ')));
      }
    });
  }

  final raceResult = await completer.future;

  if (raceResult.success) {
    final status = raceResult.acknowledged ? 'delivered' : 'sent';
    final message = payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: status,
    );
    // Persist only once for this messageId
    if (!await messageRepo.messageExists(resolvedMessageId)) {
      await messageRepo.saveMessage(message);
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_SUCCESS',
      details: {
        'id': resolvedMessageId.substring(0, 8),
        'status': status,
        'via': raceResult.via,
        'textPreview': textPreview,
      },
    );
    logChatOutgoing(
      messageId: resolvedMessageId,
      toPeerId: targetPeerId,
      status: status,
      text: text,
    );
    return (SendChatMessageResult.success, message);
  }

  // All active paths failed — try offline inbox fallback once.
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_RACE_ALL_FAILED',
    details: {'reason': raceResult.reason ?? 'unknown'},
  );

  try {
    final storedInInbox = await p2pService.storeInInbox(
      targetPeerId,
      jsonString,
    );
    if (storedInInbox) {
      final deliveredMessage = payload.toConversationMessage(
        contactPeerId: targetPeerId,
        isIncoming: false,
        status: 'delivered',
      );
      if (!await messageRepo.messageExists(resolvedMessageId)) {
        await messageRepo.saveMessage(deliveredMessage);
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_SUCCESS',
        details: {
          'id': resolvedMessageId.substring(0, 8),
          'status': 'delivered',
          'via': 'inbox',
          'textPreview': textPreview,
        },
      );
      logChatOutgoing(
        messageId: resolvedMessageId,
        toPeerId: targetPeerId,
        status: 'delivered',
        text: text,
      );
      return (SendChatMessageResult.success, deliveredMessage);
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INBOX_FALLBACK_ERROR',
      details: {'error': e.toString()},
    );
  }

  // Inbox fallback failed — persist with failed status.
  final failedMessage = payload.toConversationMessage(
    contactPeerId: targetPeerId,
    isIncoming: false,
    status: 'failed',
  );
  if (!await messageRepo.messageExists(resolvedMessageId)) {
    await messageRepo.saveMessage(failedMessage);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_FAILED',
    details: {
      'id': resolvedMessageId.substring(0, 8),
      'reason': raceResult.reason ?? 'unknown',
      'textPreview': textPreview,
    },
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'failed',
    text: text,
  );
  return (SendChatMessageResult.sendFailed, failedMessage);
}

/// Internal result of a single send path in the race.
class _RaceResult {
  final bool success;
  final bool acknowledged;
  final String? via;
  final String? reason;

  const _RaceResult._({
    required this.success,
    this.acknowledged = false,
    this.via,
    this.reason,
  });

  factory _RaceResult.succeeded({required String via, bool acknowledged = false}) =>
      _RaceResult._(success: true, acknowledged: acknowledged, via: via);

  factory _RaceResult.failed(String reason) =>
      _RaceResult._(success: false, reason: reason);
}

/// Try sending via local WiFi.
Future<_RaceResult> _tryLocalSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
  String senderPeerId,
) async {
  final localSent = await p2pService.sendLocalMessage(
    targetPeerId, jsonString, senderPeerId);
  if (localSent) {
    return _RaceResult.succeeded(via: 'local', acknowledged: true);
  }
  return _RaceResult.failed('local_send_failed');
}

/// Try direct discover → dial → send path.
Future<_RaceResult> _tryDirectSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
) async {
  final budgetMs = interactiveDirectBudget.inMilliseconds;

  // Discover
  final peer = await p2pService.discoverPeer(
    targetPeerId,
    timeoutMs: budgetMs,
  );
  if (peer == null) {
    return _RaceResult.failed('peer_not_found');
  }

  // Dial
  final dialed = await p2pService.dialPeer(
    targetPeerId,
    addresses: peer.addresses,
    timeoutMs: budgetMs,
  );
  if (!dialed) {
    return _RaceResult.failed('dial_failed');
  }

  // Send
  final sendResult = await p2pService.sendMessageWithReply(
    targetPeerId,
    jsonString,
    timeoutMs: budgetMs,
  );
  if (!sendResult.sent) {
    return _RaceResult.failed('send_failed');
  }

  return _RaceResult.succeeded(
    via: 'direct',
    acknowledged: sendResult.acknowledged,
  );
}
