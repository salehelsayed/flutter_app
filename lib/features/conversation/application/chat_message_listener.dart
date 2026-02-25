import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Listener service that monitors P2P messages for chat messages.
///
/// Subscribes to a typed chat message stream (from IncomingMessageRouter),
/// calls handleIncomingChatMessage, and broadcasts persisted
/// ConversationMessages to the UI layer.
class ChatMessageListener {
  final Stream<ChatMessage> chatMessageStream;
  final MessageRepository messageRepo;
  final ContactRepository contactRepo;
  final Bridge? bridge;
  final Future<String?> Function()? getOwnMlKemSecretKey;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final MediaFileManager? mediaFileManager;

  StreamSubscription<ChatMessage>? _subscription;
  final _messageController = StreamController<ConversationMessage>.broadcast();
  final _contactUpdatedController = StreamController<ContactModel>.broadcast();

  ChatMessageListener({
    required this.chatMessageStream,
    required this.messageRepo,
    required this.contactRepo,
    this.bridge,
    this.getOwnMlKemSecretKey,
    this.mediaAttachmentRepo,
    this.mediaFileManager,
  });

  /// Stream of new incoming chat messages for the UI to listen to.
  Stream<ConversationMessage> get incomingMessageStream =>
      _messageController.stream;

  /// Stream of contacts updated from an incoming message (username or avatar).
  Stream<ContactModel> get contactUpdatedStream =>
      _contactUpdatedController.stream;

  /// Emits a contact update from an external source (e.g. ProfileUpdateListener).
  void emitContactUpdate(ContactModel contact) {
    _contactUpdatedController.add(contact);
  }

  /// Starts listening for incoming P2P messages.
  void start() {
    if (_subscription != null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_LISTENER_START',
      details: {},
    );

    _subscription = chatMessageStream.listen(
      _onMessage,
      onError: (error) {
        emitFlowEvent(layer: 'FL', event: 'CHAT_LISTENER_STREAM_ERROR', details: {'error': error.toString()});
      },
      onDone: () {
        emitFlowEvent(layer: 'FL', event: 'CHAT_LISTENER_STREAM_DONE', details: {});
      },
    );
  }

  /// Stops listening and cleans up resources.
  void stop() {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_LISTENER_STOP',
      details: {},
    );

    _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    stop();
    _messageController.close();
    _contactUpdatedController.close();
  }

  Future<void> _autoDownloadMedia(ConversationMessage message) async {
    try {
      final attachments =
          await mediaAttachmentRepo!.getAttachmentsForMessage(message.id);
      if (attachments.isEmpty) return;

      final downloadedMedia = <MediaAttachment>[];
      for (final attachment in attachments) {
        if (attachment.downloadStatus != 'pending') {
          downloadedMedia.add(attachment);
          continue;
        }
        try {
          final result = await downloadMedia(
            bridge: bridge!,
            mediaAttachmentRepo: mediaAttachmentRepo!,
            mediaFileManager: mediaFileManager!,
            attachment: attachment,
            contactPeerId: message.contactPeerId,
          );
          downloadedMedia.add(
            result ??
                attachment.copyWith(downloadStatus: 'failed'),
          );
        } catch (e) {
          downloadedMedia
              .add(attachment.copyWith(downloadStatus: 'failed'));
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_LISTENER_DOWNLOAD_ERROR',
            details: {
              'blobId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
              'error': e.toString(),
            },
          );
        }
      }

      // Re-emit with media hydrated — ConversationWired._upsertMessageById
      // replaces by ID so the UI updates seamlessly.
      _messageController.add(message.copyWith(media: downloadedMedia));
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_LISTENER_AUTO_DOWNLOAD_ERROR',
        details: {'messageId': message.id.length > 8 ? message.id.substring(0, 8) : message.id, 'error': e.toString()},
      );
    }
  }

  Future<void> _onMessage(ChatMessage message) async {
    try {
      // Check if sender is blocked — reject message entirely (don't persist)
      final senderPeerId = message.from;
      final senderContact = await contactRepo.getContact(senderPeerId);
      if (senderContact != null && senderContact.isBlocked) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_BLOCKED_REJECT',
          details: {
            'from': senderPeerId.length > 10
                ? senderPeerId.substring(0, 10)
                : senderPeerId,
          },
        );
        return; // Message never persisted, never broadcast
      }

      final ownSecretKey = getOwnMlKemSecretKey != null
          ? await getOwnMlKemSecretKey!()
          : null;

      final (result, conversationMessage, updatedContact) =
          await handleIncomingChatMessage(
        message: message,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: ownSecretKey,
        mediaAttachmentRepo: mediaAttachmentRepo,
        transport: message.transport,
      );

      if (updatedContact != null) {
        _contactUpdatedController.add(updatedContact);
      }

      if (result == HandleChatMessageResult.chatMessage &&
          conversationMessage != null) {
        // Check if sender is archived — suppress UI notification but message is already persisted
        final contact = await contactRepo.getContact(
          conversationMessage.contactPeerId,
        );
        if (contact != null && contact.isArchived) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_LISTENER_ARCHIVED_SUPPRESS',
            details: {
              'id': conversationMessage.id.length > 8
                  ? conversationMessage.id.substring(0, 8)
                  : conversationMessage.id,
              'from': conversationMessage.senderPeerId.length > 10
                  ? conversationMessage.senderPeerId.substring(0, 10)
                  : conversationMessage.senderPeerId,
            },
          );
          return;
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_NEW_MESSAGE',
          details: {
            'id': conversationMessage.id.length > 8
                ? conversationMessage.id.substring(0, 8)
                : conversationMessage.id,
            'from': conversationMessage.senderPeerId.length > 10
                ? conversationMessage.senderPeerId.substring(0, 10)
                : conversationMessage.senderPeerId,
          },
        );

        _messageController.add(conversationMessage);

        // Fire-and-forget: auto-download media attachments
        if (bridge != null &&
            mediaAttachmentRepo != null &&
            mediaFileManager != null) {
          _autoDownloadMedia(conversationMessage);
        }
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
