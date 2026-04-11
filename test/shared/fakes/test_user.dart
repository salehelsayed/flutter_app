import 'dart:ui' show AppLifecycleState;

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart'
    as delete_message_uc;
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/application/message_deletion_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/remove_reaction_use_case.dart'
    as remove_reaction_uc;
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart'
    as send_reaction_uc;
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../core/bridge/fake_bridge.dart';
import '../../features/conversation/domain/repositories/fake_reaction_repository.dart';
import '../helpers/lifecycle_helpers.dart' as lifecycle_helpers;
import 'fake_p2p_network.dart';
import 'fake_p2p_service_integration.dart';
import 'in_memory_contact_repository.dart';
import 'in_memory_message_repository.dart';

/// Encapsulates the full per-user stack for integration tests.
class TestUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final InMemoryMessageRepository messageRepo;
  final InMemoryContactRepository contactRepo;
  final ChatMessageListener chatListener;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final Bridge bridge;
  final IncomingMessageRouter? router;
  final ReactionListener? reactionListener;
  final FakeReactionRepository? reactionRepo;
  final MessageDeletionListener? messageDeletionListener;
  AppLifecycleState lifecycleState = AppLifecycleState.resumed;

  TestUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.messageRepo,
    required this.contactRepo,
    required this.chatListener,
    required this.bridge,
    this.mediaAttachmentRepo,
    this.router,
    this.reactionListener,
    this.reactionRepo,
    this.messageDeletionListener,
  });

  factory TestUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
    MediaAttachmentRepository? mediaAttachmentRepo,
    InMemoryMessageRepository? messageRepo,
    InMemoryContactRepository? contactRepo,
    Bridge? bridge,
    Future<String?> Function()? getOwnMlKemSecretKey,
    bool withReactions = false,
    bool withMessageDeletion = false,
    bool autoStartListener = false,
  }) {
    final effectiveBridge = bridge ?? PassthroughCryptoBridge();
    final p2p = FakeP2PService(peerId: peerId, network: network);
    final msgRepo = messageRepo ?? InMemoryMessageRepository();
    final contactsRepo = contactRepo ?? InMemoryContactRepository();

    // When withReactions, use IncomingMessageRouter to split streams
    IncomingMessageRouter? router;
    ReactionListener? reactionListener;
    FakeReactionRepository? reactionRepo;
    MessageDeletionListener? messageDeletionListener;
    final Stream<ChatMessage> chatStream;

    if (withReactions || withMessageDeletion) {
      router = IncomingMessageRouter(p2pService: p2p);
      chatStream = router.chatMessageStream;
      if (withReactions) {
        reactionRepo = FakeReactionRepository();
        reactionListener = ReactionListener(
          reactionStream: router.reactionStream,
          messageRepo: msgRepo,
          reactionRepo: reactionRepo,
          contactRepo: contactsRepo,
          bridge: effectiveBridge,
          getOwnMlKemSecretKey:
              getOwnMlKemSecretKey ?? () async => 'test-own-mlkem-sk',
        );
      }
      if (withMessageDeletion) {
        messageDeletionListener = MessageDeletionListener(
          deletionStream: router.messageDeletionStream,
          messageRepo: msgRepo,
          contactRepo: contactsRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          bridge: effectiveBridge,
          getOwnMlKemSecretKey:
              getOwnMlKemSecretKey ?? () async => 'test-own-mlkem-sk',
        );
      }
    } else {
      chatStream = p2p.messageStream;
    }

    final listener = ChatMessageListener(
      chatMessageStream: chatStream,
      messageRepo: msgRepo,
      contactRepo: contactsRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      bridge: effectiveBridge,
      getOwnMlKemSecretKey:
          getOwnMlKemSecretKey ?? () async => 'test-own-mlkem-sk',
    );

    final user = TestUser._(
      peerId: peerId,
      username: username,
      p2pService: p2p,
      messageRepo: msgRepo,
      contactRepo: contactsRepo,
      chatListener: listener,
      bridge: effectiveBridge,
      mediaAttachmentRepo: mediaAttachmentRepo,
      router: router,
      reactionListener: reactionListener,
      reactionRepo: reactionRepo,
      messageDeletionListener: messageDeletionListener,
    );
    if (autoStartListener) {
      user.start();
    }
    return user;
  }

  /// Adds another user as a contact (simulating QR scan exchange).
  void addContact(TestUser other) {
    contactRepo.addTestContact(
      ContactModel(
        peerId: other.peerId,
        publicKey: 'pk-${other.peerId}',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: other.username,
        signature: 'sig-${other.peerId}',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: 'test-mlkem-pk-${other.peerId}',
      ),
    );
  }

  /// Looks up the ML-KEM public key for a contact.
  Future<String?> _mlKemKeyFor(String targetPeerId) async {
    final contact = await contactRepo.getContact(targetPeerId);
    return contact?.mlKemPublicKey;
  }

  /// Sends a message to the target peer.
  Future<(SendChatMessageResult, ConversationMessage?)> sendMessage(
    String targetPeerId,
    String text,
  ) async {
    return sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: targetPeerId,
      text: text,
      senderPeerId: peerId,
      senderUsername: username,
      bridge: bridge,
      recipientMlKemPublicKey: await _mlKemKeyFor(targetPeerId),
    );
  }

  /// Sends a message with a quote-reply.
  Future<(SendChatMessageResult, ConversationMessage?)> sendQuoteReply(
    String targetPeerId,
    String text,
    String quotedMessageId,
  ) async {
    return sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: targetPeerId,
      text: text,
      senderPeerId: peerId,
      senderUsername: username,
      bridge: bridge,
      recipientMlKemPublicKey: await _mlKemKeyFor(targetPeerId),
      quotedMessageId: quotedMessageId,
    );
  }

  /// Sends a message with media attachments.
  Future<(SendChatMessageResult, ConversationMessage?)> sendMessageWithMedia(
    String targetPeerId,
    String text,
    List<MediaAttachment> attachments,
  ) async {
    return sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: targetPeerId,
      text: text,
      senderPeerId: peerId,
      senderUsername: username,
      bridge: bridge,
      recipientMlKemPublicKey: await _mlKemKeyFor(targetPeerId),
      mediaAttachments: attachments,
      mediaAttachmentRepo: mediaAttachmentRepo,
    );
  }

  /// Deletes a sent message for everyone.
  Future<(SendChatMessageResult, ConversationMessage?)>
  deleteMessageForEveryone(ConversationMessage message) async {
    return delete_message_uc.deleteMessageForEveryone(
      p2pService: p2pService,
      messageRepo: messageRepo,
      originalMessage: message,
      reactionRepo: reactionRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      bridge: bridge,
      recipientMlKemPublicKey: await _mlKemKeyFor(message.contactPeerId),
    );
  }

  /// Sends a reaction to a message.
  Future<(send_reaction_uc.SendReactionResult, MessageReaction?)> sendReaction(
    String targetPeerId,
    String messageId,
    String emoji,
  ) async {
    assert(
      reactionRepo != null,
      'TestUser must be created with withReactions: true',
    );
    return send_reaction_uc.sendReaction(
      p2pService: p2pService,
      bridge: bridge,
      reactionRepo: reactionRepo!,
      targetPeerId: targetPeerId,
      messageId: messageId,
      emoji: emoji,
      senderPeerId: peerId,
      recipientMlKemPublicKey: await _mlKemKeyFor(targetPeerId) ?? '',
    );
  }

  /// Removes a reaction from a message.
  Future<remove_reaction_uc.RemoveReactionResult> removeReaction(
    String targetPeerId,
    String messageId,
    String emoji,
  ) async {
    assert(
      reactionRepo != null,
      'TestUser must be created with withReactions: true',
    );
    return remove_reaction_uc.removeReaction(
      p2pService: p2pService,
      bridge: bridge,
      reactionRepo: reactionRepo!,
      targetPeerId: targetPeerId,
      messageId: messageId,
      emoji: emoji,
      senderPeerId: peerId,
      recipientMlKemPublicKey: await _mlKemKeyFor(targetPeerId) ?? '',
    );
  }

  /// Loads the conversation with a contact.
  Future<List<ConversationMessage>> loadConversationWith(String contactPeerId) {
    return loadConversation(
      messageRepo: messageRepo,
      contactPeerId: contactPeerId,
    );
  }

  void start() {
    router?.start();
    chatListener.start();
    reactionListener?.start();
    messageDeletionListener?.start();
  }

  void startListener() => chatListener.start();

  void stopListener() => chatListener.stop();

  Future<void> simulatePause() async {
    lifecycleState = AppLifecycleState.paused;
    await handleAppPaused(messageRepo: messageRepo);
  }

  Future<bool?> simulateResume({
    Future<int> Function()? recoverStuckSendingMessagesFn,
    Future<int> Function()? retryIncompleteUploadsFn,
    Future<int> Function()? retryIncompleteGroupUploadsFn,
    Future<int> Function()? retryFailedMessagesFn,
    Future<int> Function()? retryUnackedMessagesFn,
  }) async {
    lifecycleState = AppLifecycleState.resumed;
    return handleAppResumed(
      bridge: bridge,
      p2pService: p2pService,
      recoverStuckSendingMessagesFn: recoverStuckSendingMessagesFn,
      retryIncompleteGroupUploadsFn: retryIncompleteGroupUploadsFn,
      retryIncompleteUploadsFn: retryIncompleteUploadsFn,
      retryFailedMessagesFn: retryFailedMessagesFn,
      retryUnackedMessagesFn: retryUnackedMessagesFn,
    );
  }

  Future<bool?> simulateBackgroundForegroundCycle({
    Future<int> Function()? recoverStuckSendingMessagesFn,
    Future<int> Function()? retryIncompleteUploadsFn,
    Future<int> Function()? retryIncompleteGroupUploadsFn,
    Future<int> Function()? retryFailedMessagesFn,
    Future<int> Function()? retryUnackedMessagesFn,
  }) async {
    lifecycleState = AppLifecycleState.paused;
    final result = await lifecycle_helpers.simulateBackgroundForegroundCycle(
      bridge: bridge,
      p2pService: p2pService,
      messageRepo: messageRepo,
      recoverStuckSendingMessagesFn: recoverStuckSendingMessagesFn,
      retryIncompleteGroupUploadsFn: retryIncompleteGroupUploadsFn,
      retryIncompleteUploadsFn: retryIncompleteUploadsFn,
      retryFailedMessagesFn: retryFailedMessagesFn,
      retryUnackedMessagesFn: retryUnackedMessagesFn,
    );
    lifecycleState = AppLifecycleState.resumed;
    return result;
  }

  void setOnline(bool online) => p2pService.setOnline(online);

  Future<int> drainOfflineInbox() => p2pService.drainOfflineInboxCount();

  void dispose() {
    messageDeletionListener?.dispose();
    reactionListener?.dispose();
    chatListener.dispose();
    router?.dispose();
    p2pService.dispose();
  }
}
