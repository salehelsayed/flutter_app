import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/encrypted_media_test_bridge.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

const _createdAt = '2026-06-12T10:00:00.000Z';

void main() {
  late InMemoryPostRepository posts;
  late FakeSecureKeyStore secureKeyStore;
  late ImageProcessor imageProcessor;
  late Directory tempDir;
  late RelayMediaStore relayStore;
  late EncryptedMediaTestBridge bridge;
  late TempPostMediaFileManager mediaFileManager;

  setUp(() async {
    posts = InMemoryPostRepository();
    secureKeyStore = FakeSecureKeyStore();
    // Pass-through "processing" that still produces a distinct temp file, so
    // processed-temp hygiene is observable.
    imageProcessor = ImageProcessor(
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
    );
    tempDir = Directory.systemTemp.createTempSync('attach-post-media-enc-');
    relayStore = RelayMediaStore();
    bridge = EncryptedMediaTestBridge(relayStore);
    mediaFileManager = TempPostMediaFileManager(tempDir.path);

    await posts.savePost(
      const PostModel(
        id: 'post-1',
        eventId: 'evt-post-1',
        senderPeerId: 'peer-self',
        authorPeerId: 'peer-self',
        authorUsername: 'Alice',
        text: 'media post',
        audience: PostAudience(kind: PostAudienceKind.allFriends),
        createdAt: _createdAt,
        visibleAt: _createdAt,
        expiresAt: '2026-06-15T10:00:00.000Z',
        isIncoming: false,
        deliveryStatus: 'sending',
        mediaKind: 'image',
      ),
    );
    await posts.saveRecipientDelivery(
      const PostRecipientDelivery(
        postId: 'post-1',
        recipientPeerId: 'peer-bob',
        deliveryStatus: 'pending',
        lastAttemptAt: _createdAt,
        deliveryPath: 'post_create',
        createdAt: _createdAt,
        updatedAt: _createdAt,
      ),
    );
  });

  tearDown(() {
    // KC-P4/G8 standing pin: the sender never deletes posts relay blobs.
    expect(bridge.commandLog, isNot(contains('media:delete')));
    posts.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Uint8List sourceBytes([int seed = 3]) => Uint8List.fromList(
        List<int>.generate(400, (index) => (index * seed + 7) & 0xff),
      );

  File writeSource(String name, [int seed = 3]) {
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(sourceBytes(seed), flush: true);
    return file;
  }

  List<String> encTempsUnder(Directory dir) => dir
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path)
      .where((path) => path.endsWith('.enc'))
      .toList();

  test(
    'uploadPostMedia uploads ciphertext with the opaque transport mime; returned attachment keeps the real mime and full crypto metadata',
    () async {
      final source = writeSource('photo.jpg');

      final (result, attachments) = await attachPostMedia(
        postId: 'post-1',
        postRepo: posts,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        drafts: <PostMediaDraft>[
          PostMediaDraft(localFilePath: source.path, mime: 'image/jpeg'),
        ],
        mediaFileManager: mediaFileManager,
        bridge: bridge,
      );

      expect(result, AttachPostMediaResult.success);
      final attachment = attachments.single;

      expect(bridge.commandLog, contains('blob:keygen'));
      expect(bridge.commandLog, contains('blob:encrypt'));

      final blobId = relayStore.blobIds.single;
      expect(blobId, attachment.blobId);
      final relayBytes = relayStore.uploadedBytesByBlobId[blobId]!;
      expect(relayBytes, isNot(orderedEquals(sourceBytes())));

      // G7a: opaque mime on the wire, real mime on the model.
      expect(relayStore.mimeByBlobId[blobId], kOpaqueMediaTransportMime);
      expect(attachment.mime, 'image/jpeg');

      expect(attachment.isEncrypted, isTrue);
      expect(attachment.encryptionKeyBase64, isNotNull);
      expect(attachment.encryptionNonce, isNotNull);
      expect(
        attachment.encryptionScheme,
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
      // G6/MIG-012 provenance: hash of the ENCRYPTED artifact, not the source.
      expect(attachment.contentHash, sha256.convert(relayBytes).toString());
      expect(
        attachment.contentHash,
        isNot(sha256.convert(sourceBytes()).toString()),
      );
      // sizeBytes stays the PLAINTEXT size (group + pass convention).
      expect(attachment.sizeBytes, sourceBytes().length);
    },
  );

  test(
    'durable local copy is PLAINTEXT and byte-identical to the uploaded source',
    () async {
      final source = writeSource('photo.jpg');

      final (result, attachments) = await attachPostMedia(
        postId: 'post-1',
        postRepo: posts,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        drafts: <PostMediaDraft>[
          PostMediaDraft(localFilePath: source.path, mime: 'image/jpeg'),
        ],
        mediaFileManager: mediaFileManager,
        bridge: bridge,
      );

      expect(result, AttachPostMediaResult.success);
      final attachment = attachments.single;
      expect(attachment.localPath, isNotNull);
      final durablePath = await mediaFileManager.resolveStoredPath(
        attachment.localPath!,
      );
      final durableBytes = File(durablePath).readAsBytesSync();
      expect(durableBytes, orderedEquals(sourceBytes()));
      expect(
        durableBytes,
        isNot(orderedEquals(relayStore.uploadedBytesByBlobId.values.single)),
      );
      // Real-mime extension preserved on the durable copy.
      expect(durablePath, endsWith('.jpg'));
    },
  );

  test(
    'keygen failure fails closed: no media:upload, attachPostMedia returns uploadFailed',
    () async {
      bridge.failBlobKeygen = true;
      final source = writeSource('photo.jpg');

      final (result, attachments) = await attachPostMedia(
        postId: 'post-1',
        postRepo: posts,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        drafts: <PostMediaDraft>[
          PostMediaDraft(localFilePath: source.path, mime: 'image/jpeg'),
        ],
        mediaFileManager: mediaFileManager,
        bridge: bridge,
      );

      expect(result, AttachPostMediaResult.uploadFailed);
      expect(attachments, isEmpty);
      expect(bridge.commandLog, isNot(contains('media:upload')));
      expect(relayStore.blobIds, isEmpty);
    },
  );

  test(
    'encrypt failure fails closed: no media:upload, attachPostMedia returns uploadFailed',
    () async {
      bridge.failBlobEncrypt = true;
      final source = writeSource('photo.jpg');

      final (result, attachments) = await attachPostMedia(
        postId: 'post-1',
        postRepo: posts,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        drafts: <PostMediaDraft>[
          PostMediaDraft(localFilePath: source.path, mime: 'image/jpeg'),
        ],
        mediaFileManager: mediaFileManager,
        bridge: bridge,
      );

      expect(result, AttachPostMediaResult.uploadFailed);
      expect(attachments, isEmpty);
      expect(bridge.commandLog, isNot(contains('media:upload')));
    },
  );

  test('.enc temp deleted in finally on success AND on upload failure',
      () async {
    final source = writeSource('photo.jpg');

    final (result, _) = await attachPostMedia(
      postId: 'post-1',
      postRepo: posts,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      drafts: <PostMediaDraft>[
        PostMediaDraft(localFilePath: source.path, mime: 'image/jpeg'),
      ],
      mediaFileManager: mediaFileManager,
      bridge: bridge,
    );
    expect(result, AttachPostMediaResult.success);
    // RED-coupling rule: absence-of-temp is only meaningful if the encrypt
    // step actually ran in the same scenario.
    expect(bridge.commandLog, contains('blob:encrypt'));
    expect(encTempsUnder(tempDir), isEmpty);

    bridge.failMediaUpload = true;
    final failedSource = writeSource('photo2.jpg', 5);
    final (failedResult, _) = await attachPostMedia(
      postId: 'post-1',
      postRepo: posts,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      drafts: <PostMediaDraft>[
        PostMediaDraft(localFilePath: failedSource.path, mime: 'image/jpeg'),
      ],
      mediaFileManager: mediaFileManager,
      bridge: bridge,
    );
    expect(failedResult, AttachPostMediaResult.uploadFailed);
    expect(
      bridge.commandLog.where((command) => command == 'blob:encrypt'),
      hasLength(2),
    );
    expect(encTempsUnder(tempDir), isEmpty);
  });

  test(
    'processed plaintext temp deleted after successful upload; voice source passes through untouched',
    () async {
      final source = writeSource('photo.jpg');

      final (result, _) = await attachPostMedia(
        postId: 'post-1',
        postRepo: posts,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        drafts: <PostMediaDraft>[
          PostMediaDraft(localFilePath: source.path, mime: 'image/jpeg'),
        ],
        mediaFileManager: mediaFileManager,
        bridge: bridge,
      );

      expect(result, AttachPostMediaResult.success);
      expect(File('${source.path}_processed').existsSync(), isFalse,
          reason: 'the processed plaintext temp must be deleted post-upload');
      expect(source.existsSync(), isTrue,
          reason: 'the draft source is the recovery-replay re-upload source '
              'and must survive attachPostMedia');

      // Voice passes through _prepareDraft unchanged: processedPath ==
      // source, so the processed-temp delete guard must not remove it.
      final voiceSource = writeSource('clip.m4a', 9);
      final (voiceResult, voiceAttachments) = await attachPostMedia(
        postId: 'post-1',
        postRepo: posts,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        drafts: <PostMediaDraft>[
          PostMediaDraft(
            localFilePath: voiceSource.path,
            mime: 'audio/mp4',
            durationMs: 2100,
            waveform: const <double>[0.1, 0.9, 0.4],
          ),
        ],
        mediaFileManager: mediaFileManager,
        bridge: bridge,
      );
      expect(voiceResult, AttachPostMediaResult.success);
      expect(voiceSource.existsSync(), isTrue);
      expect(voiceAttachments.single.isEncrypted, isTrue);
      expect(voiceAttachments.single.waveform, isNotNull);
    },
  );

  test('distinct key, nonce, and blobId per attachment', () async {
    final first = writeSource('one.jpg', 3);
    final second = writeSource('two.jpg', 11);

    final (result, attachments) = await attachPostMedia(
      postId: 'post-1',
      postRepo: posts,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      drafts: <PostMediaDraft>[
        PostMediaDraft(localFilePath: first.path, mime: 'image/jpeg'),
        PostMediaDraft(localFilePath: second.path, mime: 'image/jpeg'),
      ],
      mediaFileManager: mediaFileManager,
      bridge: bridge,
    );

    expect(result, AttachPostMediaResult.success);
    expect(attachments, hasLength(2));
    expect(
      attachments[0].blobId,
      isNot(attachments[1].blobId),
    );
    expect(
      attachments[0].encryptionKeyBase64,
      isNot(attachments[1].encryptionKeyBase64),
    );
    expect(
      attachments[0].encryptionNonce,
      isNot(attachments[1].encryptionNonce),
    );
  });

  test('allowedPeers ACL unchanged: author + recipient delivery peers',
      () async {
    final source = writeSource('photo.jpg');

    final (result, attachments) = await attachPostMedia(
      postId: 'post-1',
      postRepo: posts,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      drafts: <PostMediaDraft>[
        PostMediaDraft(localFilePath: source.path, mime: 'image/jpeg'),
      ],
      mediaFileManager: mediaFileManager,
      bridge: bridge,
    );

    expect(result, AttachPostMediaResult.success);
    expect(
      relayStore.allowedPeersByBlobId[attachments.single.blobId],
      unorderedEquals(<String>['peer-self', 'peer-bob']),
    );
  });
}
