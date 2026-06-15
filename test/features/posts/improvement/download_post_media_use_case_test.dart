import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/posts/application/download_post_media_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';

import '../../../shared/fakes/encrypted_media_test_bridge.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

const _createdAt = '2026-06-12T10:00:00.000Z';

void main() {
  late Directory tempDir;
  late TempPostMediaFileManager mediaFileManager;
  late RelayMediaStore relayStore;
  late EncryptedMediaTestBridge bridge;
  late InMemoryPostRepository posts;

  final plaintext = Uint8List.fromList(
    List<int>.generate(300, (index) => (index * 31) & 0xff),
  );
  final key = deriveTestBlobKey(7);
  final nonce = deriveTestBlobNonce(7);
  final ciphertext = xorWithKeyAndNonce(plaintext, key, nonce);
  final ciphertextHash = sha256.convert(ciphertext).toString();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('download-post-media-');
    mediaFileManager = TempPostMediaFileManager(tempDir.path);
    relayStore = RelayMediaStore();
    bridge = EncryptedMediaTestBridge(relayStore);
    posts = InMemoryPostRepository();
    relayStore.uploadedBytesByBlobId['blob-enc-1'] = ciphertext;
    relayStore.mimeByBlobId['blob-enc-1'] = kOpaqueMediaTransportMime;
    relayStore.uploadedBytesByBlobId['blob-plain-1'] = plaintext;
    relayStore.mimeByBlobId['blob-plain-1'] = 'image/jpeg';
  });

  tearDown(() {
    // KC-P4/G8: posts media must NEVER delete the shared multi-recipient
    // relay blob — asserted across every case in this suite.
    expect(bridge.commandLog, isNot(contains('media:delete')));
    posts.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  PostMediaAttachmentModel attachment({
    String blobId = 'blob-enc-1',
    String? keyBase64,
    String? nonceBase64,
    String? scheme,
    String? contentHash,
    bool isEncrypted = true,
  }) {
    return PostMediaAttachmentModel(
      mediaId: 'media-1',
      postId: 'post-1',
      blobId: blobId,
      kind: 'image',
      mime: 'image/jpeg',
      sizeBytes: plaintext.length,
      createdAt: _createdAt,
      downloadStatus: 'pending',
      encryptionKeyBase64: keyBase64,
      encryptionNonce: nonceBase64,
      encryptionScheme: scheme,
      contentHash: contentHash,
      isEncrypted: isEncrypted,
    );
  }

  Future<String> finalPathFor(String blobId) {
    return mediaFileManager.localPathForPostAttachment(
      postId: 'post-1',
      blobId: blobId,
      mime: 'image/jpeg',
    );
  }

  test(
    'isEncrypted with null key or nonce fails closed: status failed, no localPath, no done',
    () async {
      final row = attachment(keyBase64: null, nonceBase64: null);
      await posts.savePostMediaAttachment(row);

      await expectLater(
        downloadPostMedia(
          bridge: bridge,
          postRepo: posts,
          mediaFileManager: mediaFileManager,
          attachment: row,
        ),
        throwsA(isA<StateError>()),
      );

      final stored = (await posts.loadPostMediaAttachments('post-1')).single;
      expect(stored.downloadStatus, 'failed');
      expect(stored.localPath, isNull);
      expect(bridge.commandLog, isNot(contains('blob:decrypt')));
      final finalPath = await finalPathFor('blob-enc-1');
      expect(File(finalPath).existsSync(), isFalse);
      expect(File('$finalPath.enc').existsSync(), isFalse);
    },
  );

  test('decrypt failure deletes the .enc staging file and marks failed',
      () async {
    bridge.failBlobDecrypt = true;
    final row = attachment(
      keyBase64: base64Encode(key),
      nonceBase64: base64Encode(nonce),
      scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      contentHash: ciphertextHash,
    );
    await posts.savePostMediaAttachment(row);

    await expectLater(
      downloadPostMedia(
        bridge: bridge,
        postRepo: posts,
        mediaFileManager: mediaFileManager,
        attachment: row,
      ),
      throwsA(isA<StateError>()),
    );

    expect(bridge.commandLog, contains('blob:decrypt'));
    final stored = (await posts.loadPostMediaAttachments('post-1')).single;
    expect(stored.downloadStatus, 'failed');
    final finalPath = await finalPathFor('blob-enc-1');
    expect(File('$finalPath.enc').existsSync(), isFalse,
        reason: 'the .enc staging file must not be orphaned');
    expect(File(finalPath).existsSync(), isFalse);
  });

  test('unknown encryption scheme fails closed without calling blob:decrypt',
      () async {
    final row = attachment(
      keyBase64: base64Encode(key),
      nonceBase64: base64Encode(nonce),
      scheme: 'blob_future_scheme_v9',
      contentHash: ciphertextHash,
    );
    await posts.savePostMediaAttachment(row);

    await expectLater(
      downloadPostMedia(
        bridge: bridge,
        postRepo: posts,
        mediaFileManager: mediaFileManager,
        attachment: row,
      ),
      throwsA(isA<StateError>()),
    );

    expect(bridge.commandLog, isNot(contains('blob:decrypt')));
    final stored = (await posts.loadPostMediaAttachments('post-1')).single;
    expect(stored.downloadStatus, 'failed');
    final finalPath = await finalPathFor('blob-enc-1');
    expect(File('$finalPath.enc').existsSync(), isFalse);
    expect(File(finalPath).existsSync(), isFalse);
  });

  test('content_hash mismatch on downloaded ciphertext fails before decrypt',
      () async {
    final row = attachment(
      keyBase64: base64Encode(key),
      nonceBase64: base64Encode(nonce),
      scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      contentHash: sha256.convert(utf8.encode('not the ciphertext')).toString(),
    );
    await posts.savePostMediaAttachment(row);

    await expectLater(
      downloadPostMedia(
        bridge: bridge,
        postRepo: posts,
        mediaFileManager: mediaFileManager,
        attachment: row,
      ),
      throwsA(isA<StateError>()),
    );

    expect(bridge.commandLog, contains('media:download'));
    expect(bridge.commandLog, isNot(contains('blob:decrypt')));
    final stored = (await posts.loadPostMediaAttachments('post-1')).single;
    expect(stored.downloadStatus, 'failed');
    final finalPath = await finalPathFor('blob-enc-1');
    expect(File('$finalPath.enc').existsSync(), isFalse);
  });

  test(
    'content_hash match decrypts; null content_hash tolerated (legacy pass rows)',
    () async {
      final verified = attachment(
        keyBase64: base64Encode(key),
        nonceBase64: base64Encode(nonce),
        scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        contentHash: ciphertextHash,
      );
      await posts.savePostMediaAttachment(verified);

      final hydrated = await downloadPostMedia(
        bridge: bridge,
        postRepo: posts,
        mediaFileManager: mediaFileManager,
        attachment: verified,
      );
      expect(hydrated.downloadStatus, 'done');

      // Legacy pass row: key+nonce, no scheme, no hash — still decrypts.
      posts.dispose();
      posts = InMemoryPostRepository();
      final legacy = attachment(
        keyBase64: base64Encode(key),
        nonceBase64: base64Encode(nonce),
      );
      await posts.savePostMediaAttachment(legacy);

      final legacyHydrated = await downloadPostMedia(
        bridge: bridge,
        postRepo: posts,
        mediaFileManager: mediaFileManager,
        attachment: legacy,
      );
      expect(legacyHydrated.downloadStatus, 'done');

      final finalPath = await finalPathFor('blob-enc-1');
      expect(File(finalPath).readAsBytesSync(), orderedEquals(plaintext));
    },
  );

  test('encrypted blob decrypts, renames .dec to final, deletes .enc',
      () async {
    final row = attachment(
      keyBase64: base64Encode(key),
      nonceBase64: base64Encode(nonce),
      scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      contentHash: ciphertextHash,
    );
    await posts.savePostMediaAttachment(row);

    final hydrated = await downloadPostMedia(
      bridge: bridge,
      postRepo: posts,
      mediaFileManager: mediaFileManager,
      attachment: row,
    );

    expect(hydrated.downloadStatus, 'done');
    expect(hydrated.localPath, 'post_media/post-1/blob-enc-1.jpg');

    final finalPath = await finalPathFor('blob-enc-1');
    expect(File(finalPath).readAsBytesSync(), orderedEquals(plaintext));
    expect(File('$finalPath.enc').existsSync(), isFalse);
    expect(File('$finalPath.enc.dec').existsSync(), isFalse);

    final stored = (await posts.loadPostMediaAttachments('post-1')).single;
    expect(stored.downloadStatus, 'done');
    expect(stored.localPath, 'post_media/post-1/blob-enc-1.jpg');
  });

  test(
    'plaintext legacy attachment downloads directly to the final path, no blob:decrypt',
    () async {
      final row = attachment(
        blobId: 'blob-plain-1',
        keyBase64: null,
        nonceBase64: null,
        isEncrypted: false,
      );
      await posts.savePostMediaAttachment(row);

      final hydrated = await downloadPostMedia(
        bridge: bridge,
        postRepo: posts,
        mediaFileManager: mediaFileManager,
        attachment: row,
      );

      expect(hydrated.downloadStatus, 'done');
      expect(bridge.commandLog, isNot(contains('blob:decrypt')));

      final finalPath = await finalPathFor('blob-plain-1');
      expect(File(finalPath).readAsBytesSync(), orderedEquals(plaintext));
      expect(File('$finalPath.enc').existsSync(), isFalse);
    },
  );
}
