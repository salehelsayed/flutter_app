import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import 'package:flutter_app/features/settings/application/download_profile_picture_use_case.dart';

enum ChatMessageProcessState {
  stored,
  blockedSender,
  notChatMessage,
  missingMlKemSecret,
  decryptionFailed,
  unknownSender,
  duplicate,
  editMissingOriginal,
  error,
}

class ChatMessageProcessOutcome {
  final ChatMessageProcessState state;
  final ConversationMessage? conversationMessage;
  final ContactModel? updatedContact;
  final String? reasonDetail;

  const ChatMessageProcessOutcome({
    required this.state,
    this.conversationMessage,
    this.updatedContact,
    this.reasonDetail,
  });
}

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
  final NotificationService? notificationService;
  final ActiveConversationTracker? conversationTracker;
  final AppLifecycleState Function()? getAppLifecycleState;
  final DownloadProfilePictureFn? downloadProfilePictureFn;
  final RecentRemoteNotificationGate? remoteNotificationGate;
  final Duration backgroundNotificationDuplicateGuardDelay;

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
    this.notificationService,
    this.conversationTracker,
    this.getAppLifecycleState,
    this.downloadProfilePictureFn,
    this.remoteNotificationGate,
    this.backgroundNotificationDuplicateGuardDelay = const Duration(seconds: 2),
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

    emitFlowEvent(layer: 'FL', event: 'CHAT_LISTENER_START', details: {});

    _subscription = chatMessageStream.listen(
      _onMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  /// Stops listening and cleans up resources.
  void stop() {
    emitFlowEvent(layer: 'FL', event: 'CHAT_LISTENER_STOP', details: {});

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
      final attachments = await mediaAttachmentRepo!.getAttachmentsForMessage(
        message.id,
      );
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
            result ?? attachment.copyWith(downloadStatus: 'failed'),
          );
        } catch (e) {
          downloadedMedia.add(attachment.copyWith(downloadStatus: 'failed'));
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
        details: {
          'messageId': message.id.length > 8
              ? message.id.substring(0, 8)
              : message.id,
          'error': e.toString(),
        },
      );
    }
  }

  /// Checks if a contact's avatar file exists on disk. If not, triggers
  /// a fire-and-forget download from the relay. Naturally retries on each
  /// incoming message until the avatar is successfully downloaded.
  void _ensureAvatarDownloaded(ContactModel contact) {
    if (bridge == null) return;

    final docsDir = UserAvatar.documentsDir;
    if (docsDir != null) {
      final file = File('$docsDir/media/avatars/${contact.peerId}.jpg');
      if (file.existsSync()) return;
    }

    () async {
      try {
        final dlFn = downloadProfilePictureFn ?? downloadProfilePicture;
        final updated = await dlFn(
          bridge: bridge!,
          contactRepo: contactRepo,
          ownerPeerId: contact.peerId,
          avatarVersion: 'initial',
        );
        if (updated != null) {
          emitContactUpdate(updated);
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_AVATAR_RETRY_ERROR',
          details: {'peerId': contact.peerId, 'error': e.toString()},
        );
      }
    }();
  }

  Future<void> _onMessage(ChatMessage message) async {
    await processIncomingMessage(message);
  }

  bool? _confirmationValueForState(ChatMessageProcessState state) {
    switch (state) {
      case ChatMessageProcessState.stored:
      case ChatMessageProcessState.blockedSender:
      case ChatMessageProcessState.duplicate:
        return true;
      case ChatMessageProcessState.notChatMessage:
      case ChatMessageProcessState.missingMlKemSecret:
      case ChatMessageProcessState.decryptionFailed:
      case ChatMessageProcessState.unknownSender:
      case ChatMessageProcessState.editMissingOriginal:
      case ChatMessageProcessState.error:
        return false;
    }
  }

  Future<void> _maybeConfirmDirectNonce(
    ChatMessage message,
    ChatMessageProcessState state,
  ) async {
    final nonce = message.confirmNonce;
    final value = _confirmationValueForState(state);
    if (bridge == null || nonce == null || nonce.isEmpty || value == null) {
      return;
    }

    try {
      await callP2PConfirmDirectMessage(bridge!, nonce: nonce, ok: value);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_LISTENER_CONFIRM_NONCE_ERROR',
        details: {'nonce': nonce, 'error': e.toString(), 'ok': value},
      );
    }
  }

  Future<ChatMessageProcessOutcome> processIncomingMessage(
    ChatMessage message, {
    bool suppressNotification = false,
  }) async {
    Future<ChatMessageProcessOutcome> finish(
      ChatMessageProcessOutcome outcome,
    ) async {
      await _maybeConfirmDirectNonce(message, outcome.state);
      return outcome;
    }

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
        return finish(
          const ChatMessageProcessOutcome(
            state: ChatMessageProcessState.blockedSender,
          ),
        );
      }

      // Opportunistically download avatar if missing
      if (senderContact != null) {
        _ensureAvatarDownloaded(senderContact);
      }

      final ownSecretKey = getOwnMlKemSecretKey != null
          ? await getOwnMlKemSecretKey!()
          : null;

      final (
        result,
        conversationMessage,
        updatedContact,
      ) = await handleIncomingChatMessage(
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

      if (result == HandleChatMessageResult.missingMlKemSecret) {
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.missingMlKemSecret,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.decryptionFailed) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_DECRYPT_FAILED',
          details: {
            'from': senderPeerId.length > 10
                ? senderPeerId.substring(0, 10)
                : senderPeerId,
          },
        );
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.decryptionFailed,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.unknownSender) {
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.unknownSender,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.duplicate) {
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.duplicate,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.editMissingOriginal) {
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.editMissingOriginal,
            updatedContact: updatedContact,
          ),
        );
      }

      if (result == HandleChatMessageResult.notChatMessage) {
        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.notChatMessage,
            updatedContact: updatedContact,
          ),
        );
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
          return finish(
            ChatMessageProcessOutcome(
              state: ChatMessageProcessState.stored,
              conversationMessage: conversationMessage,
              updatedContact: updatedContact,
            ),
          );
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

        // Show local notification (suppressed if viewing this conversation)
        if (notificationService != null &&
            conversationTracker != null &&
            getAppLifecycleState != null) {
          final username =
              senderContact?.username ??
              (updatedContact?.username) ??
              'Unknown';
          maybeShowNotification(
            notificationService: notificationService!,
            conversationTracker: conversationTracker!,
            getAppLifecycleState: getAppLifecycleState!,
            contactPeerId: conversationMessage.contactPeerId,
            senderUsername: username,
            messageText: notificationBodyForMessage(
              conversationMessage.text,
              conversationMessage.media,
            ),
            suppressNotification: suppressNotification,
            messageId: conversationMessage.id,
            consumeRecentRemoteNotificationAnnouncement:
                ({required payload, String? messageId}) =>
                    (remoteNotificationGate ?? recentRemoteNotificationGate)
                        .consumeIfRecentAnnouncement(
                          payload: payload,
                          messageId: messageId,
                        ),
            backgroundDuplicateGuardDelay:
                backgroundNotificationDuplicateGuardDelay,
          );
        }

        // Fire-and-forget: auto-download media attachments
        if (bridge != null &&
            mediaAttachmentRepo != null &&
            mediaFileManager != null) {
          _autoDownloadMedia(conversationMessage);
        }

        return finish(
          ChatMessageProcessOutcome(
            state: ChatMessageProcessState.stored,
            conversationMessage: conversationMessage,
            updatedContact: updatedContact,
          ),
        );
      }

      return finish(
        ChatMessageProcessOutcome(
          state: ChatMessageProcessState.error,
          updatedContact: updatedContact,
          reasonDetail: 'missing conversation message for chatMessage result',
        ),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
      return finish(
        ChatMessageProcessOutcome(
          state: ChatMessageProcessState.error,
          reasonDetail: e.toString(),
        ),
      );
    }
  }
}
