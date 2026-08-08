import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory documents;
  late DirectMediaBlobArtifactStore store;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp(
      'direct-media-blob-artifact-store-',
    );
    store = DirectMediaBlobArtifactStore(
      documentsDirectoryProvider: () async => documents,
    );
  });

  tearDown(() async {
    if (await documents.exists()) {
      await documents.delete(recursive: true);
    }
  });

  test(
    'TC-347-02 durable ciphertext candidate is immutable and identity scoped',
    () async {
      final bytes = List<int>.generate(97, (index) => (index * 7) & 0xff);
      final source = File('${documents.path}/source.enc');
      await source.writeAsBytes(bytes, flush: true);
      final contentHash = sha256.convert(bytes).toString();

      final first = await store.persistCandidate(
        identityPeerId: 'sender-peer',
        attachmentId: 'attachment-347',
        encryptedSourcePath: source.path,
        expectedContentHash: contentHash,
      );
      final second = await store.persistCandidate(
        identityPeerId: 'sender-peer',
        attachmentId: 'attachment-347',
        encryptedSourcePath: source.path,
        expectedContentHash: contentHash,
      );

      expect(first.relativePath, isNot(second.relativePath));
      expect(await File(first.absolutePath).readAsBytes(), bytes);
      expect(first.ciphertextSize, bytes.length);
      expect(
        await store.verifyOwnedArtifact(
          identityPeerId: 'sender-peer',
          relativePath: first.relativePath,
          expectedContentHash: contentHash,
          expectedCiphertextSize: bytes.length,
        ),
        isNotNull,
      );
      expect(
        await store.verifyOwnedArtifact(
          identityPeerId: 'other-peer',
          relativePath: first.relativePath,
          expectedContentHash: contentHash,
          expectedCiphertextSize: bytes.length,
        ),
        isNull,
      );
      expect(
        await store.resolveOwnedArtifactPath(
          identityPeerId: 'sender-peer',
          relativePath: '../${first.relativePath}',
        ),
        isNull,
      );
      expect(
        await store.resolveOwnedArtifactPath(
          identityPeerId: 'sender-peer',
          relativePath: first.absolutePath,
        ),
        isNull,
      );

      expect(
        await store.deleteOwnedArtifact(
          identityPeerId: 'sender-peer',
          relativePath: first.relativePath,
        ),
        isTrue,
      );
      expect(await File(first.absolutePath).exists(), isFalse);
      expect(await File(second.absolutePath).exists(), isTrue);
    },
  );

  test(
    'TC-347-02 artifact publication fails closed on hash mismatch',
    () async {
      final source = File('${documents.path}/source.enc');
      await source.writeAsBytes(<int>[1, 2, 3, 4], flush: true);

      await expectLater(
        store.persistCandidate(
          identityPeerId: 'sender-peer',
          attachmentId: 'attachment-347',
          encryptedSourcePath: source.path,
          expectedContentHash: 'a' * 64,
        ),
        throwsA(isA<FileSystemException>()),
      );
      final custodyRoot = Directory(
        '${documents.path}/$kDirectMediaBlobArtifactRootDirectory',
      );
      expect(await custodyRoot.exists(), isFalse);
    },
  );

  test(
    'TC-347-07 cleanup reaps only unreferenced identity-scoped artifacts',
    () async {
      final source = File('${documents.path}/source.enc');
      final bytes = List<int>.generate(41, (index) => index);
      await source.writeAsBytes(bytes, flush: true);
      final contentHash = sha256.convert(bytes).toString();
      final retained = await store.persistCandidate(
        identityPeerId: 'sender-peer',
        attachmentId: 'retained-attachment',
        encryptedSourcePath: source.path,
        expectedContentHash: contentHash,
      );
      final orphan = await store.persistCandidate(
        identityPeerId: 'sender-peer',
        attachmentId: 'orphan-attachment',
        encryptedSourcePath: source.path,
        expectedContentHash: contentHash,
      );
      final otherIdentity = await store.persistCandidate(
        identityPeerId: 'other-peer',
        attachmentId: 'other-attachment',
        encryptedSourcePath: source.path,
        expectedContentHash: contentHash,
      );

      final result = await store.cleanupUnreferencedArtifacts(
        identityPeerId: 'sender-peer',
        referencedRelativePaths: <String>{retained.relativePath},
      );

      expect(result.scanned, 2);
      expect(result.retained, 1);
      expect(result.deleted, 1);
      expect(await File(retained.absolutePath).exists(), isTrue);
      expect(await File(orphan.absolutePath).exists(), isFalse);
      expect(await File(otherIdentity.absolutePath).exists(), isTrue);
      await expectLater(
        store.cleanupUnreferencedArtifacts(
          identityPeerId: 'sender-peer',
          referencedRelativePaths: <String>{otherIdentity.relativePath},
        ),
        throwsFormatException,
      );
    },
  );
}
