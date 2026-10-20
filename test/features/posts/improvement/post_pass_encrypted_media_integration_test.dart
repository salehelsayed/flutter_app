import '../support/legacy_post_state.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
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

    tempDir = Directory.systemTemp.createTempSync('post-pass-encrypted-media-');
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
    'rejects legacy pass: encrypted repost media uploads ciphertext, preserves recipient ACL, and decrypts back to the original bytes',
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

      final previousPassState = await snapshotLegacyPostState(
        sender.postRepo,
        postId: 'post-1',
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
      expect(result, PassPostAlongResult.notAllowed);
      expect(pass, isNull);
      expect(
        await snapshotLegacyPostState(sender.postRepo, postId: 'post-1'),
        previousPassState,
      );
    },
  );

  test(
    'rejects legacy pass: pass crypto entries carry scheme=blob_aes_256_gcm_v1 and content_hash of the CIPHERTEXT (G6/MIG-012 provenance)',
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

      final previousPassState = await snapshotLegacyPostState(
        sender.postRepo,
        postId: 'post-1',
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
      expect(result, PassPostAlongResult.notAllowed);
      expect(
        await snapshotLegacyPostState(sender.postRepo, postId: 'post-1'),
        previousPassState,
      );
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
