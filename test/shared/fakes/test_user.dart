import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

import '../../core/bridge/fake_bridge.dart';
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

  TestUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.messageRepo,
    required this.contactRepo,
    required this.chatListener,
    required this.bridge,
    this.mediaAttachmentRepo,
  });

  factory TestUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
    MediaAttachmentRepository? mediaAttachmentRepo,
    Bridge? bridge,
    Future<String?> Function()? getOwnMlKemSecretKey,
  }) {
    final effectiveBridge = bridge ?? PassthroughCryptoBridge();
    final p2p = FakeP2PService(peerId: peerId, network: network);
    final msgRepo = InMemoryMessageRepository();
    final contactRepo = InMemoryContactRepository();
    final listener = ChatMessageListener(
      chatMessageStream: p2p.messageStream,
      messageRepo: msgRepo,
      contactRepo: contactRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      bridge: effectiveBridge,
      getOwnMlKemSecretKey:
          getOwnMlKemSecretKey ?? () async => 'test-own-mlkem-sk',
    );

    return TestUser._(
      peerId: peerId,
      username: username,
      p2pService: p2p,
      messageRepo: msgRepo,
      contactRepo: contactRepo,
      chatListener: listener,
      bridge: effectiveBridge,
      mediaAttachmentRepo: mediaAttachmentRepo,
    );
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
      mediaAttachments: null,
      mediaAttachmentRepo: mediaAttachmentRepo,
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
      quotedMessageId: quotedMessageId,
      bridge: bridge,
      recipientMlKemPublicKey: await _mlKemKeyFor(targetPeerId),
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
      mediaAttachments: attachments,
      mediaAttachmentRepo: mediaAttachmentRepo,
      bridge: bridge,
      recipientMlKemPublicKey: await _mlKemKeyFor(targetPeerId),
    );
  }

  /// Loads the conversation with a contact.
  Future<List<ConversationMessage>> loadConversationWith(
      String contactPeerId) {
    return loadConversation(
      messageRepo: messageRepo,
      contactPeerId: contactPeerId,
    );
  }

  void start() => chatListener.start();

  void setOnline(bool online) => p2pService.setOnline(online);

  Future<int> drainOfflineInbox() => p2pService.drainOfflineInboxCount();

  void dispose() {
    chatListener.dispose();
    p2pService.dispose();
  }
}
