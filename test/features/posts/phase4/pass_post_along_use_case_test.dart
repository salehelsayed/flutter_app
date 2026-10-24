import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';

import 'package:flutter_app/core/bridge/bridge.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

import '../support/legacy_post_state.dart';

void main() {
  late FakeP2PNetwork network;
  late FakeP2PService aliceService;
  late FakeP2PService bobService;
  late FakeP2PService caraService;
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;
  late PassthroughCryptoBridge bridge;
  Directory? tempDir;

  setUp(() {
    network = FakeP2PNetwork();
    aliceService = FakeP2PService(peerId: 'peer-alice', network: network);
    bobService = FakeP2PService(peerId: 'peer-bob', network: network);
    caraService = FakeP2PService(peerId: 'peer-cara', network: network);
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    bridge = PassthroughCryptoBridge();
    tempDir = null;

    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-cara', 'Cara'));
  });

  tearDown(() {
    tempDir?.deleteSync(recursive: true);
    posts.dispose();
    aliceService.dispose();
    bobService.dispose();
    caraService.dispose();
  });

  test(
    'rejects legacy pass: passes an eligible direct post along with a renderable original snapshot',
    () async {
      await posts.savePost(_directPost());

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: includes stored media attachments in the outgoing original snapshot',
    () async {
      await posts.savePost(_directPost(mediaKind: 'image'));
      await posts.savePostMediaAttachment(
        const PostMediaAttachmentModel(
          mediaId: 'media-1',
          postId: 'post-1',
          blobId: 'blob-1',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: 248120,
          width: 1440,
          height: 1080,
          localPath: 'post_media/post-1/blob-1.jpg',
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      );

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
        prepareRepostMediaFn: _noopMediaPrep,
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: createLocalPostPass resolves stored repost media paths before media prep',
    () async {
      await posts.savePost(_directPost(mediaKind: 'image'));
      await posts.savePostMediaAttachment(
        const PostMediaAttachmentModel(
          mediaId: 'media-1',
          postId: 'post-1',
          blobId: 'blob-1',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: 248120,
          width: 1440,
          height: 1080,
          localPath: 'post_media/post-1/blob-1.jpg',
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      );
      final mediaFileManager = FakeMediaFileManager();
      List<PostMediaAttachmentModel>? preparedMedia;

      final before = await snapshotLegacyPostState(posts);
      final rejection = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
        resolveStoredPathFn: mediaFileManager.resolveStoredPath,
        prepareRepostMediaFn:
            ({
              required bridge,
              required originalMedia,
              required passerPeerId,
              required recipientPeerIds,
              required originalAuthorPeerId,
            }) async {
              preparedMedia = originalMedia;
              return RepostMediaPrepResult(
                attachments: originalMedia,
                keys: const <String, PostMediaCryptoEntry>{},
              );
            },
      );
      expect(preparedMedia, isNull);
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: pass upload advertises kOpaqueMediaTransportMime (G7a)',
    () async {
      tempDir = await Directory.systemTemp.createTemp('pass-post-opaque-mime-');
      final localFile = File('${tempDir!.path}/blob-1.jpg');
      await localFile.writeAsBytes(const <int>[1, 2, 3, 4]);
      await posts.savePost(_directPost(mediaKind: 'image'));
      await posts.savePostMediaAttachment(
        PostMediaAttachmentModel(
          mediaId: 'media-1',
          postId: 'post-1',
          blobId: 'blob-1',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: 4,
          localPath: localFile.path,
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      );

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: createLocalPostPass returns mediaPreparationFailed when blob crypto bridge support is missing',
    () async {
      tempDir = await Directory.systemTemp.createTemp(
        'pass-post-missing-blob-plugin-',
      );
      final localFile = File('${tempDir!.path}/blob-1.jpg');
      await localFile.writeAsBytes(const <int>[1, 2, 3, 4]);
      await posts.savePost(_directPost(mediaKind: 'image'));
      await posts.savePostMediaAttachment(
        PostMediaAttachmentModel(
          mediaId: 'media-1',
          postId: 'post-1',
          blobId: 'blob-1',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: 4,
          localPath: localFile.path,
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      );

      final before = await snapshotLegacyPostState(posts);
      final rejection = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: _MissingBlobPluginBridge(),
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: includes processed avatar in encrypted repost payload when avatar exists',
    () async {
      await posts.savePost(_directPost());
      final avatarBytes = _avatarSnapshotBytes();
      final processedAvatarBytes = _avatarSnapshotBytes(red: 200);

      await _captureFlowEvents(() async {
        final before = await snapshotLegacyPostState(posts);
        final rejection = await passPostAlong(
          p2pService: aliceService,
          postRepo: posts,
          contactRepo: contacts,
          bridge: bridge,
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          recipientPeerIds: const <String>['peer-cara'],
          loadAvatarBytesFn: (_) async => avatarBytes,
          avatarNormalizer: _makeAvatarNormalizer(processedAvatarBytes),
        );
        expect(rejection.$1, PassPostAlongResult.notAllowed);
        expect(rejection.$2, isNull);
        expect(await snapshotLegacyPostState(posts), before);
        expect(network.deliverCallCount, 0);
        expect(network.storeInInboxCallCount, 0);
      });
    },
  );

  test(
    'rejects legacy pass: omits avatar in encrypted repost payload when no avatar exists',
    () async {
      await posts.savePost(_directPost());

      await _captureFlowEvents(() async {
        final before = await snapshotLegacyPostState(posts);
        final rejection = await passPostAlong(
          p2pService: aliceService,
          postRepo: posts,
          contactRepo: contacts,
          bridge: bridge,
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          recipientPeerIds: const <String>['peer-cara'],
          loadAvatarBytesFn: (_) async => null,
        );
        expect(rejection.$1, PassPostAlongResult.notAllowed);
        expect(rejection.$2, isNull);
        expect(await snapshotLegacyPostState(posts), before);
        expect(network.deliverCallCount, 0);
        expect(network.storeInInboxCallCount, 0);
      });
    },
  );

  test(
    'rejects legacy pass: includes a valid but oversized local avatar after client-side processing',
    () async {
      await posts.savePost(_directPost());
      final avatarBytes = _validButOversizedAvatarBytes();
      final processedAvatarBytes = _avatarSnapshotBytes(red: 200);
      final probe = _AvatarProcessingProbe();

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
        loadAvatarBytesFn: (_) async => avatarBytes,
        avatarNormalizer: _makeAvatarNormalizer(
          processedAvatarBytes,
          probe: probe,
        ),
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: omits avatar in encrypted repost payload when processed avatar still exceeds the 64 KB bound',
    () async {
      await posts.savePost(_directPost());
      final avatarBytes = _avatarSnapshotBytes();
      final processedAvatarBytes = _validButOversizedAvatarBytes();

      await _captureFlowEvents(() async {
        final before = await snapshotLegacyPostState(posts);
        final rejection = await passPostAlong(
          p2pService: aliceService,
          postRepo: posts,
          contactRepo: contacts,
          bridge: bridge,
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          recipientPeerIds: const <String>['peer-cara'],
          loadAvatarBytesFn: (_) async => avatarBytes,
          avatarNormalizer: _makeAvatarNormalizer(processedAvatarBytes),
        );
        expect(rejection.$1, PassPostAlongResult.notAllowed);
        expect(rejection.$2, isNull);
        expect(await snapshotLegacyPostState(posts), before);
        expect(network.deliverCallCount, 0);
        expect(network.storeInInboxCallCount, 0);
      });
    },
  );

  test(
    'rejects legacy pass: omits avatar but still delivers the repost when loading the local avatar throws',
    () async {
      await posts.savePost(_directPost());

      await _captureFlowEvents(() async {
        final before = await snapshotLegacyPostState(posts);
        final rejection = await passPostAlong(
          p2pService: aliceService,
          postRepo: posts,
          contactRepo: contacts,
          bridge: bridge,
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          recipientPeerIds: const <String>['peer-cara'],
          loadAvatarBytesFn: (_) async {
            throw const FileSystemException('avatar unreadable');
          },
        );
        expect(rejection.$1, PassPostAlongResult.notAllowed);
        expect(rejection.$2, isNull);
        expect(await snapshotLegacyPostState(posts), before);
        expect(network.deliverCallCount, 0);
        expect(network.storeInInboxCallCount, 0);
      });
    },
  );

  test(
    'rejects legacy pass: omits avatar safely when avatar normalization fails on unreadable bytes',
    () async {
      await posts.savePost(_directPost());
      final avatarBytes = Uint8List.fromList(const <int>[255, 0, 1, 2]);

      await _captureFlowEvents(() async {
        final before = await snapshotLegacyPostState(posts);
        final rejection = await passPostAlong(
          p2pService: aliceService,
          postRepo: posts,
          contactRepo: contacts,
          bridge: bridge,
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          recipientPeerIds: const <String>['peer-cara'],
          loadAvatarBytesFn: (_) async => avatarBytes,
          avatarNormalizer: _makeThrowingAvatarNormalizer(),
        );
        expect(rejection.$1, PassPostAlongResult.notAllowed);
        expect(rejection.$2, isNull);
        expect(await snapshotLegacyPostState(posts), before);
        expect(network.deliverCallCount, 0);
        expect(network.storeInInboxCallCount, 0);
      });
    },
  );

  test(
    'rejects legacy pass: cleans up avatar temp directories after repeated repost attempts',
    () async {
      await posts.savePost(_directPost());
      final avatarBytes = Uint8List.fromList(const <int>[7, 7, 7, 7]);
      final beforeAvatarEntries = await _listAvatarTempEntries(
        postId: 'post-1',
        authorPeerId: 'peer-bob',
      );

      for (var i = 0; i < 3; i++) {
        final before = await snapshotLegacyPostState(posts);
        final rejection = await createLocalPostPass(
          p2pService: aliceService,
          postRepo: posts,
          contactRepo: contacts,
          bridge: bridge,
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          recipientPeerIds: const <String>['peer-cara'],
          loadAvatarBytesFn: (_) async => avatarBytes,
          avatarNormalizer: _makeThrowingAvatarNormalizer(),
        );
        expect(rejection.$1, PassPostAlongResult.notAllowed);
        expect(rejection.$2, isNull);
        expect(await snapshotLegacyPostState(posts), before);
        expect(network.deliverCallCount, 0);
        expect(network.storeInInboxCallCount, 0);
        final repeated = await createLocalPostPass(
          p2pService: aliceService,
          postRepo: posts,
          contactRepo: contacts,
          bridge: bridge,
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          recipientPeerIds: const <String>['peer-cara'],
          loadAvatarBytesFn: (_) async => avatarBytes,
          avatarNormalizer: _makeThrowingAvatarNormalizer(),
        );
        expect(repeated.$1, PassPostAlongResult.notAllowed);
        expect(await snapshotLegacyPostState(posts), before);
      }
      expect(
        await _listAvatarTempEntries(
          postId: 'post-1',
          authorPeerId: 'peer-bob',
        ),
        beforeAvatarEntries,
      );
    },
  );

  test(
    'rejects legacy pass: calls loadAvatarBytesFn exactly once with the original author peer id',
    () async {
      await posts.savePost(_directPost());
      final requestedPeerIds = <String>[];

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
        loadAvatarBytesFn: (peerId) async {
          requestedPeerIds.add(peerId);
          return _avatarSnapshotBytes();
        },
        avatarNormalizer: _makeAvatarNormalizer(_avatarSnapshotBytes(red: 200)),
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: createLocalPostPass persists processed avatar snapshot in durable state before delivery starts',
    () async {
      await posts.savePost(_directPost());
      final avatarBytes = _avatarSnapshotBytes();
      final processedAvatarBytes = _avatarSnapshotBytes(red: 200);

      final before = await snapshotLegacyPostState(posts);
      final rejection = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
        loadAvatarBytesFn: (_) async => avatarBytes,
        avatarNormalizer: _makeAvatarNormalizer(processedAvatarBytes),
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: still emits an event-count repost baseline when a local pass fans out to multiple recipients',
    () async {
      await posts.savePost(_directPost());

      final before = await snapshotLegacyPostState(posts);
      final rejection = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: runner-backed repost delivery encrypts repost payloads per recipient and carries the shared-thread baseline contract',
    () async {
      await posts.savePost(_directPost(mediaKind: 'image'));
      await posts.savePostMediaAttachment(
        const PostMediaAttachmentModel(
          mediaId: 'media-1',
          postId: 'post-1',
          blobId: 'blob-original-1',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: 248120,
          width: 1440,
          height: 1080,
          localPath: 'post_media/post-1/blob-original-1.jpg',
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      );

      final before = await snapshotLegacyPostState(posts);
      final rejection = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
        prepareRepostMediaFn: _noopMediaPrep,
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: createLocalPostPass persists a local pass and queued recipient deliveries before background delivery starts',
    () async {
      await posts.savePost(_directPost());

      final before = await snapshotLegacyPostState(posts);
      final rejection = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: createLocalPostPass persists recipient_count from the explicit audience and excludes the original-author notification copy',
    () async {
      await posts.savePost(_directPost());

      final before = await snapshotLegacyPostState(posts);
      final rejection = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: createLocalPostPass persists shared-thread participant, heart, and repost baselines before background delivery starts',
    () async {
      await posts.savePost(_directPost());
      await _seedExistingRepostThreadState(posts);

      final before = await snapshotLegacyPostState(posts);
      final rejection = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: persists a local pass and shared recipient deliveries before delivery completes',
    () async {
      await posts.savePost(_directPost());
      network.deliveryDelay = const Duration(milliseconds: 150);

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: passPostAlong persists shared-thread participant, heart, and repost baselines before delivery settles',
    () async {
      await posts.savePost(_directPost());
      await _seedExistingRepostThreadState(posts);
      network.deliveryDelay = const Duration(milliseconds: 150);

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: does not create a duplicate delivery target when the sender explicitly selects the original author',
    () async {
      await posts.savePost(_directPost());

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
      final repeated = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
      );
      expect(repeated.$1, PassPostAlongResult.notAllowed);
      expect(await snapshotLegacyPostState(posts), before);
    },
  );

  test(
    'rejects legacy pass: passPostAlong uses the post delivery runner default concurrency cap of 25',
    () async {
      final recipientPeerIds = List<String>.generate(
        30,
        (index) => 'peer-${index.toString().padLeft(2, '0')}',
      );
      final sendGates = <String, Completer<void>>{
        for (final peerId in recipientPeerIds) peerId: Completer<void>(),
      };
      final service = _ControlledP2PService(
        peerId: 'peer-bob',
        network: network,
        policies: {
          for (final peerId in recipientPeerIds)
            peerId: _PeerPolicy(sendGate: sendGates[peerId]),
        },
      );
      addTearDown(service.dispose);

      await posts.savePost(_directPost());
      for (final peerId in recipientPeerIds) {
        contacts.addTestContact(_contact(peerId, peerId));
      }

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: service,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        senderUsername: 'Bob',
        recipientPeerIds: recipientPeerIds,
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: deliverCreatedLocalPostPass keeps the local pass and queued recipient deliveries when every delivery path fails',
    () async {
      await posts.savePost(_directPost());
      bobService.setOnline(false);
      caraService.setOnline(false);
      network.inboxDisabled = true;

      final before = await snapshotLegacyPostState(posts);
      final rejection = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: keeps a local pass and retryable recipient-delivery state when the author notification is unresolved',
    () async {
      await posts.savePost(_directPost());
      bobService.setOnline(false);
      network.inboxDisabled = true;

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: rejects a non-renderable snapshot before persisting a local pass or recipient-delivery state',
    () async {
      await posts.savePost(_directPost(mediaKind: 'image'));

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: blocks pass-along for pick-people posts',
    () async {
      await posts.savePost(
        _directPost(
          audience: PostAudience.pickPeople(const <String>['peer-alice']),
        ),
      );

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pass: enforces the explicit one-hop rule for already-passed posts',
    () async {
      await posts.savePost(_directPost(senderPeerId: 'peer-james'));

      final before = await snapshotLegacyPostState(posts);
      final rejection = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(rejection.$1, PassPostAlongResult.notAllowed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );
}

class _MissingBlobPluginBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    if (parsed['cmd'] == 'blob:keygen') {
      throw MissingPluginException(
        'No implementation found for method blobKeygen on channel com.mknoon/go_bridge',
      );
    }
    return super.send(message);
  }
}

ContactModel _contact(
  String peerId,
  String username, {
  String? mlKemPublicKey,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    mlKemPublicKey: mlKemPublicKey ?? 'mlkem-$peerId',
  );
}

PostModel _directPost({
  PostAudience? audience,
  String senderPeerId = 'peer-bob',
  String mediaKind = 'none',
}) {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: senderPeerId,
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: 'Lost dog near Neckar bridge.',
    audience: audience ?? PostAudience.peopleNearby(radiusM: 2000),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
    mediaKind: mediaKind,
  );
}

Future<void> _seedExistingRepostThreadState(
  InMemoryPostRepository posts,
) async {
  await posts.savePostPass(
    const PostPassModel(
      passId: 'pass-existing',
      eventId: 'evt-pass-existing',
      postId: 'post-1',
      senderPeerId: 'peer-alice',
      passerPeerId: 'peer-alice',
      passerUsername: 'Alice',
      passedAt: '2026-03-15T11:05:00.000Z',
      createdAt: '2026-03-15T11:05:00.000Z',
    ),
  );
  await posts.saveRepostEngagementParticipant(
    postId: 'post-1',
    participantPeerId: 'peer-zoya',
    createdAt: '2026-03-15T11:05:00.000Z',
  );
  await posts.saveRepostHeartBaselinePeerIds(
    postId: 'post-1',
    peerIds: const <String>['peer-zoya'],
    createdAt: '2026-03-15T11:05:00.000Z',
  );
  await posts.seedRepostTotalBaseline(
    postId: 'post-1',
    repostTotalBaseline: 2,
    existingLocalPassCount: 1,
    createdAt: '2026-03-15T11:05:00.000Z',
  );
}

Uint8List _validButOversizedAvatarBytes() {
  final builder = BytesBuilder(copy: false)
    ..add(_avatarSnapshotBytes())
    ..add(Uint8List(70000));
  return builder.toBytes();
}

Uint8List _avatarSnapshotBytes({int red = 60}) {
  final image = img.Image(width: 16, height: 16);
  img.fill(image, color: img.ColorRgb8(red, 120, 200));
  return Uint8List.fromList(img.encodePng(image));
}

class _AvatarProcessingProbe {
  int? quality;
  bool? keepExif;
  int? minWidth;
  int? minHeight;
}

AvatarNormalizationHelper _makeAvatarNormalizer(
  Uint8List processedBytes, {
  _AvatarProcessingProbe? probe,
}) {
  return AvatarNormalizationHelper(
    imageProcessor: ImageProcessor(
      compressFile:
          ({
            required String path,
            required int quality,
            required bool keepExif,
            int minWidth = 1920,
            int minHeight = 1080,
          }) async {
            probe?.quality = quality;
            probe?.keepExif = keepExif;
            probe?.minWidth = minWidth;
            probe?.minHeight = minHeight;
            final outputPath = '${path}_processed.jpg';
            await File(outputPath).writeAsBytes(processedBytes, flush: true);
            return XFile(outputPath);
          },
    ),
  );
}

AvatarNormalizationHelper _makeThrowingAvatarNormalizer() {
  return AvatarNormalizationHelper(
    imageProcessor: ImageProcessor(
      compressFile:
          ({
            required String path,
            required int quality,
            required bool keepExif,
            int minWidth = 1920,
            int minHeight = 1080,
          }) async {
            throw const FileSystemException('avatar decode failed');
          },
    ),
  );
}

Future<Set<String>> _listAvatarTempEntries({
  required String postId,
  required String authorPeerId,
}) async {
  final prefix = 'post-pass-avatar-${postId}_$authorPeerId-';
  final entities = await Directory.systemTemp.list().toList();
  return entities
      .whereType<Directory>()
      .map((directory) => directory.path.split(Platform.pathSeparator).last)
      .where((name) => name.startsWith(prefix))
      .toSet();
}

Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() body,
) async {
  final originalDebugPrint = debugPrint;
  final events = <Map<String, dynamic>>[];
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null || !message.startsWith('[FLOW] ')) {
      return;
    }
    final decoded = jsonDecode(message.substring('[FLOW] '.length));
    if (decoded is Map<String, dynamic>) {
      events.add(decoded);
    }
  };
  try {
    await body();
  } finally {
    debugPrint = originalDebugPrint;
  }
  return events;
}

/// A no-op media preparation function that passes attachments through
/// unchanged, for tests that don't need real file I/O.
Future<RepostMediaPrepResult?> _noopMediaPrep({
  required Bridge bridge,
  required List<PostMediaAttachmentModel> originalMedia,
  required String passerPeerId,
  required List<String> recipientPeerIds,
  required String originalAuthorPeerId,
}) async {
  return RepostMediaPrepResult(
    attachments: originalMedia,
    keys: const <String, PostMediaCryptoEntry>{},
  );
}

class _ControlledP2PService extends FakeP2PService {
  final Map<String, _PeerPolicy> policies;
  final List<String> sendStartOrder = <String>[];
  final StreamController<void> _sendStarted =
      StreamController<void>.broadcast();
  final Set<String> _dialedPeers = <String>{};

  int _inFlightSends = 0;
  int maxInFlightSends = 0;

  _ControlledP2PService({
    required super.peerId,
    required super.network,
    this.policies = const <String, _PeerPolicy>{},
  });

  Future<void> waitForSendCount(int count) async {
    while (sendStartOrder.length < count) {
      await _sendStarted.stream.first;
    }
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final policy = policies[targetPeerId] ?? const _PeerPolicy();
    if (policy.requireDiscoverAndDialBeforeSend &&
        !_dialedPeers.contains(targetPeerId)) {
      return const SendMessageResult(sent: false);
    }
    sendStartOrder.add(targetPeerId);
    _inFlightSends++;
    if (_inFlightSends > maxInFlightSends) {
      maxInFlightSends = _inFlightSends;
    }
    _sendStarted.add(null);

    try {
      final gate = policy.sendGate;
      if (gate != null) {
        await gate.future;
      }
      return const SendMessageResult(sent: true, reply: 'received');
    } finally {
      _inFlightSends--;
    }
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    return DiscoveredPeer(
      id: peerId,
      addresses: <String>['/ip4/127.0.0.1/tcp/4001/p2p/$peerId'],
    );
  }

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async {
    _dialedPeers.add(peerId);
    return true;
  }

  @override
  void dispose() {
    _sendStarted.close();
    super.dispose();
  }
}

class _PeerPolicy {
  final Completer<void>? sendGate;
  final bool requireDiscoverAndDialBeforeSend = false;

  const _PeerPolicy({this.sendGate});
}
