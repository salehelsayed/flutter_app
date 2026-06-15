import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/download_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/encrypted_media_test_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late _EncryptedMediaUser sender;
  late _EncryptedMediaUser author;
  late _EncryptedMediaUser recipient;
  late RelayMediaStore relayStore;
  late Directory tempDir;
  late TempPostMediaFileManager mediaFileManager;

  setUp(() {
    network = FakeP2PNetwork();
    relayStore = RelayMediaStore();
    sender = _EncryptedMediaUser.create(
      peerId: 'peer-hisam',
      username: 'Hisam',
      network: network,
      relayStore: relayStore,
    );
    author = _EncryptedMediaUser.create(
      peerId: 'peer-solz',
      username: 'Solz',
      network: network,
      relayStore: relayStore,
    );
    recipient = _EncryptedMediaUser.create(
      peerId: 'peer-ibra',
      username: 'Ibra',
      network: network,
      relayStore: relayStore,
    );

    sender.addContact(author);
    sender.addContact(recipient);
    author.addContact(sender);
    recipient.addContact(sender);

    author.start();
    recipient.start();

    tempDir = Directory.systemTemp.createTempSync(
      'post-pass-encrypted-media-',
    );
    mediaFileManager = TempPostMediaFileManager(tempDir.path);
  });

  tearDown(() {
    sender.dispose();
    author.dispose();
    recipient.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'encrypted repost media uploads ciphertext, preserves recipient ACL, and decrypts back to the original bytes',
    () async {
      final originalBytes = Uint8List.fromList(
        List<int>.generate(256, (index) => (index * 17) & 0xff),
      );
      final originalFile = File('${tempDir.path}/source-image.jpg');
      await originalFile.writeAsBytes(originalBytes);

      await sender.postRepo.savePost(
        PostModel(
          id: 'post-1',
          eventId: 'evt-post-1',
          senderPeerId: 'peer-solz',
          authorPeerId: 'peer-solz',
          authorUsername: 'Solz',
          text: 'Need help carrying a ladder.',
          audience: PostAudience.allFriends(),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
          isIncoming: true,
          mediaKind: 'image',
        ),
      );
      await sender.postRepo.savePostMediaAttachment(
        PostMediaAttachmentModel(
          mediaId: 'media-1',
          postId: 'post-1',
          blobId: 'blob-original-1',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: originalBytes.length,
          width: 1440,
          height: 1080,
          localPath: originalFile.path,
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      );

      final (result, pass) = await passPostAlong(
        p2pService: sender.p2pService,
        postRepo: sender.postRepo,
        contactRepo: sender.contactRepo,
        bridge: sender.bridge,
        postId: 'post-1',
        senderPeerId: sender.peerId,
        senderUsername: sender.username,
        recipientPeerIds: const <String>['peer-ibra'],
      );

      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);
      expect(
        sender.bridge.commandLog.where((command) => command == 'blob:encrypt'),
        hasLength(1),
      );
      expect(
        sender.bridge.commandLog.where((command) => command == 'media:upload'),
        hasLength(1),
      );
      expect(
        sender.bridge.commandLog.where((command) => command == 'message.encrypt'),
        hasLength(2),
      );

      await _waitForPassCount(sender, expectedCount: 1);
      await _waitForPassCount(author, expectedCount: 1);
      await _waitForPassCount(recipient, expectedCount: 1);

      final relayBlobId = sender.relayStore.blobIds.single;
      expect(relayBlobId, isNot('blob-original-1'));
      expect(sender.relayStore.allowedPeersByBlobId[relayBlobId], isNotNull);
      expect(
        sender.relayStore.allowedPeersByBlobId[relayBlobId]!,
        unorderedEquals(<String>[
          sender.peerId,
          recipient.peerId,
          author.peerId,
        ]),
      );
      expect(
        sender.relayStore.ciphertextByBlobId[relayBlobId],
        isNotNull,
      );
      expect(
        sender.relayStore.ciphertextByBlobId[relayBlobId]!,
        isNot(equals(originalBytes)),
      );

      final recipientPass = (await recipient.postRepo.loadPostPasses('post-1'))
          .single;
      expect(recipientPass.innerPayloadJson, isNotNull);
      await _waitForMediaAttachmentCount(recipient, expectedCount: 1);
      final recipientAttachment = (await recipient.postRepo
              .loadPostMediaAttachments('post-1'))
          .single;
      expect(recipientAttachment.isEncrypted, isTrue);
      expect(recipientAttachment.blobId, relayBlobId);
      expect(recipientAttachment.encryptionKeyBase64, isNotNull);
      expect(recipientAttachment.encryptionNonce, isNotNull);

      final hydratedAttachment = await downloadPostMedia(
        bridge: recipient.bridge,
        postRepo: recipient.postRepo,
        mediaFileManager: mediaFileManager,
        attachment: recipientAttachment,
      );

      expect(hydratedAttachment.downloadStatus, 'done');
      expect(hydratedAttachment.localPath, isNotNull);

      final localPath = await mediaFileManager.localPathForPostAttachment(
        postId: 'post-1',
        blobId: relayBlobId,
        mime: 'image/jpeg',
      );
      final restoredBytes = await File(localPath).readAsBytes();
      expect(restoredBytes, orderedEquals(originalBytes));
    },
  );

  test(
    'pass crypto entries carry scheme=blob_aes_256_gcm_v1 and content_hash of the CIPHERTEXT (G6/MIG-012 provenance)',
    () async {
      final originalBytes = Uint8List.fromList(
        List<int>.generate(256, (index) => (index * 17) & 0xff),
      );
      final originalFile = File('${tempDir.path}/source-image.jpg');
      await originalFile.writeAsBytes(originalBytes);

      await sender.postRepo.savePost(
        PostModel(
          id: 'post-1',
          eventId: 'evt-post-1',
          senderPeerId: 'peer-solz',
          authorPeerId: 'peer-solz',
          authorUsername: 'Solz',
          text: 'Need help carrying a ladder.',
          audience: PostAudience.allFriends(),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
          isIncoming: true,
          mediaKind: 'image',
        ),
      );
      await sender.postRepo.savePostMediaAttachment(
        PostMediaAttachmentModel(
          mediaId: 'media-1',
          postId: 'post-1',
          blobId: 'blob-original-1',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: originalBytes.length,
          localPath: originalFile.path,
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      );

      final (result, _) = await passPostAlong(
        p2pService: sender.p2pService,
        postRepo: sender.postRepo,
        contactRepo: sender.contactRepo,
        bridge: sender.bridge,
        postId: 'post-1',
        senderPeerId: sender.peerId,
        senderUsername: sender.username,
        recipientPeerIds: const <String>['peer-ibra'],
      );
      expect(result, PassPostAlongResult.success);

      await _waitForPassCount(recipient, expectedCount: 1);
      await _waitForMediaAttachmentCount(recipient, expectedCount: 1);

      final relayBlobId = sender.relayStore.blobIds.single;
      final ciphertext = sender.relayStore.ciphertextByBlobId[relayBlobId]!;
      final ciphertextHash = sha256.convert(ciphertext).toString();
      final plaintextHash = sha256.convert(originalBytes).toString();

      final recipientAttachment = (await recipient.postRepo
              .loadPostMediaAttachments('post-1'))
          .single;
      expect(
        recipientAttachment.encryptionScheme,
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
      // Provenance, both directions: the hash IS of the encrypted artifact
      // and is NOT of the plaintext source.
      expect(recipientAttachment.contentHash, ciphertextHash);
      expect(recipientAttachment.contentHash, isNot(plaintextHash));

      final recipientPass = (await recipient.postRepo.loadPostPasses('post-1'))
          .single;
      final innerPayload =
          jsonDecode(recipientPass.innerPayloadJson!) as Map<String, dynamic>;
      final entry = (innerPayload['media_keys']
          as Map<String, dynamic>)['media-1'] as Map<String, dynamic>;
      expect(entry['scheme'], kMediaAttachmentEncryptionSchemeBlobAesGcmV1);
      expect(entry['content_hash'], ciphertextHash);
    },
  );
}

class _EncryptedMediaUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final EncryptedMediaTestBridge bridge;
  final InMemoryContactRepository contactRepo;
  final InMemoryPostRepository postRepo;
  final IncomingMessageRouter router;
  final PostPassListener passListener;

  _EncryptedMediaUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.bridge,
    required this.contactRepo,
    required this.postRepo,
    required this.router,
    required this.passListener,
  });

  factory _EncryptedMediaUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
    required RelayMediaStore relayStore,
  }) {
    final p2pService = FakeP2PService(peerId: peerId, network: network);
    final bridge = EncryptedMediaTestBridge(relayStore);
    final contactRepo = InMemoryContactRepository();
    final postRepo = InMemoryPostRepository();
    final router = IncomingMessageRouter(p2pService: p2pService);
    final passListener = PostPassListener(
      postPassStream: router.postPassStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'test-own-mlkem-sk',
    );

    return _EncryptedMediaUser._(
      peerId: peerId,
      username: username,
      p2pService: p2pService,
      bridge: bridge,
      contactRepo: contactRepo,
      postRepo: postRepo,
      router: router,
      passListener: passListener,
    );
  }

  void addContact(_EncryptedMediaUser other) {
    contactRepo.addTestContact(
      ContactModel(
        peerId: other.peerId,
        publicKey: 'pk-${other.peerId}',
        rendezvous: '/dns4/example.invalid/tcp/443',
        username: other.username,
        signature: 'sig-${other.peerId}',
        scannedAt: '2026-03-15T10:00:00.000Z',
        mlKemPublicKey: 'mlkem-${other.peerId}',
      ),
    );
  }

  void start() {
    router.start();
    passListener.start();
  }

  RelayMediaStore get relayStore => bridge.relayStore;

  void dispose() {
    passListener.dispose();
    router.dispose();
    postRepo.dispose();
    p2pService.dispose();
  }
}

Future<void> _waitForPassCount(
  _EncryptedMediaUser user, {
  required int expectedCount,
}) async {
  Future<bool> condition() async {
    return (await user.postRepo.loadPostPasses('post-1')).length ==
        expectedCount;
  }

  if (await condition()) {
    return;
  }

  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (await condition()) {
      return;
    }
  }

  throw StateError('Timed out waiting for repost delivery');
}

Future<void> _waitForMediaAttachmentCount(
  _EncryptedMediaUser user, {
  required int expectedCount,
}) async {
  Future<bool> condition() async {
    return (await user.postRepo.loadPostMediaAttachments('post-1')).length ==
        expectedCount;
  }

  if (await condition()) {
    return;
  }

  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (await condition()) {
      return;
    }
  }

  throw StateError('Timed out waiting for repost media attachment');
}
