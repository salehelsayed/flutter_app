import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_message_deletion_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

class MessageDeletionListener {
  final Stream<ChatMessage> deletionStream;
  final MessageRepository messageRepo;
  final ContactRepository contactRepo;
  final ReactionRepository? reactionRepo;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final MediaFileManager? mediaFileManager;
  final Bridge? bridge;
  final Future<String?> Function()? getOwnMlKemSecretKey;

  StreamSubscription<ChatMessage>? _subscription;
  final _deletionController = StreamController<ConversationMessage>.broadcast();

  MessageDeletionListener({
    required this.deletionStream,
    required this.messageRepo,
    required this.contactRepo,
    this.reactionRepo,
    this.mediaAttachmentRepo,
    this.mediaFileManager,
    this.bridge,
    this.getOwnMlKemSecretKey,
  });

  Stream<ConversationMessage> get incomingDeletionStream =>
      _deletionController.stream;

  void start() {
    if (_subscription != null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_LISTENER_START',
      details: {},
    );

    _subscription = deletionStream.listen(
      _onMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_DELETE_LISTENER_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  void stop() {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_LISTENER_STOP',
      details: {},
    );
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
    _deletionController.close();
  }

  Future<void> _onMessage(ChatMessage message) async {
    try {
      final senderContact = await contactRepo.getContact(message.from);
      if (senderContact != null && senderContact.isBlocked) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_DELETE_LISTENER_BLOCKED_REJECT',
          details: {
            'from': message.from.length > 10
                ? message.from.substring(0, 10)
                : message.from,
          },
        );
        return;
      }

      final ownSecretKey = getOwnMlKemSecretKey != null
          ? await getOwnMlKemSecretKey!()
          : null;

      final (result, deletedMessage) = await handleIncomingMessageDeletion(
        message: message,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
        bridge: bridge,
        ownMlKemSecretKey: ownSecretKey,
      );

      if (result == HandleMessageDeletionResult.success &&
          deletedMessage != null) {
        _deletionController.add(deletedMessage);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
