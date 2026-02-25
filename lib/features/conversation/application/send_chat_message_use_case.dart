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

/// Result of sending a chat message.
enum SendChatMessageResult {
  success,
  nodeNotRunning,
  invalidMessage,
  messageTooLong,
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
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
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

  // 1. Validate — allow empty text if media is attached
  final hasMedia = mediaAttachments != null && mediaAttachments.isNotEmpty;
  if (text.trim().isEmpty && !hasMedia) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {'reason': 'empty_text'},
    );
    return (SendChatMessageResult.invalidMessage, null);
  }

  // 1b. Length check
  if (isMessageTooLong(text)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {'reason': 'message_too_long', 'length': text.length},
    );
    return (SendChatMessageResult.messageTooLong, null);
  }

  // 1c. Sanitize text and username
  text = sanitizeMessageText(text);
  senderUsername = sanitizeUsername(senderUsername);

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
    quotedMessageId: quotedMessageId,
    media: hasMedia
        ? mediaAttachments!.map((a) => a.toJson()).toList()
        : null,
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

  // 4.5. Try local WiFi delivery first (dual-path: don't return early)
  bool wifiSent = false;
  if (p2pService.isLocalPeer(targetPeerId)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_LOCAL_ATTEMPT',
      details: {'targetPeerId': targetPrefix},
    );
    try {
      final localSent = await p2pService.sendLocalMessage(
        targetPeerId, jsonString, senderPeerId);
      if (localSent) {
        wifiSent = true;
        final wifiMessage = payload.toConversationMessage(
          contactPeerId: targetPeerId,
          isIncoming: false,
          status: 'sent',
          transport: 'wifi',
        );
        await messageRepo.saveMessage(wifiMessage);
        await _persistMediaAttachments(
            mediaAttachmentRepo, mediaAttachments, resolvedMessageId);
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_LOCAL_SUCCESS',
          details: {
            'id': resolvedMessageId.substring(0, 8),
            'textPreview': textPreview,
          },
        );
        logChatOutgoing(
          messageId: resolvedMessageId,
          toPeerId: targetPeerId,
          status: 'sent',
          text: text,
        );
        // DO NOT RETURN — fall through to relay/inbox for confirmation
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_LOCAL_FAILED',
          details: {'targetPeerId': targetPrefix},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_LOCAL_ERROR',
        details: {'targetPeerId': targetPrefix, 'error': e.toString()},
      );
    }
    // Fall through to relay path
  }

  // 4.7. Fast path: if already connected, try sending directly (skip discover/dial)
  if (p2pService.isConnectedToPeer(targetPeerId)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_FAST_PATH_ATTEMPT',
      details: {'targetPeerId': targetPrefix},
    );

    try {
      final fastResult = await p2pService.sendMessageWithReply(
        targetPeerId,
        jsonString,
      );

      if (fastResult.sent) {
        final status = fastResult.acknowledged ? 'delivered' : 'sent';
        final message = payload.toConversationMessage(
          contactPeerId: targetPeerId,
          isIncoming: false,
          status: status,
          transport: wifiSent ? 'wifi' : 'relay',
        );
        await messageRepo.saveMessage(message);
        if (!wifiSent) {
          await _persistMediaAttachments(
              mediaAttachmentRepo, mediaAttachments, resolvedMessageId);
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_FAST_PATH_SUCCESS',
          details: {
            'id': resolvedMessageId.substring(0, 8),
            'status': status,
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
    } catch (e) {
      // Fast path failed — fall through to discover-dial-send
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_FAST_PATH_FAILED',
      details: {'targetPeerId': targetPrefix},
    );
  }

  // 5. Discover → Dial → Send (with 3x retries and exponential backoff)
  const maxAttempts = 3;
  const baseDelay = Duration(milliseconds: 500);

  SendChatMessageResult? lastFailureReason;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      // 5a. Discover peer
      final peer = await p2pService.discoverPeer(targetPeerId);
      if (peer == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_PEER_NOT_FOUND',
          details: {'attempt': attempt, 'targetPeerId': targetPrefix},
        );
        lastFailureReason = SendChatMessageResult.peerNotFound;

        if (attempt < maxAttempts) {
          await Future.delayed(baseDelay * attempt);
          continue;
        }
        break;
      }

      // 5b. Dial peer with discovered addresses
      final dialed = await p2pService.dialPeer(
        targetPeerId,
        addresses: peer.addresses,
      );

      if (!dialed) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_DIAL_FAILED',
          details: {'attempt': attempt, 'targetPeerId': targetPrefix},
        );
        lastFailureReason = SendChatMessageResult.dialFailed;

        if (attempt < maxAttempts) {
          await Future.delayed(baseDelay * attempt);
          continue;
        }
        break;
      }

      // 5c. Send message
      final sendResult = await p2pService.sendMessageWithReply(
        targetPeerId,
        jsonString,
      );

      if (!sendResult.sent) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_MESSAGE_FAILED',
          details: {'attempt': attempt, 'targetPeerId': targetPrefix},
        );
        lastFailureReason = SendChatMessageResult.sendFailed;

        if (attempt < maxAttempts) {
          await Future.delayed(baseDelay * attempt);
          continue;
        }
        break;
      }

      // Success! Persist with appropriate status based on ack
      final status = sendResult.acknowledged ? 'delivered' : 'sent';
      final message = payload.toConversationMessage(
        contactPeerId: targetPeerId,
        isIncoming: false,
        status: status,
        transport: wifiSent ? 'wifi' : 'relay',
      );
      await messageRepo.saveMessage(message);
      if (!wifiSent) {
        await _persistMediaAttachments(
            mediaAttachmentRepo, mediaAttachments, resolvedMessageId);
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_SUCCESS',
        details: {
          'id': resolvedMessageId.substring(0, 8),
          'status': status,
          'attempts': attempt,
          'textPreview': textPreview,
        },
      );
      logChatOutgoing(
        messageId: resolvedMessageId,
        toPeerId: targetPeerId,
        status: status,
        text: text,
        attempt: attempt,
      );
      return (SendChatMessageResult.success, message);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_ERROR',
        details: {'attempt': attempt, 'error': e.toString()},
      );
      lastFailureReason = SendChatMessageResult.sendFailed;

      if (attempt < maxAttempts) {
        await Future.delayed(baseDelay * attempt);
        continue;
      }
    }
  }

  // All retries exhausted — try offline inbox fallback first.
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
        transport: wifiSent ? 'wifi' : 'inbox',
      );
      await messageRepo.saveMessage(deliveredMessage);
      if (!wifiSent) {
        await _persistMediaAttachments(
            mediaAttachmentRepo, mediaAttachments, resolvedMessageId);
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_SUCCESS',
        details: {
          'id': resolvedMessageId.substring(0, 8),
          'status': 'delivered',
          'attempts': maxAttempts,
          'via': 'inbox',
          'textPreview': textPreview,
        },
      );
      logChatOutgoing(
        messageId: resolvedMessageId,
        toPeerId: targetPeerId,
        status: 'delivered',
        text: text,
        attempt: maxAttempts,
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

  // Inbox fallback failed — if WiFi sent, that's our best effort.
  if (wifiSent) {
    return (SendChatMessageResult.success, payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: 'sent',
      transport: 'wifi',
    ));
  }

  // No WiFi fallback — persist with failed status.
  final failedMessage = payload.toConversationMessage(
    contactPeerId: targetPeerId,
    isIncoming: false,
    status: 'failed',
  );
  await messageRepo.saveMessage(failedMessage);
  await _persistMediaAttachments(
      mediaAttachmentRepo, mediaAttachments, resolvedMessageId);

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_FAILED',
    details: {
      'id': resolvedMessageId.substring(0, 8),
      'reason': lastFailureReason?.name ?? 'unknown',
      'textPreview': textPreview,
    },
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'failed',
    text: text,
    attempt: maxAttempts,
  );
  return (lastFailureReason ?? SendChatMessageResult.sendFailed, failedMessage);
}

/// Persists media attachments after a message is saved.
Future<void> _persistMediaAttachments(
  MediaAttachmentRepository? repo,
  List<MediaAttachment>? attachments,
  String messageId,
) async {
  if (repo == null || attachments == null || attachments.isEmpty) return;
  for (final a in attachments) {
    await repo.saveAttachment(a.copyWith(messageId: messageId));
  }
}
