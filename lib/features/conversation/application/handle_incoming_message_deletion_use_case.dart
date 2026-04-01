import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_deletion_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

enum HandleMessageDeletionResult {
  success,
  notMessageDeletion,
  decryptionFailed,
  unknownSender,
  ignoredMissingMessage,
  unauthorized,
}

Future<(HandleMessageDeletionResult, ConversationMessage?)>
handleIncomingMessageDeletion({
  required ChatMessage message,
  required MessageRepository messageRepo,
  required ContactRepository contactRepo,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  Bridge? bridge,
  String? ownMlKemSecretKey,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_RECEIVE_START',
    details: {
      'from': message.from.length > 10
          ? message.from.substring(0, 10)
          : message.from,
    },
  );

  MessageDeletionPayload? payload;
  final v2Envelope = MessageDeletionPayload.parseEncryptedEnvelope(
    message.content,
  );
  if (v2Envelope != null) {
    if (bridge == null || ownMlKemSecretKey == null) {
      return (HandleMessageDeletionResult.decryptionFailed, null);
    }
    final encrypted = v2Envelope['encrypted'] as Map<String, dynamic>;
    try {
      final decryptResult = await callDecryptMessage(
        bridge: bridge,
        ownMlKemSecretKey: ownMlKemSecretKey,
        kem: encrypted['kem'] as String,
        ciphertext: encrypted['ciphertext'] as String,
        nonce: encrypted['nonce'] as String,
      );
      if (decryptResult['ok'] != true) {
        return (HandleMessageDeletionResult.decryptionFailed, null);
      }
      payload = MessageDeletionPayload.fromDecryptedJson(
        decryptResult['plaintext'] as String,
      );
    } catch (_) {
      return (HandleMessageDeletionResult.decryptionFailed, null);
    }
  } else {
    payload = MessageDeletionPayload.fromJson(message.content);
  }

  if (payload == null) {
    return (HandleMessageDeletionResult.notMessageDeletion, null);
  }

  final contact = await contactRepo.getContact(payload.senderPeerId);
  if (contact == null) {
    return (HandleMessageDeletionResult.unknownSender, null);
  }

  final targetMessage = await messageRepo.getMessage(payload.messageId);
  if (targetMessage == null) {
    return (HandleMessageDeletionResult.ignoredMissingMessage, null);
  }

  if (targetMessage.senderPeerId != payload.senderPeerId) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_RECEIVE_UNAUTHORIZED',
      details: {
        'messageId': payload.messageId.length > 8
            ? payload.messageId.substring(0, 8)
            : payload.messageId,
      },
    );
    return (HandleMessageDeletionResult.unauthorized, null);
  }

  if (targetMessage.isDeleted) {
    return (HandleMessageDeletionResult.success, targetMessage);
  }

  final tombstone = buildDeletedMessageTombstone(
    originalMessage: targetMessage,
    deletedAt: payload.timestamp,
    deletedByPeerId: payload.senderPeerId,
    hiddenLocally: false,
    status: targetMessage.status,
    transport: targetMessage.transport,
    wireEnvelope: null,
  );
  await messageRepo.saveMessage(tombstone);
  await _bestEffortIncomingCleanup(
    message: tombstone,
    reactionRepo: reactionRepo,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_RECEIVE_SUCCESS',
    details: {
      'messageId': payload.messageId.length > 8
          ? payload.messageId.substring(0, 8)
          : payload.messageId,
    },
  );
  return (HandleMessageDeletionResult.success, tombstone);
}

Future<void> _bestEffortIncomingCleanup({
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
      event: 'CHAT_MSG_DELETE_RECEIVE_CLEANUP_ERROR',
      details: {
        'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
        'error': e.toString(),
      },
    );
  }
}
