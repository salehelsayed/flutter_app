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
  encryptionRequired,
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
  final sendStart = DateTime.now();

  // 1. Validate — allow empty text if media is attached
  final hasMedia = mediaAttachments != null && mediaAttachments.isNotEmpty;
  if (text.trim().isEmpty && !hasMedia) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {
        'reason': 'empty_text',
        'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
      },
    );
    return (SendChatMessageResult.invalidMessage, null);
  }

  // 1b. Length check
  if (isMessageTooLong(text)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {
        'reason': 'message_too_long',
        'length': text.length,
        'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
      },
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
      details: {
        'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
      },
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
    media: hasMedia ? mediaAttachments.map((a) => a.toJson()).toList() : null,
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'sending',
    text: text,
  );

  // 4. Enforce V2 encryption — refuse to send unencrypted chat messages
  if (bridge == null || recipientMlKemPublicKey == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_ENCRYPTION_REQUIRED',
      details: {
        'hasBridge': bridge != null,
        'hasRecipientKey': recipientMlKemPublicKey != null,
        'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
      },
    );
    return (SendChatMessageResult.encryptionRequired, null);
  }

  String jsonString;
  final encryptStart = DateTime.now();
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
          'encryptMs': DateTime.now().difference(encryptStart).inMilliseconds,
          'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
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
      details: {
        'error': e.toString(),
        'encryptMs': DateTime.now().difference(encryptStart).inMilliseconds,
        'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
      },
    );
    return (SendChatMessageResult.sendFailed, null);
  }

  logChatWireEnvelope(
    direction: 'OUT',
    messageId: resolvedMessageId,
    wireJson: jsonString,
  );

  // 4.5. Try local WiFi delivery first (dual-path: don't return early)
  bool wifiSent = false;
  if (p2pService.isLocalPeer(targetPeerId)) {
    final localStart = DateTime.now();
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_LOCAL_ATTEMPT',
      details: {'targetPeerId': targetPrefix},
    );
    try {
      final localSent = await p2pService.sendLocalMessage(
        targetPeerId, jsonString, senderPeerId);
      if (localSent) {
        final wifiMessage = payload.toConversationMessage(
          contactPeerId: targetPeerId,
          isIncoming: false,
          status: 'sent',
          transport: 'wifi',
        );
        await messageRepo.saveMessage(wifiMessage);
        await _persistMediaAttachments(
            mediaAttachmentRepo, mediaAttachments, resolvedMessageId);
        wifiSent = true; // only true after persistence succeeds
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_LOCAL_SUCCESS',
          details: {
            'id': resolvedMessageId.substring(0, 8),
            'textPreview': textPreview,
            'durationMs': DateTime.now().difference(localStart).inMilliseconds,
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
          details: {
            'targetPeerId': targetPrefix,
            'durationMs': DateTime.now().difference(localStart).inMilliseconds,
          },
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_LOCAL_ERROR',
        details: {
          'targetPeerId': targetPrefix,
          'error': e.toString(),
          'durationMs': DateTime.now().difference(localStart).inMilliseconds,
        },
      );
    }
    // Fall through to relay path
  }

  // 4.7. Fast path: if already connected, try sending directly (skip discover/dial)
  if (p2pService.isConnectedToPeer(targetPeerId)) {
    final fastStart = DateTime.now();
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_FAST_PATH_ATTEMPT',
      details: {'targetPeerId': targetPrefix},
    );

    try {
      final fastResult = await p2pService.sendMessageWithReply(
        targetPeerId,
        jsonString,
        timeoutMs: 1000,
      );

      if (fastResult.sent) {
        if (fastResult.acknowledged) {
          // ACK'd — save as delivered
          final message = payload.toConversationMessage(
            contactPeerId: targetPeerId,
            isIncoming: false,
            status: 'delivered',
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
              'status': 'delivered',
              'textPreview': textPreview,
              'durationMs': DateTime.now().difference(fastStart).inMilliseconds,
              'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
            },
          );
          logChatOutgoing(
            messageId: resolvedMessageId,
            toPeerId: targetPeerId,
            status: 'delivered',
            text: text,
          );
          return (SendChatMessageResult.success, message);
        }

        // Sent but not ACK'd — try inbox safety net (skip for WiFi)
        if (!wifiSent) {
          final inboxResult = await _tryInboxSafetyNet(
            p2pService: p2pService,
            messageRepo: messageRepo,
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaAttachments: mediaAttachments,
            payload: payload,
            targetPeerId: targetPeerId,
            resolvedMessageId: resolvedMessageId,
            jsonString: jsonString,
            textPreview: textPreview,
            text: text,
          );
          if (inboxResult != null) return inboxResult;
        }

        // WiFi sent but no ACK, or inbox safety net failed — save as 'sent' with wire_envelope
        final status = 'sent';
        final message = payload.toConversationMessage(
          contactPeerId: targetPeerId,
          isIncoming: false,
          status: status,
          transport: wifiSent ? 'wifi' : 'relay',
          wireEnvelope: wifiSent ? null : jsonString,
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
            'durationMs': DateTime.now().difference(fastStart).inMilliseconds,
            'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
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
      details: {
        'targetPeerId': targetPrefix,
        'durationMs': DateTime.now().difference(fastStart).inMilliseconds,
      },
    );
  }

  // 4.8. Relay probe — fast offline detection
  final probeStart = DateTime.now();
  var probeResult = RelayProbeResult.error;
  try {
    probeResult = await p2pService.probeRelay(targetPeerId);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_RELAY_PROBE_ERROR',
      details: {
        'error': e.toString(),
        'durationMs': DateTime.now().difference(probeStart).inMilliseconds,
      },
    );
  }

  if (probeResult == RelayProbeResult.connected) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_RELAY_PROBE_CONNECTED',
      details: {
        'durationMs': DateTime.now().difference(probeStart).inMilliseconds,
      },
    );
    // Peer is online — send on the newly established relay connection
    try {
      final probeResult = await p2pService.sendMessageWithReply(
        targetPeerId,
        jsonString,
      );
      if (probeResult.sent) {
        if (probeResult.acknowledged) {
          final message = payload.toConversationMessage(
            contactPeerId: targetPeerId,
            isIncoming: false,
            status: 'delivered',
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
              'status': 'delivered',
              'via': 'relay_probe',
              'textPreview': textPreview,
              'durationMs': DateTime.now().difference(probeStart).inMilliseconds,
              'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
            },
          );
          logChatOutgoing(
            messageId: resolvedMessageId,
            toPeerId: targetPeerId,
            status: 'delivered',
            text: text,
          );
          return (SendChatMessageResult.success, message);
        }

        // Sent but not ACK'd — try inbox safety net (skip for WiFi)
        if (!wifiSent) {
          final inboxResult = await _tryInboxSafetyNet(
            p2pService: p2pService,
            messageRepo: messageRepo,
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaAttachments: mediaAttachments,
            payload: payload,
            targetPeerId: targetPeerId,
            resolvedMessageId: resolvedMessageId,
            jsonString: jsonString,
            textPreview: textPreview,
            text: text,
          );
          if (inboxResult != null) return inboxResult;
        }

        // Save as 'sent' with wire_envelope
        final message = payload.toConversationMessage(
          contactPeerId: targetPeerId,
          isIncoming: false,
          status: 'sent',
          transport: wifiSent ? 'wifi' : 'relay',
          wireEnvelope: wifiSent ? null : jsonString,
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
            'status': 'sent',
            'via': 'relay_probe',
            'textPreview': textPreview,
            'durationMs': DateTime.now().difference(probeStart).inMilliseconds,
            'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
          },
        );
        logChatOutgoing(
          messageId: resolvedMessageId,
          toPeerId: targetPeerId,
          status: 'sent',
          text: text,
        );
        return (SendChatMessageResult.success, message);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_RELAY_PROBE_SEND_FAILED',
        details: {
          'error': e.toString(),
          'durationMs': DateTime.now().difference(probeStart).inMilliseconds,
        },
      );
      // Send failed after relay connect — fall through to dial
    }
  } else if (probeResult == RelayProbeResult.noReservation) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_RELAY_PROBE_OFFLINE',
      details: {
        'durationMs': DateTime.now().difference(probeStart).inMilliseconds,
      },
    );
    // Peer is definitely offline — skip dial entirely, go straight to inbox
  }
  // probeResult == error → fall through to single dial attempt

  // 5. Single dial attempt (only reached on probe error or probe connected + send failed)
  SendChatMessageResult? lastFailureReason;

  if (probeResult != RelayProbeResult.noReservation) {
    const maxAttempts = 1; // Reduced from 3 — probe already checked relay
    const baseDelay = Duration(milliseconds: 500);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final attemptStart = DateTime.now();
      try {
        // 5a. Discover peer
        final peer = await p2pService.discoverPeer(targetPeerId);
        if (peer == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_SEND_PEER_NOT_FOUND',
            details: {
              'attempt': attempt,
              'targetPeerId': targetPrefix,
              'durationMs': DateTime.now().difference(attemptStart).inMilliseconds,
            },
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
            details: {
              'attempt': attempt,
              'targetPeerId': targetPrefix,
              'durationMs': DateTime.now().difference(attemptStart).inMilliseconds,
            },
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
            details: {
              'attempt': attempt,
              'targetPeerId': targetPrefix,
              'durationMs': DateTime.now().difference(attemptStart).inMilliseconds,
            },
          );
          lastFailureReason = SendChatMessageResult.sendFailed;

          if (attempt < maxAttempts) {
            await Future.delayed(baseDelay * attempt);
            continue;
          }
          break;
        }

        // Sent! Check ACK status
        if (sendResult.acknowledged) {
          // ACK'd — save as delivered
          final message = payload.toConversationMessage(
            contactPeerId: targetPeerId,
            isIncoming: false,
            status: 'delivered',
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
              'status': 'delivered',
              'attempts': attempt,
              'textPreview': textPreview,
              'durationMs': DateTime.now().difference(attemptStart).inMilliseconds,
              'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
            },
          );
          logChatOutgoing(
            messageId: resolvedMessageId,
            toPeerId: targetPeerId,
            status: 'delivered',
            text: text,
            attempt: attempt,
          );
          return (SendChatMessageResult.success, message);
        }

        // Sent but not ACK'd — try inbox safety net (skip for WiFi)
        if (!wifiSent) {
          final inboxResult = await _tryInboxSafetyNet(
            p2pService: p2pService,
            messageRepo: messageRepo,
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaAttachments: mediaAttachments,
            payload: payload,
            targetPeerId: targetPeerId,
            resolvedMessageId: resolvedMessageId,
            jsonString: jsonString,
            textPreview: textPreview,
            text: text,
          );
          if (inboxResult != null) return inboxResult;
        }

        // WiFi sent but no ACK, or inbox failed — save as 'sent' with wire_envelope
        final message = payload.toConversationMessage(
          contactPeerId: targetPeerId,
          isIncoming: false,
          status: 'sent',
          transport: wifiSent ? 'wifi' : 'relay',
          wireEnvelope: wifiSent ? null : jsonString,
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
            'status': 'sent',
            'attempts': attempt,
            'textPreview': textPreview,
            'durationMs': DateTime.now().difference(attemptStart).inMilliseconds,
            'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
          },
        );
        logChatOutgoing(
          messageId: resolvedMessageId,
          toPeerId: targetPeerId,
          status: 'sent',
          text: text,
          attempt: attempt,
        );
        return (SendChatMessageResult.success, message);
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_ERROR',
          details: {
            'attempt': attempt,
            'error': e.toString(),
            'durationMs': DateTime.now().difference(attemptStart).inMilliseconds,
          },
        );
        lastFailureReason = SendChatMessageResult.sendFailed;

        if (attempt < maxAttempts) {
          await Future.delayed(baseDelay * attempt);
          continue;
        }
      }
    }
  }

  // 6. Inbox fallback — try offline inbox.
  final inboxStart = DateTime.now();
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
        transport: 'inbox',
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
          'via': 'inbox',
          'probeResult': probeResult.name,
          'textPreview': textPreview,
          'durationMs': DateTime.now().difference(inboxStart).inMilliseconds,
          'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
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
      details: {
        'error': e.toString(),
        'durationMs': DateTime.now().difference(inboxStart).inMilliseconds,
      },
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

  // No WiFi fallback — persist with failed status + wire_envelope for retry.
  final failedMessage = payload.toConversationMessage(
    contactPeerId: targetPeerId,
    isIncoming: false,
    status: 'failed',
    wireEnvelope: jsonString,
  );
  try {
    await messageRepo.saveMessage(failedMessage);
    await _persistMediaAttachments(
        mediaAttachmentRepo, mediaAttachments, resolvedMessageId);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_PERSIST_FAILED_ERROR',
      details: {
        'error': e.toString(),
        'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
      },
    );
    return (lastFailureReason ?? SendChatMessageResult.sendFailed, null);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_FAILED',
    details: {
      'id': resolvedMessageId.substring(0, 8),
      'reason': lastFailureReason?.name ?? 'unknown',
      'textPreview': textPreview,
      'totalMs': DateTime.now().difference(sendStart).inMilliseconds,
    },
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'failed',
    text: text,
  );
  return (lastFailureReason ?? SendChatMessageResult.sendFailed, failedMessage);
}

/// Attempts to store the message in the relay inbox as a safety net
/// when the message was sent but not ACK'd.
///
/// Returns the result tuple if inbox succeeded, or null to fall through.
Future<(SendChatMessageResult, ConversationMessage?)?> _tryInboxSafetyNet({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<MediaAttachment>? mediaAttachments,
  required MessagePayload payload,
  required String targetPeerId,
  required String resolvedMessageId,
  required String jsonString,
  required String textPreview,
  required String text,
}) async {
  try {
    final stored = await p2pService.storeInInbox(targetPeerId, jsonString);
    if (stored) {
      final msg = payload.toConversationMessage(
        contactPeerId: targetPeerId,
        isIncoming: false,
        status: 'delivered',
        transport: 'inbox',
      );
      await messageRepo.saveMessage(msg);
      await _persistMediaAttachments(
          mediaAttachmentRepo, mediaAttachments, resolvedMessageId);

      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_INBOX_SAFETY_NET_SUCCESS',
        details: {
          'id': resolvedMessageId.substring(0, 8),
          'textPreview': textPreview,
        },
      );
      logChatOutgoing(
        messageId: resolvedMessageId,
        toPeerId: targetPeerId,
        status: 'delivered',
        text: text,
      );
      return (SendChatMessageResult.success, msg);
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INBOX_SAFETY_NET_ERROR',
      details: {'error': e.toString()},
    );
  }
  return null;
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
