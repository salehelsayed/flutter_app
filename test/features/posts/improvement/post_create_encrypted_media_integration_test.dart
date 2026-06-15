import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/download_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/encrypted_media_test_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

const _createdAt = '2026-03-15T10:15:30.000Z';

void main() {
  late FakeP2PNetwork network;
  late RelayMediaStore relayStore;
  late Directory tempDir;
  late _EncryptedPostUser author;
  late _EncryptedPostUser recipient1;
  late _EncryptedPostUser recipient2;
  late _EncryptedPostUser recipient3;

  setUp(() {
    network = FakeP2PNetwork();
    relayStore = RelayMediaStore();
    tempDir = Directory.systemTemp.createTempSync('post-create-enc-media-');
    author = _EncryptedPostUser.create(
      peerId: 'peer-alice',
      username: 'Alice',
      network: network,
      relayStore: relayStore,
      baseDir: '${tempDir.path}/alice',
    );
    recipient1 = _EncryptedPostUser.create(
      peerId: 'peer-bob',
      username: 'Bob',
      network: network,
      relayStore: relayStore,
      baseDir: '${tempDir.path}/bob',
    );
    recipient2 = _EncryptedPostUser.create(
      peerId: 'peer-cara',
      username: 'Cara',
      network: network,
      relayStore: relayStore,
      baseDir: '${tempDir.path}/cara',
    );
    recipient3 = _EncryptedPostUser.create(
      peerId: 'peer-dana',
      username: 'Dana',
      network: network,
      relayStore: relayStore,
      baseDir: '${tempDir.path}/dana',
    );

    for (final recipient in <_EncryptedPostUser>[
      recipient1,
      recipient2,
      recipient3,
    ]) {
      author.addContact(recipient);
      recipient.addContact(author);
      recipient.start();
    }
  });

  tearDown(() {
    for (final user in <_EncryptedPostUser>[
      author,
      recipient1,
      recipient2,
      recipient3,
    ]) {
      // KC-P4/G8 end to end: nobody ever deletes a posts relay blob.
      expect(user.bridge.commandLog, isNot(contains('media:delete')));
      user.dispose();
    }
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Uint8List plaintextBytes() => Uint8List.fromList(
        List<int>.generate(512, (index) => (index * 23 + 1) & 0xff),
      );

  Future<List<PostMediaAttachmentModel>> attachAndDeliver({
    required List<_EncryptedPostUser> recipients,
  }) async {
    final source = File('${tempDir.path}/alice-source.jpg')
      ..writeAsBytesSync(plaintextBytes(), flush: true);

    final post = PostModel(
      id: 'post-1',
      eventId: 'evt-post-1',
      senderPeerId: author.peerId,
      authorPeerId: author.peerId,
      authorUsername: author.username,
      text: 'encrypted media post',
      audience: PostAudience.allFriends(),
      createdAt: _createdAt,
      visibleAt: _createdAt,
      expiresAt: '2026-03-18T10:15:30.000Z',
      isIncoming: false,
      deliveryStatus: 'sending',
      mediaKind: 'image',
    );
    await author.postRepo.savePost(post);
    for (final recipient in recipients) {
      await author.postRepo.saveRecipientDelivery(
        PostRecipientDelivery(
          postId: 'post-1',
          recipientPeerId: recipient.peerId,
          deliveryStatus: 'pending',
          lastAttemptAt: _createdAt,
          deliveryPath: 'post_create',
          createdAt: _createdAt,
          updatedAt: _createdAt,
        ),
      );
    }

    final (attachResult, attachments) = await attachPostMedia(
      postId: 'post-1',
      postRepo: author.postRepo,
      secureKeyStore: author.secureKeyStore,
      imageProcessor: author.imageProcessor,
      drafts: <PostMediaDraft>[
        PostMediaDraft(localFilePath: source.path, mime: 'image/jpeg'),
      ],
      mediaFileManager: author.mediaFileManager,
      bridge: author.bridge,
    );
    expect(attachResult, AttachPostMediaResult.success);

    final preparedPost = post.copyWith(media: attachments);
    await author.postRepo.savePost(preparedPost);

    final (deliveryResult, _) = await PostDeliveryRunner(
      p2pService: author.p2pService,
      postRepo: author.postRepo,
      bridge: author.bridge,
    ).execute(
      CreatedLocalPost(
        post: preparedPost,
        resolvedRecipients: recipients
            .map(
              (recipient) => CreatedLocalPostRecipient(
                contact: author.contactFor(recipient.peerId),
              ),
            )
            .toList(growable: false),
      ),
    );
    expect(deliveryResult, SendPostResult.success);
    return attachments;
  }

  test(
    'author attaches, delivers; recipient joins keys and downloadPostMedia restores byte-identical plaintext',
    () async {
      final attachments = await attachAndDeliver(
        recipients: <_EncryptedPostUser>[recipient1],
      );
      final attachment = attachments.single;

      // Relay holds ciphertext, never the plaintext.
      final relayBytes = relayStore.uploadedBytesByBlobId[attachment.blobId]!;
      expect(relayBytes, isNot(orderedEquals(plaintextBytes())));

      await recipient1.waitForDownloadedMedia('post-1');

      final received =
          (await recipient1.postRepo.loadPostMediaAttachments('post-1'))
              .single;
      expect(received.isEncrypted, isTrue);
      expect(received.encryptionKeyBase64, attachment.encryptionKeyBase64);
      expect(received.encryptionScheme, attachment.encryptionScheme);
      expect(received.contentHash, attachment.contentHash);
      expect(received.downloadStatus, 'done');

      final restoredBytes = File(
        await recipient1.mediaFileManager.resolveStoredPath(
          received.localPath!,
        ),
      ).readAsBytesSync();
      expect(restoredBytes, orderedEquals(plaintextBytes()));

      // Command-log counts: one keygen+encrypt+upload per attachment, one
      // message.encrypt per recipient.
      expect(
        author.bridge.commandLog.where((command) => command == 'blob:encrypt'),
        hasLength(1),
      );
      expect(
        author.bridge.commandLog.where((command) => command == 'media:upload'),
        hasLength(1),
      );
      expect(
        author.bridge.commandLog.where(
          (command) => command == 'message.encrypt',
        ),
        hasLength(1),
      );
    },
  );

  test('legacy plaintext post from an old sender still round-trips',
      () async {
    relayStore.uploadedBytesByBlobId['blob-legacy-1'] = plaintextBytes();
    relayStore.mimeByBlobId['blob-legacy-1'] = 'image/jpeg';

    final legacyWire = jsonEncode(<String, Object?>{
      'type': 'post_create',
      'version': '1',
      'event_id': 'evt-post-1',
      'created_at': _createdAt,
      'sender_peer_id': author.peerId,
      'payload': <String, Object?>{
        'post_id': 'post-1',
        'snapshot': <String, Object?>{
          'post_id': 'post-1',
          'author_peer_id': author.peerId,
          'author_username': author.username,
          'post_created_at': _createdAt,
          'audience': <String, Object?>{'kind': 'all_friends'},
          'text': 'legacy plaintext media post',
          'media_kind': 'image',
          'media': <Object?>[
            <String, Object?>{
              'media_id': 'media-legacy-1',
              'blob_id': 'blob-legacy-1',
              'kind': 'image',
              'mime': 'image/jpeg',
              'size_bytes': 512,
            },
          ],
          'keep_available': false,
          'expires_at': '2026-03-18T10:15:30.000Z',
        },
      },
    });
    await author.p2pService.sendMessageWithReply(recipient1.peerId, legacyWire);

    await recipient1.waitForDownloadedMedia('post-1');
    final received =
        (await recipient1.postRepo.loadPostMediaAttachments('post-1')).single;
    expect(received.isEncrypted, isFalse);
    expect(received.encryptionKeyBase64, isNull);
    expect(received.downloadStatus, 'done');
    final restoredBytes = File(
      await recipient1.mediaFileManager.resolveStoredPath(received.localPath!),
    ).readAsBytesSync();
    expect(restoredBytes, orderedEquals(plaintextBytes()));
    expect(recipient1.bridge.commandLog, isNot(contains('blob:decrypt')));
  });

  test(
    'three recipients all download and decrypt the same blob; no recipient deletes it',
    () async {
      final attachments = await attachAndDeliver(
        recipients: <_EncryptedPostUser>[recipient1, recipient2, recipient3],
      );
      final attachment = attachments.single;

      for (final recipient in <_EncryptedPostUser>[
        recipient1,
        recipient2,
        recipient3,
      ]) {
        await recipient.waitForDownloadedMedia('post-1');
        final received =
            (await recipient.postRepo.loadPostMediaAttachments('post-1'))
                .single;
        final restoredBytes = File(
          await recipient.mediaFileManager.resolveStoredPath(
            received.localPath!,
          ),
        ).readAsBytesSync();
        expect(restoredBytes, orderedEquals(plaintextBytes()));
      }

      // The shared blob survives every download (KC-P4 end to end).
      expect(
        relayStore.uploadedBytesByBlobId.containsKey(attachment.blobId),
        isTrue,
      );
      expect(relayStore.deletedBlobIds, isEmpty);
      expect(
        author.bridge.commandLog.where(
          (command) => command == 'message.encrypt',
        ),
        hasLength(3),
      );
    },
  );

  // ---- Phase 4.1 matrix completion (green-on-arrival pins) ----

  test(
    'voice post round trip: encrypted clip decrypts byte-identical, waveform metadata intact',
    () async {
      final voiceBytes = Uint8List.fromList(
        List<int>.generate(700, (index) => (index * 7 + 9) & 0xff),
      );
      final source = File('${tempDir.path}/alice-clip.m4a')
        ..writeAsBytesSync(voiceBytes, flush: true);
      const waveform = <double>[0.1, 0.8, 0.3, 0.6];

      final post = PostModel(
        id: 'post-voice',
        eventId: 'evt-post-voice',
        senderPeerId: author.peerId,
        authorPeerId: author.peerId,
        authorUsername: author.username,
        text: '',
        audience: PostAudience.allFriends(),
        createdAt: _createdAt,
        visibleAt: _createdAt,
        expiresAt: '2026-03-18T10:15:30.000Z',
        isIncoming: false,
        deliveryStatus: 'sending',
        mediaKind: 'voice',
      );
      await author.postRepo.savePost(post);
      await author.postRepo.saveRecipientDelivery(
        PostRecipientDelivery(
          postId: 'post-voice',
          recipientPeerId: recipient1.peerId,
          deliveryStatus: 'pending',
          lastAttemptAt: _createdAt,
          deliveryPath: 'post_create',
          createdAt: _createdAt,
          updatedAt: _createdAt,
        ),
      );

      final (attachResult, attachments) = await attachPostMedia(
        postId: 'post-voice',
        postRepo: author.postRepo,
        secureKeyStore: author.secureKeyStore,
        imageProcessor: author.imageProcessor,
        drafts: <PostMediaDraft>[
          PostMediaDraft(
            localFilePath: source.path,
            mime: 'audio/mp4',
            durationMs: 2100,
            waveform: waveform,
          ),
        ],
        mediaFileManager: author.mediaFileManager,
        bridge: author.bridge,
      );
      expect(attachResult, AttachPostMediaResult.success);

      final preparedPost = post.copyWith(media: attachments);
      await author.postRepo.savePost(preparedPost);
      final (deliveryResult, _) = await PostDeliveryRunner(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        bridge: author.bridge,
      ).execute(
        CreatedLocalPost(
          post: preparedPost,
          resolvedRecipients: <CreatedLocalPostRecipient>[
            CreatedLocalPostRecipient(
              contact: author.contactFor(recipient1.peerId),
            ),
          ],
        ),
      );
      expect(deliveryResult, SendPostResult.success);

      await recipient1.waitForDownloadedMedia('post-voice');
      final received =
          (await recipient1.postRepo.loadPostMediaAttachments('post-voice'))
              .single;
      expect(received.kind, 'voice');
      expect(received.waveform, waveform);
      expect(received.durationMs, 2100);
      expect(received.isEncrypted, isTrue);
      final restoredBytes = File(
        await recipient1.mediaFileManager.resolveStoredPath(
          received.localPath!,
        ),
      ).readAsBytesSync();
      expect(restoredBytes, orderedEquals(voiceBytes));
    },
  );

  test('carousel (multi-attachment) post: per-attachment keys, all decrypt',
      () async {
    final firstBytes = Uint8List.fromList(
      List<int>.generate(300, (index) => (index * 3 + 1) & 0xff),
    );
    final secondBytes = Uint8List.fromList(
      List<int>.generate(300, (index) => (index * 5 + 2) & 0xff),
    );
    final firstSource = File('${tempDir.path}/alice-one.jpg')
      ..writeAsBytesSync(firstBytes, flush: true);
    final secondSource = File('${tempDir.path}/alice-two.jpg')
      ..writeAsBytesSync(secondBytes, flush: true);

    final post = PostModel(
      id: 'post-carousel',
      eventId: 'evt-post-carousel',
      senderPeerId: author.peerId,
      authorPeerId: author.peerId,
      authorUsername: author.username,
      text: 'carousel',
      audience: PostAudience.allFriends(),
      createdAt: _createdAt,
      visibleAt: _createdAt,
      expiresAt: '2026-03-18T10:15:30.000Z',
      isIncoming: false,
      deliveryStatus: 'sending',
      mediaKind: 'image_carousel',
    );
    await author.postRepo.savePost(post);
    await author.postRepo.saveRecipientDelivery(
      PostRecipientDelivery(
        postId: 'post-carousel',
        recipientPeerId: recipient1.peerId,
        deliveryStatus: 'pending',
        lastAttemptAt: _createdAt,
        deliveryPath: 'post_create',
        createdAt: _createdAt,
        updatedAt: _createdAt,
      ),
    );

    final (attachResult, attachments) = await attachPostMedia(
      postId: 'post-carousel',
      postRepo: author.postRepo,
      secureKeyStore: author.secureKeyStore,
      imageProcessor: author.imageProcessor,
      drafts: <PostMediaDraft>[
        PostMediaDraft(localFilePath: firstSource.path, mime: 'image/jpeg'),
        PostMediaDraft(localFilePath: secondSource.path, mime: 'image/jpeg'),
      ],
      mediaFileManager: author.mediaFileManager,
      bridge: author.bridge,
    );
    expect(attachResult, AttachPostMediaResult.success);
    expect(attachments, hasLength(2));
    expect(
      attachments[0].encryptionKeyBase64,
      isNot(attachments[1].encryptionKeyBase64),
    );

    final preparedPost = post.copyWith(media: attachments);
    await author.postRepo.savePost(preparedPost);
    final (deliveryResult, _) = await PostDeliveryRunner(
      p2pService: author.p2pService,
      postRepo: author.postRepo,
      bridge: author.bridge,
    ).execute(
      CreatedLocalPost(
        post: preparedPost,
        resolvedRecipients: <CreatedLocalPostRecipient>[
          CreatedLocalPostRecipient(
            contact: author.contactFor(recipient1.peerId),
          ),
        ],
      ),
    );
    expect(deliveryResult, SendPostResult.success);

    await recipient1.waitForDownloadedMedia('post-carousel');
    final received = await recipient1.postRepo.loadPostMediaAttachments(
      'post-carousel',
    );
    expect(received, hasLength(2));
    final restoredByPosition = <int, Uint8List>{
      for (final attachment in received)
        attachment.position: File(
          await recipient1.mediaFileManager.resolveStoredPath(
            attachment.localPath!,
          ),
        ).readAsBytesSync(),
    };
    expect(restoredByPosition[0], orderedEquals(firstBytes));
    expect(restoredByPosition[1], orderedEquals(secondBytes));
  });

  test(
    'pass of an encrypted authored post: pass re-mints blobId+key; recipient decrypts via pass media_keys',
    () async {
      // recipient1 receives the encrypted authored post, then passes it
      // along to recipient2 (who never saw the original post_create).
      recipient1.addContact(recipient2);
      recipient2.addContact(recipient1);

      final attachments = await attachAndDeliver(
        recipients: <_EncryptedPostUser>[recipient1],
      );
      final originalBlobId = attachments.single.blobId;
      await recipient1.waitForDownloadedMedia('post-1');

      // Production getPost loads the posts row WITHOUT media (attachment
      // rows are joined separately); the in-memory fake retains the model's
      // envelope-derived media list verbatim. Strip it so the pass flow
      // loads the hydrated keyed rows exactly as production does.
      final storedPost = (await recipient1.postRepo.getPost('post-1'))!;
      await recipient1.postRepo.savePost(
        storedPost.copyWith(media: const <PostMediaAttachmentModel>[]),
      );

      final (passResult, pass) = await passPostAlong(
        p2pService: recipient1.p2pService,
        postRepo: recipient1.postRepo,
        contactRepo: recipient1.contactRepo,
        bridge: recipient1.bridge,
        postId: 'post-1',
        senderPeerId: recipient1.peerId,
        senderUsername: recipient1.username,
        recipientPeerIds: <String>[recipient2.peerId],
        resolveStoredPathFn: recipient1.mediaFileManager.resolveStoredPath,
      );
      expect(passResult, PassPostAlongResult.success);
      expect(pass, isNotNull);

      await recipient2.waitForDownloadedMedia('post-1');
      final received =
          (await recipient2.postRepo.loadPostMediaAttachments('post-1'))
              .single;
      // The pass re-mints a fresh blob + key (shipped pass behavior over the
      // new encrypted source).
      expect(received.blobId, isNot(originalBlobId));
      expect(received.isEncrypted, isTrue);
      expect(
        received.encryptionKeyBase64,
        isNot(attachments.single.encryptionKeyBase64),
      );
      final restoredBytes = File(
        await recipient2.mediaFileManager.resolveStoredPath(
          received.localPath!,
        ),
      ).readAsBytesSync();
      expect(restoredBytes, orderedEquals(plaintextBytes()));
    },
  );
}

class _EncryptedPostUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final EncryptedMediaTestBridge bridge;
  final InMemoryContactRepository contactRepo;
  final InMemoryPostRepository postRepo;
  final IncomingMessageRouter router;
  final PostListener postListener;
  final PostPassListener passListener;
  final FakeSecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;
  final TempPostMediaFileManager mediaFileManager;

  _EncryptedPostUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.bridge,
    required this.contactRepo,
    required this.postRepo,
    required this.router,
    required this.postListener,
    required this.passListener,
    required this.secureKeyStore,
    required this.imageProcessor,
    required this.mediaFileManager,
  });

  static int _nextSeedSalt = 0;

  factory _EncryptedPostUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
    required RelayMediaStore relayStore,
    required String baseDir,
  }) {
    final p2pService = FakeP2PService(peerId: peerId, network: network);
    final bridge = EncryptedMediaTestBridge(
      relayStore,
      // Distinct deterministic key sequences per user/device.
      seedSalt: (_nextSeedSalt += 100),
    );
    final contactRepo = InMemoryContactRepository();
    final postRepo = InMemoryPostRepository();
    final router = IncomingMessageRouter(p2pService: p2pService);
    final mediaFileManager = TempPostMediaFileManager(baseDir);
    Future<PostMediaAttachmentModel> hydrate({
      required PostMediaAttachmentModel attachment,
      required String postId,
    }) {
      return downloadPostMedia(
        bridge: bridge,
        postRepo: postRepo,
        mediaFileManager: mediaFileManager,
        attachment: attachment,
      );
    }

    final postListener = PostListener(
      postCreateStream: router.postCreateStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'test-own-mlkem-sk',
      hydratePostMediaFn: hydrate,
    );
    final passListener = PostPassListener(
      postPassStream: router.postPassStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'test-own-mlkem-sk',
      hydratePostMediaFn: hydrate,
    );

    return _EncryptedPostUser._(
      peerId: peerId,
      username: username,
      p2pService: p2pService,
      bridge: bridge,
      contactRepo: contactRepo,
      postRepo: postRepo,
      router: router,
      postListener: postListener,
      passListener: passListener,
      secureKeyStore: FakeSecureKeyStore(),
      imageProcessor: ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async {
              final processedPath = '${path}_processed';
              File(path).copySync(processedPath);
              return XFile(processedPath);
            },
      ),
      mediaFileManager: mediaFileManager,
    );
  }

  void addContact(_EncryptedPostUser other) {
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

  ContactModel contactFor(String peerId) {
    return ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: '/dns4/example.invalid/tcp/443',
      username: peerId,
      signature: 'sig-$peerId',
      scannedAt: '2026-03-15T10:00:00.000Z',
      mlKemPublicKey: 'mlkem-$peerId',
    );
  }

  void start() {
    router.start();
    postListener.start();
    passListener.start();
  }

  Future<void> waitForDownloadedMedia(String postId) async {
    Future<bool> condition() async {
      final attachments = await postRepo.loadPostMediaAttachments(postId);
      return attachments.isNotEmpty &&
          attachments.every(
            (attachment) => attachment.downloadStatus == 'done',
          );
    }

    if (await condition()) {
      return;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (await condition()) {
        return;
      }
    }
    throw StateError('Timed out waiting for downloaded post media');
  }

  void dispose() {
    passListener.dispose();
    postListener.dispose();
    router.dispose();
    postRepo.dispose();
    p2pService.dispose();
  }
}
