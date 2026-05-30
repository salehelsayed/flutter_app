import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_deletion_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

Future<int> deleteMessageForMe({
  required ConversationMessage message,
  required MessageRepository messageRepo,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_FOR_ME_START',
    details: {
      'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
    },
  );

  await cleanupDeletedMessageArtifacts(
    message: message,
    reactionRepo: reactionRepo,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
  );
  final count = await messageRepo.deleteMessage(message.id);

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_FOR_ME_DONE',
    details: {'count': count},
  );

  return count;
}

Future<(SendChatMessageResult, ConversationMessage?)> deleteMessageForEveryone({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage originalMessage,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  bool emitTimingEvent = true,
}) async {
  final deleteStopwatch = Stopwatch()..start();
  final hasMedia = originalMessage.media.isNotEmpty;
  void emitDeleteTiming({
    required String outcome,
    Map<String, dynamic> details = const {},
  }) {
    if (!emitTimingEvent) return;
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_TIMING',
      details: {
        'elapsedMs': deleteStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'hadMedia': hasMedia,
        ...details,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_FOR_EVERYONE_START',
    details: {
      'id': originalMessage.id.length > 8
          ? originalMessage.id.substring(0, 8)
          : originalMessage.id,
    },
  );

  if (originalMessage.isIncoming ||
      originalMessage.isDeleted ||
      originalMessage.status != 'delivered') {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_INVALID',
      details: {
        'status': originalMessage.status,
        'isIncoming': originalMessage.isIncoming,
        'isDeleted': originalMessage.isDeleted,
      },
    );
    emitDeleteTiming(outcome: 'invalid_message');
    return (SendChatMessageResult.invalidMessage, null);
  }

  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_NODE_NOT_RUNNING',
      details: {},
    );
    emitDeleteTiming(outcome: 'node_not_running');
    return (SendChatMessageResult.nodeNotRunning, null);
  }

  final recipientKey = recipientMlKemPublicKey?.trim();
  if (bridge == null || recipientKey == null || recipientKey.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_ENCRYPTION_REQUIRED',
      details: {
        'reason': bridge == null ? 'missing_bridge' : 'missing_recipient_key',
      },
    );
    emitDeleteTiming(
      outcome: 'encryption_required',
      details: {
        'reason': bridge == null ? 'missing_bridge' : 'missing_recipient_key',
      },
    );
    return (SendChatMessageResult.encryptionRequired, null);
  }

  final deletedAt = DateTime.now().toUtc().toIso8601String();
  final payload = MessageDeletionPayload(
    messageId: originalMessage.id,
    senderPeerId: originalMessage.senderPeerId,
    timestamp: deletedAt,
  );

  String jsonString;
  try {
    final innerJson = payload.toInnerJson();
    final encryptResult = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: recipientKey,
      plaintext: innerJson,
    );
    if (encryptResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_FOR_EVERYONE_ENCRYPT_FAILED',
        details: {'errorCode': encryptResult['errorCode']},
      );
      emitDeleteTiming(
        outcome: 'encrypt_failed',
        details: {'errorCode': encryptResult['errorCode']},
      );
      return (SendChatMessageResult.sendFailed, null);
    }
    jsonString = MessageDeletionPayload.buildEncryptedEnvelope(
      senderPeerId: originalMessage.senderPeerId,
      kem: encryptResult['kem'] as String,
      ciphertext: encryptResult['ciphertext'] as String,
      nonce: encryptResult['nonce'] as String,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_ENCRYPT_ERROR',
      details: {'error': e.toString()},
    );
    emitDeleteTiming(outcome: 'encrypt_error');
    return (SendChatMessageResult.sendFailed, null);
  }

  final pendingTombstone = buildDeletedMessageTombstone(
    originalMessage: originalMessage,
    deletedAt: deletedAt,
    deletedByPeerId: originalMessage.senderPeerId,
    hiddenLocally: false,
    status: 'sending',
    transport: originalMessage.transport,
    wireEnvelope: jsonString,
  );
  await messageRepo.saveMessage(pendingTombstone);
  await _bestEffortCleanup(
    message: pendingTombstone,
    reactionRepo: reactionRepo,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
  );

  final targetPeerId = originalMessage.contactPeerId;
  final isAlreadyConnected = p2pService.currentState.connections.any(
    (connection) => connection.peerId == targetPeerId,
  );

  if (isAlreadyConnected) {
    try {
      final sendResult = await p2pService.sendMessageWithReply(
        targetPeerId,
        jsonString,
        timeoutMs: interactiveDirectBudget.inMilliseconds,
      );
      if (sendResult.sent) {
        return _completeSuccessfulDeleteSend(
          p2pService: p2pService,
          messageRepo: messageRepo,
          tombstone: pendingTombstone,
          targetPeerId: targetPeerId,
          jsonString: jsonString,
          acknowledged: sendResult.acknowledged,
          via: _resolveDeleteTransport(
            p2pService,
            targetPeerId,
            sendResult,
            preserveLocalPeerLabel: true,
          ),
          emitTimingEvent: emitTimingEvent,
          deleteStopwatch: deleteStopwatch,
        );
      }
    } catch (_) {
      // Fall through to the normal race.
    }
  }

  final isLocalPeer = p2pService.isLocalPeer(targetPeerId);
  final raceFutures = <Future<_DeleteRaceResult>>[];
  if (isLocalPeer) {
    raceFutures.add(
      _tryLocalDeleteSend(
        p2pService,
        targetPeerId,
        jsonString,
        originalMessage.senderPeerId,
        timeoutMs: interactiveLocalBudget.inMilliseconds,
      ),
    );
  }
  raceFutures.add(
    _tryDirectDeleteSend(p2pService, targetPeerId, jsonString).timeout(
      interactiveDirectBudget,
      onTimeout: () => _DeleteRaceResult.failed('direct_timeout'),
    ),
  );

  final completer = Completer<_DeleteRaceResult>();
  var pendingCount = raceFutures.length;
  final failures = <_DeleteRaceResult>[];

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
                _DeleteRaceResult.failed(
                  failureReason,
                  relayProbeEligible: relayProbeEligible,
                ),
              );
            }
          }
        })
        .catchError((Object e) {
          failures.add(_DeleteRaceResult.failed(e.toString()));
          pendingCount--;
          if (pendingCount <= 0 && !completer.isCompleted) {
            completer.complete(
              _DeleteRaceResult.failed(failures.first.reason ?? 'unknown'),
            );
          }
        });
  }

  final raceResult = await completer.future;
  if (raceResult.success) {
    return _completeSuccessfulDeleteSend(
      p2pService: p2pService,
      messageRepo: messageRepo,
      tombstone: pendingTombstone,
      targetPeerId: targetPeerId,
      jsonString: jsonString,
      acknowledged: raceResult.acknowledged,
      via: raceResult.via!,
      emitTimingEvent: emitTimingEvent,
      deleteStopwatch: deleteStopwatch,
    );
  }

  var failureReason = raceResult.reason ?? 'unknown';
  if (raceResult.relayProbeEligible) {
    final relayProbeResult = await _tryRelayProbeDeleteSend(
      p2pService,
      targetPeerId,
      jsonString,
      failureReason: failureReason,
    );
    if (relayProbeResult.success) {
      return _completeSuccessfulDeleteSend(
        p2pService: p2pService,
        messageRepo: messageRepo,
        tombstone: pendingTombstone,
        targetPeerId: targetPeerId,
        jsonString: jsonString,
        acknowledged: relayProbeResult.acknowledged,
        via: relayProbeResult.via!,
        emitTimingEvent: emitTimingEvent,
        deleteStopwatch: deleteStopwatch,
      );
    }
    failureReason = relayProbeResult.reason ?? failureReason;
  }

  try {
    final storedInInbox = await p2pService.storeInInbox(
      targetPeerId,
      jsonString,
    );
    if (storedInInbox) {
      final deliveredTombstone = normalizeOutgoingDeleteTombstoneVisibility(
        pendingTombstone.copyWith(
          status: 'delivered',
          transport: 'inbox',
          wireEnvelope: null,
        ),
      );
      await messageRepo.saveMessage(deliveredTombstone);
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_FOR_EVERYONE_SUCCESS',
        details: {'id': _messageIdPreview(originalMessage.id), 'via': 'inbox'},
      );
      emitDeleteTiming(
        outcome: 'success',
        details: {'status': 'delivered', 'via': 'inbox'},
      );
      return (SendChatMessageResult.success, deliveredTombstone);
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_INBOX_ERROR',
      details: {'error': e.toString()},
    );
  }

  final failedTombstone = normalizeOutgoingDeleteTombstoneVisibility(
    pendingTombstone.copyWith(status: 'failed', wireEnvelope: jsonString),
  );
  await messageRepo.saveMessage(failedTombstone);
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_FOR_EVERYONE_FAILED',
    details: {
      'id': _messageIdPreview(originalMessage.id),
      'reason': failureReason,
    },
  );
  emitDeleteTiming(
    outcome: 'failed',
    details: {
      'reason': failureReason,
      'result': _resultForDeleteFailureReason(failureReason).name,
    },
  );
  return (_resultForDeleteFailureReason(failureReason), failedTombstone);
}

ConversationMessage buildDeletedMessageTombstone({
  required ConversationMessage originalMessage,
  required String deletedAt,
  required String deletedByPeerId,
  required bool hiddenLocally,
  required String status,
  String? transport,
  String? wireEnvelope,
}) {
  return originalMessage.copyWith(
    text: '',
    status: status,
    deletedAt: deletedAt,
    deletedByPeerId: deletedByPeerId,
    hiddenAt: hiddenLocally ? deletedAt : null,
    transport: transport ?? originalMessage.transport,
    wireEnvelope: wireEnvelope,
    media: const <MediaAttachment>[],
  );
}

Future<void> cleanupDeletedMessageArtifacts({
  required ConversationMessage message,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  final attachments =
      await mediaAttachmentRepo?.getAttachmentsForMessage(message.id) ??
      const <MediaAttachment>[];
  final storedPaths = attachments
      .map((attachment) => attachment.localPath)
      .whereType<String>()
      .toList(growable: false);

  await mediaAttachmentRepo?.markUploadPendingAttachmentsFailedForMessage(
    message.id,
  );
  await reactionRepo?.deleteReactionsForMessage(message.id);
  await mediaAttachmentRepo?.deleteAttachmentsForMessage(message.id);

  if (mediaFileManager == null) return;
  for (final storedPath in storedPaths) {
    if (!_isOwnedMessageStoredPath(storedPath, message.id)) {
      continue;
    }
    final resolvedPath = await mediaFileManager.resolveStoredPath(storedPath);
    await mediaFileManager.deleteFile(resolvedPath);
  }
}

Future<void> _bestEffortCleanup({
  required ConversationMessage message,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  try {
    await cleanupDeletedMessageArtifacts(
      message: message,
      reactionRepo: reactionRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_ARTIFACT_CLEANUP_ERROR',
      details: {
        'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
        'error': e.toString(),
      },
    );
  }
}

class _DeleteRaceResult {
  final bool success;
  final bool acknowledged;
  final String? via;
  final String? reason;
  final bool relayProbeEligible;

  const _DeleteRaceResult._({
    required this.success,
    this.acknowledged = false,
    this.via,
    this.reason,
    this.relayProbeEligible = false,
  });

  factory _DeleteRaceResult.succeeded({
    required String via,
    bool acknowledged = false,
  }) =>
      _DeleteRaceResult._(success: true, acknowledged: acknowledged, via: via);

  factory _DeleteRaceResult.failed(
    String reason, {
    bool relayProbeEligible = false,
  }) => _DeleteRaceResult._(
    success: false,
    reason: reason,
    relayProbeEligible: relayProbeEligible,
  );
}

Future<(SendChatMessageResult, ConversationMessage)>
_completeSuccessfulDeleteSend({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage tombstone,
  required String targetPeerId,
  required String jsonString,
  required bool acknowledged,
  required String via,
  required bool emitTimingEvent,
  required Stopwatch deleteStopwatch,
}) async {
  final message = await _persistOutgoingDeleteResult(
    p2pService: p2pService,
    targetPeerId: targetPeerId,
    jsonString: jsonString,
    acknowledged: acknowledged,
    tombstone: tombstone,
    via: via,
  );
  await messageRepo.saveMessage(message);

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_FOR_EVERYONE_SUCCESS',
    details: {
      'id': _messageIdPreview(tombstone.id),
      'status': message.status,
      'via': message.transport,
    },
  );
  if (emitTimingEvent) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_TIMING',
      details: {
        'elapsedMs': deleteStopwatch.elapsedMilliseconds,
        'outcome': 'success',
        'hadMedia': false,
        'status': message.status,
        'via': message.transport,
      },
    );
  }
  return (SendChatMessageResult.success, message);
}

Future<ConversationMessage> _persistOutgoingDeleteResult({
  required P2PService p2pService,
  required String targetPeerId,
  required String jsonString,
  required bool acknowledged,
  required ConversationMessage tombstone,
  required String via,
}) async {
  if (acknowledged) {
    return normalizeOutgoingDeleteTombstoneVisibility(
      tombstone.copyWith(
        status: 'delivered',
        transport: via,
        wireEnvelope: null,
      ),
    );
  }

  try {
    final storedInInbox = await p2pService.storeInInbox(
      targetPeerId,
      jsonString,
    );
    if (storedInInbox) {
      return normalizeOutgoingDeleteTombstoneVisibility(
        tombstone.copyWith(
          status: 'delivered',
          transport: 'inbox',
          wireEnvelope: null,
        ),
      );
    }
  } catch (_) {
    // Fall through to the durable sent state.
  }

  return normalizeOutgoingDeleteTombstoneVisibility(
    tombstone.copyWith(
      status: 'sent',
      transport: via,
      wireEnvelope: jsonString,
    ),
  );
}

SendChatMessageResult _resultForDeleteFailureReason(String? reason) {
  return switch (reason) {
    'peer_not_found' => SendChatMessageResult.peerNotFound,
    'dial_failed' => SendChatMessageResult.dialFailed,
    _ => SendChatMessageResult.sendFailed,
  };
}

String _resolveDeleteTransport(
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

  final hasRelayConnection = p2pService.currentState.connections.any(
    (connection) =>
        connection.peerId == peerId &&
        connection.multiaddrs.any(
          (multiaddr) => multiaddr.contains('/p2p-circuit'),
        ),
  );
  return hasRelayConnection ? 'relay' : 'direct';
}

Future<_DeleteRaceResult> _tryLocalDeleteSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
  String senderPeerId, {
  required int timeoutMs,
}) async {
  final sent = await p2pService.sendLocalMessage(
    targetPeerId,
    jsonString,
    senderPeerId,
    timeoutMs: timeoutMs,
  );
  if (sent) {
    return _DeleteRaceResult.succeeded(via: 'local', acknowledged: true);
  }
  return _DeleteRaceResult.failed('local_send_failed');
}

Future<_DeleteRaceResult> _tryDirectDeleteSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
) async {
  final budgetMs = interactiveDirectBudget.inMilliseconds;
  final peer = await p2pService.discoverPeer(targetPeerId, timeoutMs: budgetMs);
  if (peer == null) {
    return _DeleteRaceResult.failed('peer_not_found', relayProbeEligible: true);
  }

  final dialed = await p2pService.dialPeer(
    targetPeerId,
    addresses: peer.addresses,
    timeoutMs: budgetMs,
  );
  if (!dialed) {
    return _DeleteRaceResult.failed('dial_failed', relayProbeEligible: true);
  }

  final sendResult = await p2pService.sendMessageWithReply(
    targetPeerId,
    jsonString,
    timeoutMs: budgetMs,
  );
  if (!sendResult.sent) {
    return _DeleteRaceResult.failed('send_failed');
  }

  return _DeleteRaceResult.succeeded(
    via: _resolveDeleteTransport(p2pService, targetPeerId, sendResult),
    acknowledged: sendResult.acknowledged,
  );
}

Future<_DeleteRaceResult> _tryRelayProbeDeleteSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required String failureReason,
}) async {
  RelayProbeResult probeResult;
  try {
    probeResult = await p2pService.probeRelay(targetPeerId);
  } catch (_) {
    return _DeleteRaceResult.failed(failureReason);
  }

  switch (probeResult) {
    case RelayProbeResult.connected:
      try {
        await p2pService.dialPeer(
          targetPeerId,
          timeoutMs: interactiveDirectBudget.inMilliseconds,
        );
      } catch (_) {}
      for (var attempt = 1; attempt <= relayProbeSendAttempts; attempt++) {
        try {
          final sendResult = await p2pService.sendMessageWithReply(
            targetPeerId,
            jsonString,
            timeoutMs: interactiveDirectBudget.inMilliseconds,
          );
          if (sendResult.sent) {
            return _DeleteRaceResult.succeeded(
              via: _resolveDeleteTransport(
                p2pService,
                targetPeerId,
                sendResult,
              ),
              acknowledged: sendResult.acknowledged,
            );
          }
        } catch (_) {}
        // NET-REL-05 P5: single post-probe send attempt
        // ([relayProbeSendAttempts] == 1); no inter-attempt backoff.
      }
      return _DeleteRaceResult.failed('send_failed');
    case RelayProbeResult.noReservation:
      return _DeleteRaceResult.failed('peer_not_found');
    case RelayProbeResult.error:
      return _DeleteRaceResult.failed(failureReason);
  }
}

bool _isOwnedMessageStoredPath(String storedPath, String messageId) {
  final normalized = storedPath.replaceAll('\\', '/');
  return normalized.startsWith('media/') ||
      normalized.startsWith('pending_uploads/$messageId/') ||
      normalized.contains('/media/') ||
      normalized.contains('/pending_uploads/$messageId/');
}

String _messageIdPreview(String id) => id.length > 8 ? id.substring(0, 8) : id;
