import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/message_deletion_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_deletion_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../domain/repositories/fake_reaction_repository.dart';

const _senderPeerId = 'peer-alice';

ChatMessage _makeDeletionMessage({
  String senderPeerId = _senderPeerId,
  String messageId = 'msg-1',
}) {
  final payload = MessageDeletionPayload(
    messageId: messageId,
    senderPeerId: senderPeerId,
    timestamp: '2026-03-31T10:05:00.000Z',
  );
  return ChatMessage(
    from: senderPeerId,
    to: 'peer-bob',
    content: MessageDeletionPayload.buildEncryptedEnvelope(
      senderPeerId: senderPeerId,
      kem: 'fake-kem',
      ciphertext: payload.toInnerJson(),
      nonce: 'fake-nonce',
    ),
    timestamp: '2026-03-31T10:05:00.000Z',
    isIncoming: true,
  );
}

void main() {
  late StreamController<ChatMessage> deletionStreamController;
  late FakeContactRepository contactRepo;
  late FakeMessageRepository messageRepo;
  late FakeReactionRepository reactionRepo;
  late FakeMediaAttachmentRepository mediaAttachmentRepo;
  late FakeMediaFileManager mediaFileManager;
  late MessageDeletionListener listener;

  setUp(() {
    deletionStreamController = StreamController<ChatMessage>.broadcast();
    contactRepo = FakeContactRepository()
      ..seed([
        ContactModel(
          peerId: _senderPeerId,
          publicKey: 'pk',
          rendezvous: '/relay',
          username: 'Alice',
          signature: 'sig',
          scannedAt: '2026-01-01T00:00:00.000Z',
        ),
      ]);
    messageRepo = FakeMessageRepository()
      ..seed([
        const ConversationMessage(
          id: 'msg-1',
          contactPeerId: _senderPeerId,
          senderPeerId: _senderPeerId,
          text: 'hello',
          timestamp: '2026-03-31T10:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-03-31T10:00:01.000Z',
        ),
      ]);
    reactionRepo = FakeReactionRepository();
    mediaAttachmentRepo = FakeMediaAttachmentRepository();
    mediaFileManager = FakeMediaFileManager();

    listener = MessageDeletionListener(
      deletionStream: deletionStreamController.stream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      reactionRepo: reactionRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
      bridge: PassthroughCryptoBridge(),
      getOwnMlKemSecretKey: () async => 'own-secret-key',
    );
  });

  tearDown(() async {
    listener.dispose();
    await deletionStreamController.close();
  });

  group('MessageDeletionListener', () {
    test('start is idempotent and does not duplicate processing', () async {
      final received = <ConversationMessage>[];
      listener.incomingDeletionStream.listen(received.add);

      listener.start();
      listener.start();

      deletionStreamController.add(_makeDeletionMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, hasLength(1));
      expect(received.single.id, 'msg-1');
      expect(received.single.isDeleted, isTrue);

      final stored = await messageRepo.getMessage('msg-1');
      expect(stored, isNotNull);
      expect(stored!.isDeleted, isTrue);
    });

    test('stop cancels subscription and ignores later incoming messages', () async {
      final received = <ConversationMessage>[];
      listener.incomingDeletionStream.listen(received.add);

      listener.start();
      listener.stop();

      deletionStreamController.add(_makeDeletionMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);

      final stored = await messageRepo.getMessage('msg-1');
      expect(stored, isNotNull);
      expect(stored!.isDeleted, isFalse);
    });

    test('dispose closes stream', () {
      listener.start();
      listener.dispose();
      // No error on dispose.
    });
  });
}
