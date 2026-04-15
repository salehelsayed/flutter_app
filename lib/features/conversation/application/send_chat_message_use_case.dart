import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/chat_console_logger.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

/// Interactive send budget for local WiFi attempts.
const Duration interactiveLocalBudget = Duration(milliseconds: 1500);

/// Interactive send budget for the overall direct send path.
const Duration interactiveDirectBudget = Duration(seconds: 2);

/// Interactive send budget for the inbox store fallback path.
const Duration interactiveInboxBudget = Duration(seconds: 3);

/// After a successful relay probe, allow one immediate retry before inbox
/// fallback. This targets stale-discoverability recovery without slowing the
/// normal foreground send race.
const int relayProbeSendAttempts = 2;
const Duration relayProbeRetryBackoff = Duration(milliseconds: 250);

/// Result of sending a chat message.
enum SendChatMessageResult {
  success,
  nodeNotRunning,
  invalidMessage,
  encryptionRequired,
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
/// 4. Serializes to JSON envelope (v2 encrypted if ML-KEM key available)
/// 5. Persists wireEnvelope to DB row (Section 4: crash-safe retryability)
/// 6. Reuses an existing connection, races local WiFi with direct relay send,
///    and probes the relay only when discoverability is stale
/// 7. Persists final status via messageRepo.saveMessage()
///
/// A live send that writes to the peer but does not receive an ACK attempts an
/// immediate durable inbox handoff. If the inbox handoff also fails, the
/// message is kept as truthful local `sent` state with the wire envelope
/// retained for later retry.
///
/// The wireEnvelope persist at step 5 ensures that if the app crashes during
/// the transport race (step 6), Section 1's PendingMessageRetrier can replay
/// the message without re-serializing or re-encrypting.
///
/// Returns (result, ConversationMessage?) — message is non-null on success or failure (persisted).
Future<(SendChatMessageResult, ConversationMessage?)> sendChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String action = MessagePayload.actionSend,
  String? editedAt,
  String? messageId,
  String? timestamp,
  String? createdAt,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
}) async {
  final sendStopwatch = Stopwatch()..start();
  final targetPrefix = targetPeerId.length > 10
      ? targetPeerId.substring(0, 10)
      : targetPeerId;
  final sanitizedText = sanitizeMessageText(text);
  final textPreview = buildTextPreview(sanitizedText);
  final hasAttachments =
      mediaAttachments != null && mediaAttachments.isNotEmpty;
  var connectionReused = false;
  var sendPath = 'unknown';
  Map<String, int> stepTimings = {};
  void emitSendTiming({
    required String outcome,
    Map<String, dynamic> details = const {},
  }) {
    if (!emitTimingEvent) return;
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_TIMING',
      details: {
        'elapsedMs': sendStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'hasAttachments': hasAttachments,
        'connectionReused': connectionReused,
        'sendPath': sendPath,
        ...stepTimings,
        ...details,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_START',
    details: {'targetPeerId': targetPrefix, 'textPreview': textPreview},
  );

  // 1. Validate
  if (sanitizedText.trim().isEmpty && !hasAttachments) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {'reason': 'empty_text'},
    );
    emitSendTiming(outcome: 'invalid_message');
    return (SendChatMessageResult.invalidMessage, null);
  }

  if (action == MessagePayload.actionEdit &&
      (messageId == null || timestamp == null || createdAt == null)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {'reason': 'edit_requires_existing_message_contract'},
    );
    emitSendTiming(outcome: 'invalid_message');
    return (SendChatMessageResult.invalidMessage, null);
  }

  // 2. Check P2P node
  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_NODE_NOT_RUNNING',
      details: {},
    );
    emitSendTiming(outcome: 'node_not_running');
    return (SendChatMessageResult.nodeNotRunning, null);
  }

  // 3. Build payload
  final resolvedMessageId = messageId ?? _uuid.v4();
  final resolvedTimestamp =
      timestamp ?? DateTime.now().toUtc().toIso8601String();
  final resolvedEditedAt = action == MessagePayload.actionEdit
      ? (editedAt ?? DateTime.now().toUtc().toIso8601String())
      : null;
  final normalizedAttachments = mediaAttachments
      ?.map(
        (attachment) => attachment.copyWith(
          messageId: resolvedMessageId,
          createdAt: attachment.createdAt.isEmpty
              ? resolvedTimestamp
              : attachment.createdAt,
        ),
      )
      .toList();

  final payload = MessagePayload(
    id: resolvedMessageId,
    text: sanitizedText,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    timestamp: resolvedTimestamp,
    action: action,
    editedAt: resolvedEditedAt,
    quotedMessageId: quotedMessageId,
    media: normalizedAttachments
        ?.map((attachment) => attachment.toJson())
        .toList(),
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'queued',
    text: sanitizedText,
  );

  // 4. Serialize (v2 encrypted envelope if ML-KEM key available, v1 plaintext otherwise)
  String jsonString;
  if (bridge != null && recipientMlKemPublicKey != null) {
    try {
      final innerJson = payload.toInnerJson();
      final encryptStopwatch = Stopwatch()..start();
      final encryptResult = await callEncryptMessage(
        bridge: bridge,
        recipientMlKemPublicKey: recipientMlKemPublicKey,
        plaintext: innerJson,
      );
      encryptStopwatch.stop();
      stepTimings['encryptMs'] = encryptStopwatch.elapsedMilliseconds;
      if (encryptResult['ok'] != true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_ENCRYPT_FAILED',
          details: {
            'errorCode': encryptResult['errorCode'],
            'errorMessage': encryptResult['errorMessage'],
          },
        );
        emitSendTiming(
          outcome: 'encrypt_failed',
          details: {'errorCode': encryptResult['errorCode']},
        );
        return (SendChatMessageResult.sendFailed, null);
      }
      jsonString = MessagePayload.buildEncryptedEnvelope(
        id: resolvedMessageId,
        senderPeerId: senderPeerId,
        senderUsername: senderUsername,
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
      emitSendTiming(outcome: 'encrypt_error');
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

  // SECTION 4 CONTRACT: wireEnvelope is persisted BEFORE the transport race.
  // If the app crashes after this point, the DB row has wireEnvelope != null
  // and Section 1's PendingMessageRetrier can replay the message without
  // re-serializing or re-encrypting.
  if (messageId != null) {
    await messageRepo.updateWireEnvelope(messageId, jsonString);
  }

  // 4.5. Check for existing connected peer first (connection reuse).
  // If the peer is already connected, try to send directly without
  // rediscovering — this is the fastest interactive path.
  final isAlreadyConnected = p2pService.currentState.connections.any(
    (c) => c.peerId == targetPeerId,
  );

  if (isAlreadyConnected) {
    connectionReused = true;
    sendPath = 'reuse';
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_REUSE_CONNECTION',
      details: {'targetPeerId': targetPrefix},
    );
    try {
      final reuseSendStopwatch = Stopwatch()..start();
      final sendResult = await p2pService.sendMessageWithReply(
        targetPeerId,
        jsonString,
        timeoutMs: interactiveDirectBudget.inMilliseconds,
      );
      reuseSendStopwatch.stop();
      stepTimings = {
        'sendMs': reuseSendStopwatch.elapsedMilliseconds,
        if (sendResult.streamOpenMs != null) 'streamOpenMs': sendResult.streamOpenMs!,
        if (sendResult.writeMs != null) 'writeMs': sendResult.writeMs!,
        if (sendResult.ackWaitMs != null) 'ackWaitMs': sendResult.ackWaitMs!,
      };
      if (sendResult.sent) {
        return _completeSuccessfulSend(
          p2pService: p2pService,
          messageRepo: messageRepo,
          payload: payload,
          targetPeerId: targetPeerId,
          jsonString: jsonString,
          acknowledged: sendResult.acknowledged,
          via: _resolveGoSendTransport(
            p2pService,
            targetPeerId,
            sendResult,
            preserveLocalPeerLabel: true,
          ),
          resolvedMessageId: resolvedMessageId,
          textPreview: textPreview,
          text: sanitizedText,
          createdAt: createdAt,
          editedAt: resolvedEditedAt,
          mediaAttachmentRepo: mediaAttachmentRepo,
          attachments: normalizedAttachments,
          sendStopwatch: sendStopwatch,
          emitTimingEvent: emitTimingEvent,
          extraTimingDetails: {
            'connectionReused': true,
            'sendPath': 'reuse',
            ...stepTimings,
          },
        );
      }
    } catch (_) {
      // Connection reuse failed — fall through to race
    }
    connectionReused = false;
    sendPath = 'unknown';
    stepTimings = {};
  }

  // 5. Race: local WiFi and direct discover/dial/send in parallel.
  // The first successful path wins and is the only one to persist.
  final isLocalPeer = p2pService.isLocalPeer(targetPeerId);

  // Build race futures
  final raceFutures = <Future<_RaceResult>>[];

  // Local WiFi path (bounded by interactiveLocalBudget)
  if (isLocalPeer) {
    raceFutures.add(
      _tryLocalSend(
        p2pService,
        targetPeerId,
        jsonString,
        senderPeerId,
        timeoutMs: interactiveLocalBudget.inMilliseconds,
      ),
    );
  }

  // Direct discover/dial/send path (bounded by interactiveDirectBudget)
  raceFutures.add(
    _tryDirectSend(p2pService, targetPeerId, jsonString).timeout(
      interactiveDirectBudget,
      onTimeout: () => _RaceResult.failed('direct_timeout'),
    ),
  );

  // Race: first successful result wins.
  // We use a completer to commit only the first success.
  final completer = Completer<_RaceResult>();
  var pendingCount = raceFutures.length;
  final failures = <_RaceResult>[];

  for (final future in raceFutures) {
    future
        .then((result) {
          if (result.success && !completer.isCompleted) {
            completer.complete(result);
          } else {
            failures.add(result);
            pendingCount--;
            if (pendingCount <= 0 && !completer.isCompleted) {
              var failureReason = failures.isNotEmpty
                  ? failures.first.reason ?? 'unknown'
                  : 'unknown';
              var relayProbeEligible = false;
              for (final failure in failures) {
                if (failure.relayProbeEligible) {
                  failureReason = failure.reason ?? failureReason;
                  relayProbeEligible = true;
                  break;
                }
              }
              completer.complete(
                _RaceResult.failed(
                  failureReason,
                  relayProbeEligible: relayProbeEligible,
                ),
              );
            }
          }
        })
        .catchError((Object e) {
          failures.add(_RaceResult.failed(e.toString()));
          pendingCount--;
          if (pendingCount <= 0 && !completer.isCompleted) {
            var failureReason = failures.isNotEmpty
                ? failures.first.reason ?? 'unknown'
                : 'unknown';
            var relayProbeEligible = false;
            for (final failure in failures) {
              if (failure.relayProbeEligible) {
                failureReason = failure.reason ?? failureReason;
                relayProbeEligible = true;
                break;
              }
            }
            completer.complete(
              _RaceResult.failed(
                failureReason,
                relayProbeEligible: relayProbeEligible,
              ),
            );
          }
        });
  }

  final raceResult = await completer.future;

  if (raceResult.success) {
    sendPath = raceResult.via == 'local' ? 'local' : 'direct';
    stepTimings = raceResult.stepTimings;
    return _completeSuccessfulSend(
      p2pService: p2pService,
      messageRepo: messageRepo,
      payload: payload,
      targetPeerId: targetPeerId,
      jsonString: jsonString,
      acknowledged: raceResult.acknowledged,
      via: raceResult.via!,
      resolvedMessageId: resolvedMessageId,
      textPreview: textPreview,
      text: sanitizedText,
      createdAt: createdAt,
      editedAt: resolvedEditedAt,
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: normalizedAttachments,
      sendStopwatch: sendStopwatch,
      emitTimingEvent: emitTimingEvent,
      extraTimingDetails: {
        'connectionReused': false,
        'sendPath': sendPath,
        ...stepTimings,
      },
    );
  }

  var failureReason = raceResult.reason ?? 'unknown';
  if (raceResult.relayProbeEligible) {
    final relayProbeResult = await _tryRelayProbeSend(
      p2pService,
      targetPeerId,
      jsonString,
      failureReason: failureReason,
    );
    if (relayProbeResult.success) {
      sendPath = 'relay';
      stepTimings = {...stepTimings, ...relayProbeResult.stepTimings};
      return _completeSuccessfulSend(
        p2pService: p2pService,
        messageRepo: messageRepo,
        payload: payload,
        targetPeerId: targetPeerId,
        jsonString: jsonString,
        acknowledged: relayProbeResult.acknowledged,
        via: relayProbeResult.via!,
        resolvedMessageId: resolvedMessageId,
        textPreview: textPreview,
        text: sanitizedText,
        createdAt: createdAt,
        editedAt: resolvedEditedAt,
        mediaAttachmentRepo: mediaAttachmentRepo,
        attachments: normalizedAttachments,
        sendStopwatch: sendStopwatch,
        emitTimingEvent: emitTimingEvent,
        extraTimingDetails: {
          'connectionReused': false,
          'sendPath': 'relay',
          ...stepTimings,
        },
      );
    }
    failureReason = relayProbeResult.reason ?? failureReason;
  }

  // All active paths failed — try offline inbox fallback once.
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_RACE_ALL_FAILED',
    details: {'reason': failureReason},
  );

  try {
    final inboxStopwatch = Stopwatch()..start();
    final storedInInbox = await p2pService.storeInInbox(
      targetPeerId,
      jsonString,
      timeoutMs: interactiveInboxBudget.inMilliseconds,
    );
    inboxStopwatch.stop();
    stepTimings['inboxMs'] = inboxStopwatch.elapsedMilliseconds;
    if (storedInInbox) {
      sendPath = 'inbox';
      final deliveredMessage = payload.toConversationMessage(
        contactPeerId: targetPeerId,
        isIncoming: false,
        status: 'delivered',
        createdAt: createdAt,
        editedAt: resolvedEditedAt,
        transport: 'inbox',
      );
      await messageRepo.saveMessage(deliveredMessage);
      await _persistOutgoingMedia(
        mediaAttachmentRepo: mediaAttachmentRepo,
        attachments: normalizedAttachments,
      );
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
      emitSendTiming(
        outcome: 'success',
        details: {'status': 'delivered', 'via': 'inbox'},
      );
      logChatOutgoing(
        messageId: resolvedMessageId,
        toPeerId: targetPeerId,
        status: 'delivered',
        text: sanitizedText,
      );
      return (
        SendChatMessageResult.success,
        deliveredMessage.copyWith(media: normalizedAttachments ?? const []),
      );
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
    createdAt: createdAt,
    editedAt: resolvedEditedAt,
    wireEnvelope: jsonString,
  );
  await messageRepo.saveMessage(failedMessage);
  await _persistOutgoingMedia(
    mediaAttachmentRepo: mediaAttachmentRepo,
    attachments: normalizedAttachments,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_FAILED',
    details: {
      'id': resolvedMessageId.substring(0, 8),
      'reason': failureReason,
      'textPreview': textPreview,
    },
  );
  emitSendTiming(
    outcome: 'failed',
    details: {
      'reason': failureReason,
      'result': _resultForFailureReason(failureReason).name,
    },
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'failed',
    text: sanitizedText,
  );
  return (
    _resultForFailureReason(failureReason),
    failedMessage.copyWith(media: normalizedAttachments ?? const []),
  );
}

Future<(SendChatMessageResult, ConversationMessage?)> editChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage originalMessage,
  required String updatedText,
  required String senderUsername,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
}) {
  if (originalMessage.isIncoming) {
    return Future.value((SendChatMessageResult.invalidMessage, null));
  }

  return sendChatMessage(
    p2pService: p2pService,
    messageRepo: messageRepo,
    targetPeerId: originalMessage.contactPeerId,
    text: updatedText,
    senderPeerId: originalMessage.senderPeerId,
    senderUsername: senderUsername,
    action: MessagePayload.actionEdit,
    messageId: originalMessage.id,
    timestamp: originalMessage.timestamp,
    createdAt: originalMessage.createdAt,
    quotedMessageId: originalMessage.quotedMessageId,
    mediaAttachments: originalMessage.media,
    mediaAttachmentRepo: mediaAttachmentRepo,
    bridge: bridge,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    emitTimingEvent: emitTimingEvent,
  );
}

/// Internal result of a single send path in the race.
class _RaceResult {
  final bool success;
  final bool acknowledged;
  final String? via;
  final String? reason;
  final bool relayProbeEligible;
  final Map<String, int> stepTimings;

  const _RaceResult._({
    required this.success,
    this.acknowledged = false,
    this.via,
    this.reason,
    this.relayProbeEligible = false,
    this.stepTimings = const {},
  });

  factory _RaceResult.succeeded({
    required String via,
    bool acknowledged = false,
    Map<String, int> stepTimings = const {},
  }) => _RaceResult._(
    success: true,
    acknowledged: acknowledged,
    via: via,
    stepTimings: stepTimings,
  );

  factory _RaceResult.failed(
    String reason, {
    bool relayProbeEligible = false,
    Map<String, int> stepTimings = const {},
  }) => _RaceResult._(
    success: false,
    reason: reason,
    relayProbeEligible: relayProbeEligible,
    stepTimings: stepTimings,
  );
}

String _inferTransportForConnectedPeer(P2PService p2pService, String peerId) {
  if (p2pService.isLocalPeer(peerId)) {
    return 'local';
  }

  return _inferDirectVsRelayForConnectedPeer(p2pService, peerId);
}

String _inferDirectVsRelayForConnectedPeer(
  P2PService p2pService,
  String peerId,
) {
  final hasRelayConnection = p2pService.currentState.connections.any(
    (connection) =>
        connection.peerId == peerId &&
        connection.multiaddrs.any(
          (multiaddr) => multiaddr.contains('/p2p-circuit'),
        ),
  );
  return hasRelayConnection ? 'relay' : 'direct';
}

String _resolveGoSendTransport(
  P2PService p2pService,
  String peerId,
  SendMessageResult sendResult, {
  bool preserveLocalPeerLabel = false,
}) {
  if (preserveLocalPeerLabel && p2pService.isLocalPeer(peerId)) {
    return 'local';
  }

  final actualTransport = sendResult.transport;
  if (actualTransport != null && actualTransport.isNotEmpty) {
    return actualTransport;
  }

  if (preserveLocalPeerLabel) {
    return _inferTransportForConnectedPeer(p2pService, peerId);
  }

  return _inferDirectVsRelayForConnectedPeer(p2pService, peerId);
}

/// Try sending via local WiFi.
Future<_RaceResult> _tryLocalSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
  String senderPeerId, {
  required int timeoutMs,
}) async {
  final localStopwatch = Stopwatch()..start();
  final localSent = await p2pService.sendLocalMessage(
    targetPeerId,
    jsonString,
    senderPeerId,
    timeoutMs: timeoutMs,
  );
  localStopwatch.stop();
  final timings = {'localSendMs': localStopwatch.elapsedMilliseconds};
  if (localSent) {
    return _RaceResult.succeeded(
      via: 'local',
      acknowledged: true,
      stepTimings: timings,
    );
  }
  return _RaceResult.failed('local_send_failed', stepTimings: timings);
}

/// Try direct discover → dial → send path.
Future<_RaceResult> _tryDirectSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
) async {
  final budgetMs = interactiveDirectBudget.inMilliseconds;
  final timings = <String, int>{};

  // Discover
  final discoverStopwatch = Stopwatch()..start();
  final peer = await p2pService.discoverPeer(targetPeerId, timeoutMs: budgetMs);
  discoverStopwatch.stop();
  timings['discoverMs'] = discoverStopwatch.elapsedMilliseconds;
  if (peer == null) {
    return _RaceResult.failed(
      'peer_not_found',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }

  // Dial
  final dialStopwatch = Stopwatch()..start();
  final dialed = await p2pService.dialPeer(
    targetPeerId,
    addresses: peer.addresses,
    timeoutMs: budgetMs,
  );
  dialStopwatch.stop();
  timings['dialMs'] = dialStopwatch.elapsedMilliseconds;
  if (!dialed) {
    return _RaceResult.failed(
      'dial_failed',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }

  // Send
  final sendStepStopwatch = Stopwatch()..start();
  final sendResult = await p2pService.sendMessageWithReply(
    targetPeerId,
    jsonString,
    timeoutMs: budgetMs,
  );
  sendStepStopwatch.stop();
  timings['sendMs'] = sendStepStopwatch.elapsedMilliseconds;
  if (sendResult.streamOpenMs != null) {
    timings['streamOpenMs'] = sendResult.streamOpenMs!;
  }
  if (sendResult.writeMs != null) {
    timings['writeMs'] = sendResult.writeMs!;
  }
  if (sendResult.ackWaitMs != null) {
    timings['ackWaitMs'] = sendResult.ackWaitMs!;
  }
  if (!sendResult.sent) {
    return _RaceResult.failed('send_failed', stepTimings: timings);
  }

  return _RaceResult.succeeded(
    via: _resolveGoSendTransport(p2pService, targetPeerId, sendResult),
    acknowledged: sendResult.acknowledged,
    stepTimings: timings,
  );
}

Future<_RaceResult> _tryRelayProbeSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required String failureReason,
}) async {
  final relayProbeStopwatch = Stopwatch()..start();
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_RELAY_PROBE_BEGIN',
    details: {'reason': failureReason},
  );

  RelayProbeResult probeResult;
  try {
    probeResult = await p2pService.probeRelay(targetPeerId);
  } catch (e) {
    relayProbeStopwatch.stop();
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_RELAY_PROBE_ERROR',
      details: {'error': e.toString()},
    );
    return _RaceResult.failed(
      failureReason,
      stepTimings: {'relayProbeMs': relayProbeStopwatch.elapsedMilliseconds},
    );
  }

  switch (probeResult) {
    case RelayProbeResult.connected:
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_RELAY_PROBE_CONNECTED',
        details: {},
      );
      try {
        final dialed = await p2pService.dialPeer(
          targetPeerId,
          timeoutMs: interactiveDirectBudget.inMilliseconds,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_RELAY_PROBE_DIAL',
          details: {'dialed': dialed},
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_RELAY_PROBE_DIAL_ERROR',
          details: {'error': e.toString()},
        );
      }
      for (var attempt = 1; attempt <= relayProbeSendAttempts; attempt++) {
        try {
          final sendResult = await p2pService.sendMessageWithReply(
            targetPeerId,
            jsonString,
            timeoutMs: interactiveDirectBudget.inMilliseconds,
          );
          if (sendResult.sent) {
            relayProbeStopwatch.stop();
            return _RaceResult.succeeded(
              via: _resolveGoSendTransport(
                p2pService,
                targetPeerId,
                sendResult,
              ),
              acknowledged: sendResult.acknowledged,
              stepTimings: {
                'relayProbeMs': relayProbeStopwatch.elapsedMilliseconds,
                if (sendResult.streamOpenMs != null) 'streamOpenMs': sendResult.streamOpenMs!,
                if (sendResult.writeMs != null) 'writeMs': sendResult.writeMs!,
                if (sendResult.ackWaitMs != null) 'ackWaitMs': sendResult.ackWaitMs!,
              },
            );
          }

          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_SEND_RELAY_PROBE_SEND_RETRY',
            details: {
              'attempt': attempt,
              'maxAttempts': relayProbeSendAttempts,
            },
          );
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_SEND_RELAY_PROBE_SEND_ERROR',
            details: {
              'attempt': attempt,
              'maxAttempts': relayProbeSendAttempts,
              'error': e.toString(),
            },
          );
        }

        if (attempt < relayProbeSendAttempts) {
          await Future<void>.delayed(relayProbeRetryBackoff);
        }
      }
      relayProbeStopwatch.stop();
      return _RaceResult.failed(
        'send_failed',
        stepTimings: {'relayProbeMs': relayProbeStopwatch.elapsedMilliseconds},
      );
    case RelayProbeResult.noReservation:
      relayProbeStopwatch.stop();
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_RELAY_PROBE_NO_RESERVATION',
        details: {},
      );
      return _RaceResult.failed(
        'peer_not_found',
        stepTimings: {'relayProbeMs': relayProbeStopwatch.elapsedMilliseconds},
      );
    case RelayProbeResult.error:
      relayProbeStopwatch.stop();
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_RELAY_PROBE_FALLBACK',
        details: {'reason': failureReason},
      );
      return _RaceResult.failed(
        failureReason,
        stepTimings: {'relayProbeMs': relayProbeStopwatch.elapsedMilliseconds},
      );
  }
}

Future<void> _persistOutgoingMedia({
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<MediaAttachment>? attachments,
}) async {
  if (mediaAttachmentRepo == null ||
      attachments == null ||
      attachments.isEmpty) {
    return;
  }

  final messageIds = attachments
      .map((attachment) => attachment.messageId)
      .where((messageId) => messageId.isNotEmpty)
      .toSet();
  if (messageIds.length == 1) {
    final messageId = messageIds.first;
    final expectedIds = attachments.map((attachment) => attachment.id).toSet();
    final existing = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
    );
    final hasStaleUploadPending = existing.any(
      (attachment) =>
          attachment.downloadStatus == 'upload_pending' &&
          !expectedIds.contains(attachment.id),
    );
    if (hasStaleUploadPending) {
      await mediaAttachmentRepo.deleteAttachmentsForMessage(messageId);
    }
  }

  for (final attachment in attachments) {
    await mediaAttachmentRepo.saveAttachment(attachment);
  }
}

Future<(SendChatMessageResult, ConversationMessage)> _completeSuccessfulSend({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required MessagePayload payload,
  required String targetPeerId,
  required String jsonString,
  required bool acknowledged,
  required String via,
  required String resolvedMessageId,
  required String textPreview,
  required String text,
  required String? createdAt,
  required String? editedAt,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<MediaAttachment>? attachments,
  required Stopwatch sendStopwatch,
  required bool emitTimingEvent,
  Map<String, dynamic> extraTimingDetails = const {},
}) async {
  final message = await _persistOutgoingSendResult(
    p2pService: p2pService,
    payload: payload,
    targetPeerId: targetPeerId,
    jsonString: jsonString,
    acknowledged: acknowledged,
    createdAt: createdAt,
    editedAt: editedAt,
    via: via,
  );
  await messageRepo.saveMessage(message);
  await _persistOutgoingMedia(
    mediaAttachmentRepo: mediaAttachmentRepo,
    attachments: attachments,
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_SUCCESS',
    details: {
      'id': resolvedMessageId.substring(0, 8),
      'status': message.status,
      'via': message.transport,
      'textPreview': textPreview,
    },
  );
  if (emitTimingEvent) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_TIMING',
      details: {
        'elapsedMs': sendStopwatch.elapsedMilliseconds,
        'outcome': 'success',
        'messageId': resolvedMessageId.substring(0, 8),
        'hasAttachments': attachments != null && attachments.isNotEmpty,
        'status': message.status,
        'via': message.transport,
        ...extraTimingDetails,
      },
    );
  }
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: message.status,
    text: text,
  );
  return (
    SendChatMessageResult.success,
    message.copyWith(media: attachments ?? const []),
  );
}

SendChatMessageResult _resultForFailureReason(String? reason) {
  return switch (reason) {
    'peer_not_found' => SendChatMessageResult.peerNotFound,
    'dial_failed' => SendChatMessageResult.dialFailed,
    _ => SendChatMessageResult.sendFailed,
  };
}

Future<ConversationMessage> _persistOutgoingSendResult({
  required P2PService p2pService,
  required MessagePayload payload,
  required String targetPeerId,
  required String jsonString,
  required bool acknowledged,
  required String? createdAt,
  required String? editedAt,
  required String via,
}) async {
  if (acknowledged) {
    return payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: 'delivered',
      createdAt: createdAt,
      editedAt: editedAt,
      transport: via,
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_BEGIN',
    details: {'via': via},
  );
  try {
    final storedInInbox = await p2pService.storeInInbox(
      targetPeerId,
      jsonString,
      timeoutMs: interactiveInboxBudget.inMilliseconds,
    );
    if (storedInInbox) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_SUCCESS',
        details: {'via': via},
      );
      return payload.toConversationMessage(
        contactPeerId: targetPeerId,
        isIncoming: false,
        status: 'delivered',
        createdAt: createdAt,
        editedAt: editedAt,
        transport: 'inbox',
      );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_FAILED',
      details: {'via': via, 'reason': 'store_returned_false'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_ERROR',
      details: {'via': via, 'error': e.toString()},
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_UNACKED_PENDING_RETRY',
    details: {'via': via},
  );
  return payload.toConversationMessage(
    contactPeerId: targetPeerId,
    isIncoming: false,
    status: 'sent',
    createdAt: createdAt,
    editedAt: editedAt,
    transport: via,
    wireEnvelope: jsonString,
  );
}
