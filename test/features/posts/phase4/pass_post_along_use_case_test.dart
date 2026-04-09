import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';

import 'package:flutter_app/core/bridge/bridge.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

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
    'passes an eligible direct post along with a renderable original snapshot',
    () async {
      await posts.savePost(_directPost());

      final receivedByCara = caraService.messageStream.first;

      final (result, pass) = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);

      final message = await receivedByCara.timeout(const Duration(seconds: 1));
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final payload = _decodeEncryptedPassPayload(json);
      final snapshot = payload['original_snapshot'] as Map<String, dynamic>;

      expect(json['type'], 'post_pass');
      expect(json['version'], '2');
      expect(payload['post_id'], 'post-1');
      expect(payload['passer_peer_id'], 'peer-alice');
      expect(snapshot['post_id'], 'post-1');
      expect(snapshot['author_peer_id'], 'peer-bob');
      expect(snapshot['text'], 'Lost dog near Neckar bridge.');
      expect(snapshot['audience'], <String, dynamic>{
        'kind': 'people_nearby',
        'radius_m': 2000,
        'scope_label': 'Shared nearby',
      });
    },
  );

  test(
    'includes stored media attachments in the outgoing original snapshot',
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

      final receivedByCara = caraService.messageStream.first;

      final (result, pass) = await passPostAlong(
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

      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);

      final message = await receivedByCara.timeout(const Duration(seconds: 1));
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final payload = _decodeEncryptedPassPayload(json);
      final snapshot = payload['original_snapshot'] as Map<String, dynamic>;
      final media = (snapshot['media'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(snapshot['media_kind'], 'image');
      expect(media, hasLength(1));
      expect(media.single['media_id'], 'media-1');
      expect(media.single['blob_id'], 'blob-1');
    },
  );

  test(
    'createLocalPostPass resolves stored repost media paths before media prep',
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

      final (result, created) = await createLocalPostPass(
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

      expect(result, PassPostAlongResult.success);
      expect(created, isNotNull);
      expect(preparedMedia, isNotNull);
      expect(
        preparedMedia!.single.localPath,
        endsWith('test_docs/post_media/post-1/blob-1.jpg'),
      );
    },
  );

  test(
    'createLocalPostPass returns mediaPreparationFailed when blob crypto bridge support is missing',
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

      final (result, created) = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: _MissingBlobPluginBridge(),
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.mediaPreparationFailed);
      expect(created, isNull);
      expect(await posts.loadPostPasses('post-1'), isEmpty);
    },
  );

  test(
    'includes processed avatar in encrypted repost payload when avatar exists',
    () async {
      await posts.savePost(_directPost());
      final avatarBytes = Uint8List.fromList(const <int>[1, 2, 3, 4, 5]);
      final processedAvatarBytes = Uint8List.fromList(const <int>[9, 8, 7, 6]);

      final receivedByCara = caraService.messageStream.first;

      final events = await _captureFlowEvents(() async {
        final (result, pass) = await passPostAlong(
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

        expect(result, PassPostAlongResult.success);
        expect(pass, isNotNull);
      });

      final message = await receivedByCara.timeout(const Duration(seconds: 1));
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final snapshot = _decodeEncryptedOriginalSnapshot(json);

      expect(
        snapshot['original_author_avatar_base64'],
        base64Encode(processedAvatarBytes),
      );
      expect(_flowEventDetails(events, 'POST_PASS_AVATAR_LOAD_START'), isNotEmpty);
      expect(
        _flowEventDetails(events, 'POST_PASS_AVATAR_LOAD_SUCCESS'),
        isNotEmpty,
      );
      expect(
        _flowEventDetails(events, 'POST_PASS_AVATAR_PROCESS_START'),
        isNotEmpty,
      );
      expect(
        _flowEventDetails(events, 'POST_PASS_AVATAR_PROCESS_SUCCESS'),
        isNotEmpty,
      );
      expect(
        _flowEventDetails(events, 'POST_PASS_AVATAR_SNAPSHOT_STORED'),
        isNotEmpty,
      );
    },
  );

  test(
    'omits avatar in encrypted repost payload when no avatar exists',
    () async {
      await posts.savePost(_directPost());

      final receivedByCara = caraService.messageStream.first;

      final events = await _captureFlowEvents(() async {
        final (result, pass) = await passPostAlong(
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

        expect(result, PassPostAlongResult.success);
        expect(pass, isNotNull);
      });

      final message = await receivedByCara.timeout(const Duration(seconds: 1));
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final snapshot = _decodeEncryptedOriginalSnapshot(json);

      expect(snapshot.containsKey('original_author_avatar_base64'), isFalse);
      expect(
        _flowEventDetails(events, 'POST_PASS_AVATAR_LOAD_MISSING'),
        isNotEmpty,
      );
    },
  );

  test(
    'includes a valid but oversized local avatar after client-side processing',
    () async {
      await posts.savePost(_directPost());
      final avatarBytes = _validButOversizedAvatarBytes();
      final processedAvatarBytes = Uint8List.fromList(const <int>[
        0xCA,
        0xFE,
        0xBA,
        0xBE,
      ]);
      final probe = _AvatarProcessingProbe();

      final receivedByCara = caraService.messageStream.first;

      final (result, pass) = await passPostAlong(
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

      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);

      final message = await receivedByCara.timeout(const Duration(seconds: 1));
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final snapshot = _decodeEncryptedOriginalSnapshot(json);

      expect(
        snapshot['original_author_avatar_base64'],
        base64Encode(processedAvatarBytes),
      );
      expect(probe.quality, 80);
      expect(probe.keepExif, isFalse);
      expect(probe.minWidth, 512);
      expect(probe.minHeight, 512);
    },
  );

  test(
    'omits avatar in encrypted repost payload when processed avatar still exceeds the 64 KB bound',
    () async {
      await posts.savePost(_directPost());
      final avatarBytes = Uint8List.fromList(const <int>[5, 4, 3, 2, 1]);
      final processedAvatarBytes = _validButOversizedAvatarBytes();
      expect(processedAvatarBytes.length, greaterThan(65536));

      final receivedByCara = caraService.messageStream.first;

      final events = await _captureFlowEvents(() async {
        final (result, pass) = await passPostAlong(
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

        expect(result, PassPostAlongResult.success);
        expect(pass, isNotNull);
      });

      final message = await receivedByCara.timeout(const Duration(seconds: 1));
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final snapshot = _decodeEncryptedOriginalSnapshot(json);

      expect(
        snapshot.containsKey('original_author_avatar_base64'),
        isFalse,
      );
      expect(
        _flowEventDetails(events, 'POST_PASS_AVATAR_OMITTED_TOO_LARGE'),
        isNotEmpty,
      );
    },
  );

  test(
    'omits avatar but still delivers the repost when loading the local avatar throws',
    () async {
      await posts.savePost(_directPost());

      final receivedByCara = caraService.messageStream.first;

      final events = await _captureFlowEvents(() async {
        final (result, pass) = await passPostAlong(
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

        expect(result, PassPostAlongResult.success);
        expect(pass, isNotNull);
      });

      final message = await receivedByCara.timeout(const Duration(seconds: 1));
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final snapshot = _decodeEncryptedOriginalSnapshot(json);

      expect(snapshot.containsKey('original_author_avatar_base64'), isFalse);
      expect(
        _flowEventDetails(events, 'POST_PASS_AVATAR_LOAD_FAILED'),
        isNotEmpty,
      );
      expect(
        _flowEventDetails(events, 'POST_PASS_AVATAR_LOAD_MISSING'),
        isEmpty,
      );
    },
  );

  test(
    'omits avatar safely when avatar normalization fails on unreadable bytes',
    () async {
      await posts.savePost(_directPost());
      final avatarBytes = Uint8List.fromList(const <int>[255, 0, 1, 2]);

      final receivedByCara = caraService.messageStream.first;

      final events = await _captureFlowEvents(() async {
        final (result, pass) = await passPostAlong(
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

        expect(result, PassPostAlongResult.success);
        expect(pass, isNotNull);
      });

      final message = await receivedByCara.timeout(const Duration(seconds: 1));
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final snapshot = _decodeEncryptedOriginalSnapshot(json);

      expect(snapshot.containsKey('original_author_avatar_base64'), isFalse);
      expect(
        _flowEventDetails(events, 'POST_PASS_AVATAR_PROCESS_FAILED'),
        isNotEmpty,
      );
    },
  );

  test(
    'cleans up avatar temp directories after repeated repost attempts',
    () async {
      await posts.savePost(_directPost());
      final avatarBytes = Uint8List.fromList(const <int>[7, 7, 7, 7]);
      final before = await _listAvatarTempEntries(
        postId: 'post-1',
        authorPeerId: 'peer-bob',
      );

      for (var i = 0; i < 3; i++) {
        final (result, pass) = await createLocalPostPass(
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

        expect(result, PassPostAlongResult.success);
        expect(pass, isNotNull);
      }

      final after = await _listAvatarTempEntries(
        postId: 'post-1',
        authorPeerId: 'peer-bob',
      );
      expect(after, before);
    },
  );

  test(
    'calls loadAvatarBytesFn exactly once with the original author peer id',
    () async {
      await posts.savePost(_directPost());
      final requestedPeerIds = <String>[];

      final (result, pass) = await passPostAlong(
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
          return Uint8List.fromList(const <int>[9, 8, 7]);
        },
        avatarNormalizer: _makeAvatarNormalizer(
          Uint8List.fromList(const <int>[9, 8, 7]),
        ),
      );

      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);
      expect(requestedPeerIds, <String>['peer-bob']);
    },
  );

  test(
    'createLocalPostPass persists processed avatar snapshot in durable state before delivery starts',
    () async {
      await posts.savePost(_directPost());
      final avatarBytes = Uint8List.fromList(const <int>[42, 41, 40, 39]);
      final processedAvatarBytes = Uint8List.fromList(const <int>[99, 98, 97]);

      final (result, created) = await createLocalPostPass(
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

      expect(result, PassPostAlongResult.success);
      expect(created, isNotNull);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
      expect(
        await posts.loadPassAvatarSnapshot('post-1'),
        orderedEquals(processedAvatarBytes),
      );
    },
  );

  test(
    'still emits an event-count repost baseline when a local pass fans out to multiple recipients',
    () async {
      await posts.savePost(_directPost());

      final (result, created) = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
      );

      expect(result, PassPostAlongResult.success);
      expect(created, isNotNull);
      expect(created!.recipientPeerIds, <String>['peer-bob', 'peer-cara']);
      expect(created.resolvedRecipients, hasLength(2));

      final envelopeJson = jsonDecode(created.envelope) as Map<String, dynamic>;
      final payload = envelopeJson['payload'] as Map<String, dynamic>;
      expect(payload['repost_total_baseline'], 0);
      expect(payload['participant_peer_ids'], <String>[
        'peer-alice',
        'peer-bob',
        'peer-cara',
      ]);
    },
  );

  test(
    'runner-backed repost delivery encrypts repost payloads per recipient and carries the shared-thread baseline contract',
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

      final receivedByBob = bobService.messageStream.first;
      final receivedByCara = caraService.messageStream.first;

      final (createResult, created) = await createLocalPostPass(
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

      expect(createResult, PassPostAlongResult.success);
      expect(created, isNotNull);

      final (deliveryResult, deliveredPass) =
          await PostDeliveryRunner(
            p2pService: aliceService,
            postRepo: posts,
            bridge: bridge,
          ).executePostPass(
            pass: created!.pass,
            snapshotPost: created.snapshotPost,
            resolvedRecipients: created.resolvedRecipients,
            allRecipientPeerIds: created.recipientPeerIds,
          );

      expect(deliveryResult, SendPostResult.success);
      expect(deliveredPass.passId, created.pass.passId);
      expect(
        bridge.commandLog.where((command) => command == 'message.encrypt'),
        hasLength(2),
      );

      final bobMessage = await receivedByBob.timeout(
        const Duration(seconds: 1),
      );
      final caraMessage = await receivedByCara.timeout(
        const Duration(seconds: 1),
      );

      final json = jsonDecode(bobMessage.content) as Map<String, dynamic>;
      final payload = _decodeEncryptedPassPayload(json);
      final snapshot = payload['original_snapshot'] as Map<String, dynamic>;
      final media = (snapshot['media'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(json['type'], 'post_pass');
      expect(json['version'], '2');
      expect(json.containsKey('encrypted'), isTrue);
      expect(payload['participant_peer_ids'], <String>[
        'peer-alice',
        'peer-bob',
        'peer-cara',
      ]);
      expect(payload['heart_baseline'], <String, Object?>{
        'active_peer_ids': const <String>[],
      });
      expect(payload['repost_total_baseline'], 0);
      expect(media.single['blob_id'], 'blob-original-1');
      expect(
        _encryptRecipientKeys(bridge.sentMessages),
        unorderedEquals(<String>['mlkem-peer-bob', 'mlkem-peer-cara']),
      );
      expect(
        jsonDecode(caraMessage.content),
        equals(jsonDecode(bobMessage.content)),
      );
    },
  );

  test(
    'createLocalPostPass persists a local pass and queued recipient deliveries before background delivery starts',
    () async {
      await posts.savePost(_directPost());

      final (result, created) = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.success);
      expect(created, isNotNull);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);

      final localPasses = await posts.loadPostPasses('post-1');
      expect(localPasses, hasLength(1));
      expect(created!.pass.passId, localPasses.single.passId);
      expect(localPasses.single.deliveryStatus, 'sending');
      final deliveries = await posts.getPostPassRecipientDeliveries(
        created.pass.passId,
      );
      expect(deliveries.map((delivery) => delivery.recipientPeerId), <String>[
        'peer-bob',
        'peer-cara',
      ]);
      expect(
        deliveries.map((delivery) => delivery.deliveryStatus),
        everyElement('pending'),
      );
      expect(
        deliveries.map((delivery) => delivery.deliveryOwnerKind),
        everyElement(postRecipientDeliveryOwnerKindPass),
      );
      expect(
        deliveries.map((delivery) => delivery.deliveryOwnerId),
        everyElement(created.pass.passId),
      );
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    },
  );

  test(
    'createLocalPostPass persists recipient_count from the explicit audience and excludes the original-author notification copy',
    () async {
      await posts.savePost(_directPost());

      final (result, created) = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
      );

      expect(result, PassPostAlongResult.success);
      expect(created, isNotNull);
      expect(created!.pass.recipientCount, 1);

      final localPasses = await posts.loadPostPasses('post-1');
      final storedPass = localPasses.singleWhere(
        (pass) => pass.passId == created.pass.passId,
      );
      final envelopeJson = jsonDecode(created.envelope) as Map<String, dynamic>;
      final payload = envelopeJson['payload'] as Map<String, dynamic>;
      final deliveries = await posts.getPostPassRecipientDeliveries(
        created.pass.passId,
      );

      expect(storedPass.recipientCount, 1);
      expect(payload['recipient_count'], 1);
      expect(payload['shared_to_count_baseline'], 0);
      expect(deliveries.map((delivery) => delivery.recipientPeerId), <String>[
        'peer-bob',
        'peer-cara',
      ]);
    },
  );

  test(
    'createLocalPostPass persists shared-thread participant, heart, and repost baselines before background delivery starts',
    () async {
      await posts.savePost(_directPost());
      await _seedExistingRepostThreadState(posts);

      final (result, created) = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.success);
      expect(created, isNotNull);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
      await _expectPersistedSharedThreadState(
        posts,
        innerPayloadJson: created!.pass.innerPayloadJson!,
        expectedParticipantPeerIds: const <String>[
          'peer-alice',
          'peer-bob',
          'peer-cara',
          'peer-zoya',
        ],
      );
    },
  );

  test(
    'persists a local pass and shared recipient deliveries before delivery completes',
    () async {
      await posts.savePost(_directPost());
      network.deliveryDelay = const Duration(milliseconds: 150);

      final sendFuture = passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final localPasses = await posts.loadPostPasses('post-1');
      expect(localPasses, hasLength(1));
      expect(localPasses.single.deliveryStatus, 'sending');
      final deliveries = await posts.getPostPassRecipientDeliveries(
        localPasses.single.passId,
      );
      expect(deliveries.map((delivery) => delivery.recipientPeerId), <String>[
        'peer-bob',
        'peer-cara',
      ]);
      expect(
        deliveries.map((delivery) => delivery.deliveryStatus),
        everyElement('pending'),
      );
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);

      final (result, pass) = await sendFuture;
      expect(result, PassPostAlongResult.success);
      expect(pass?.passId, localPasses.single.passId);
    },
  );

  test(
    'passPostAlong persists shared-thread participant, heart, and repost baselines before delivery settles',
    () async {
      await posts.savePost(_directPost());
      await _seedExistingRepostThreadState(posts);
      network.deliveryDelay = const Duration(milliseconds: 150);

      final sendFuture = passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final localPasses = await posts.loadPostPasses('post-1');
      expect(localPasses, hasLength(2));
      final pendingPass = localPasses.firstWhere(
        (pass) =>
            pass.innerPayloadJson != null && pass.innerPayloadJson!.isNotEmpty,
      );
      await _expectPersistedSharedThreadState(
        posts,
        innerPayloadJson: pendingPass.innerPayloadJson!,
        expectedParticipantPeerIds: const <String>[
          'peer-alice',
          'peer-bob',
          'peer-cara',
          'peer-zoya',
        ],
      );

      final (result, pass) = await sendFuture;
      expect(result, PassPostAlongResult.success);
      expect(pass?.passId, pendingPass.passId);
    },
  );

  test(
    'does not create a duplicate delivery target when the sender explicitly selects the original author',
    () async {
      await posts.savePost(_directPost());

      final receivedByBob = bobService.messageStream.first;
      final receivedByCara = caraService.messageStream.first;

      final (result, pass) = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
      );

      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);
      expect(network.deliverCallCount, 2);

      final deliveries = await posts.getPostPassRecipientDeliveries(
        pass!.passId,
      );
      expect(deliveries.map((delivery) => delivery.recipientPeerId), <String>[
        'peer-bob',
        'peer-cara',
      ]);
      expect(
        deliveries.where((delivery) => delivery.recipientPeerId == 'peer-bob'),
        hasLength(1),
      );
      expect(
        deliveries.where((delivery) => delivery.recipientPeerId == 'peer-cara'),
        hasLength(1),
      );

      await receivedByBob.timeout(const Duration(seconds: 1));
      await receivedByCara.timeout(const Duration(seconds: 1));
    },
  );

  test(
    'passPostAlong uses the post delivery runner default concurrency cap of 25',
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

      final sendFuture = passPostAlong(
        p2pService: service,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        senderUsername: 'Bob',
        recipientPeerIds: recipientPeerIds,
      );

      await service
          .waitForSendCount(25)
          .timeout(const Duration(milliseconds: 200));
      await _drainMicrotasks();

      expect(service.maxInFlightSends, 25);
      expect(service.sendStartOrder, recipientPeerIds.take(25).toList());

      sendGates[recipientPeerIds.first]!.complete();
      await service
          .waitForSendCount(26)
          .timeout(const Duration(milliseconds: 200));
      await _drainMicrotasks();

      expect(service.maxInFlightSends, 25);
      expect(service.sendStartOrder, recipientPeerIds.take(26).toList());

      for (final gate in sendGates.values) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }

      final (result, pass) = await sendFuture;
      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);
      expect(service.maxInFlightSends, 25);
    },
  );

  test(
    'deliverCreatedLocalPostPass keeps the local pass and queued recipient deliveries when every delivery path fails',
    () async {
      await posts.savePost(_directPost());
      bobService.setOnline(false);
      caraService.setOnline(false);
      network.inboxDisabled = true;

      final (createResult, created) = await createLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(createResult, PassPostAlongResult.success);
      expect(created, isNotNull);

      final deliveryResult = await deliverCreatedLocalPostPass(
        p2pService: aliceService,
        postRepo: posts,
        created: created!,
        bridge: bridge,
      );

      expect(deliveryResult.$1, SendPostResult.sendFailed);
      final localPasses = await posts.loadPostPasses('post-1');
      expect(localPasses, hasLength(1));
      expect(localPasses.single.deliveryStatus, 'failed');

      final deliveries = await posts.getPostPassRecipientDeliveries(
        created.pass.passId,
      );
      expect(deliveries.map((delivery) => delivery.recipientPeerId), <String>[
        'peer-bob',
        'peer-cara',
      ]);
      expect(deliveries.map((delivery) => delivery.deliveryStatus), <String>[
        'failed',
        'failed',
      ]);

      final retryablePasses = await posts.loadRetryableOutgoingPostPasses();
      expect(retryablePasses, hasLength(1));
      expect(retryablePasses.single.passId, created.pass.passId);
    },
  );

  test(
    'keeps a local pass and retryable recipient-delivery state when the author notification is unresolved',
    () async {
      await posts.savePost(_directPost());
      bobService.setOnline(false);
      network.inboxDisabled = true;

      final (result, pass) = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        bridge: bridge,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.partiallySettled);
      expect(pass, isNotNull);
      expect(await posts.loadPostPasses('post-1'), hasLength(1));

      final deliveries = await posts.getPostPassRecipientDeliveries(
        pass!.passId,
      );
      expect(deliveries.map((delivery) => delivery.recipientPeerId), <String>[
        'peer-bob',
        'peer-cara',
      ]);
      expect(deliveries.map((delivery) => delivery.deliveryStatus), <String>[
        'failed',
        'delivered',
      ]);

      final retryablePasses = await posts.loadRetryableOutgoingPostPasses();
      expect(retryablePasses, hasLength(1));
      expect(retryablePasses.single.passId, pass.passId);
      expect(retryablePasses.single.deliveryStatus, 'partial');
      expect(
        deliveries
            .where(
              (delivery) =>
                  delivery.deliveryStatus != 'delivered' &&
                  delivery.deliveryStatus != 'inbox',
            )
            .map((delivery) => delivery.recipientPeerId),
        <String>['peer-bob'],
      );
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    },
  );

  test(
    'rejects a non-renderable snapshot before persisting a local pass or recipient-delivery state',
    () async {
      await posts.savePost(_directPost(mediaKind: 'image'));

      final (result, pass) = await passPostAlong(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );

      expect(result, PassPostAlongResult.sendFailed);
      expect(pass, isNull);
      expect(await posts.loadPostPasses('post-1'), isEmpty);
      expect(await posts.loadRetryableOutgoingPostPasses(), isEmpty);
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    },
  );

  test('blocks pass-along for pick-people posts', () async {
    await posts.savePost(
      _directPost(
        audience: PostAudience.pickPeople(const <String>['peer-alice']),
      ),
    );

    final (result, pass) = await passPostAlong(
      p2pService: aliceService,
      postRepo: posts,
      contactRepo: contacts,
      postId: 'post-1',
      senderPeerId: 'peer-alice',
      senderUsername: 'Alice',
      recipientPeerIds: const <String>['peer-cara'],
    );

    expect(result, PassPostAlongResult.pickPeopleNotAllowed);
    expect(pass, isNull);
  });

  test('enforces the explicit one-hop rule for already-passed posts', () async {
    await posts.savePost(_directPost(senderPeerId: 'peer-james'));

    final (result, pass) = await passPostAlong(
      p2pService: aliceService,
      postRepo: posts,
      contactRepo: contacts,
      postId: 'post-1',
      senderPeerId: 'peer-alice',
      senderUsername: 'Alice',
      recipientPeerIds: const <String>['peer-cara'],
    );

    expect(result, PassPostAlongResult.oneHopLimitReached);
    expect(pass, isNull);
  });
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

Map<String, dynamic> _decodeEncryptedPassPayload(Map<String, dynamic> json) {
  final encrypted = json['encrypted'] as Map<String, dynamic>;
  return jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
}

Map<String, dynamic> _decodeEncryptedOriginalSnapshot(
  Map<String, dynamic> json,
) {
  final payload = _decodeEncryptedPassPayload(json);
  return payload['original_snapshot'] as Map<String, dynamic>;
}

List<String> _encryptRecipientKeys(List<String> sentMessages) {
  return sentMessages
      .map((message) => jsonDecode(message) as Map<String, dynamic>)
      .where((message) => message['cmd'] == 'message.encrypt')
      .map(
        (message) =>
            (message['payload'] as Map<String, dynamic>)['recipientPublicKey']
                as String,
      )
      .toList(growable: false);
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

Future<void> _drainMicrotasks([int turns = 3]) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
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

Future<void> _expectPersistedSharedThreadState(
  InMemoryPostRepository posts, {
  required String innerPayloadJson,
  required List<String> expectedParticipantPeerIds,
}) async {
  final payload = jsonDecode(innerPayloadJson) as Map<String, dynamic>;
  final heartBaseline = payload['heart_baseline'] as Map<String, dynamic>;

  expect(
    await posts.loadRepostEngagementParticipantPeerIds('post-1'),
    expectedParticipantPeerIds.toSet(),
  );
  expect(await posts.loadRepostHeartBaselinePeerIds('post-1'), <String>{
    'peer-zoya',
  });
  expect(await posts.loadRepostTotalBaseline('post-1'), 2);
  expect(
    (payload['participant_peer_ids'] as List<dynamic>).cast<String>(),
    expectedParticipantPeerIds,
  );
  expect(
    (heartBaseline['active_peer_ids'] as List<dynamic>).cast<String>(),
    <String>['peer-zoya'],
  );
  expect(payload['repost_total_baseline'], 3);
}

Uint8List _validButOversizedAvatarBytes() {
  final builder = BytesBuilder(copy: false)
    ..add(_avatarSnapshotBytes())
    ..add(Uint8List(70000));
  return builder.toBytes();
}

Uint8List _avatarSnapshotBytes() {
  return Uint8List.fromList(const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x62,
    0x00,
    0x00,
    0x00,
    0x02,
    0x00,
    0x01,
    0xE5,
    0x27,
    0xDE,
    0xFC,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
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

List<Map<String, dynamic>> _flowEventDetails(
  List<Map<String, dynamic>> events,
  String eventName,
) {
  return events
      .where((event) => event['event'] == eventName)
      .map((event) => event['details'] as Map<String, dynamic>)
      .toList(growable: false);
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
  final bool requireDiscoverAndDialBeforeSend;

  const _PeerPolicy({
    this.sendGate,
    this.requireDiscoverAndDialBeforeSend = false,
  });
}
