import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/media/group_media_blob_artifact_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDirectory;
  late GroupMediaBlobArtifactStore store;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'group_media_blob_artifact_store_',
    );
    store = GroupMediaBlobArtifactStore(
      documentsDirectoryProvider: () async => tempDirectory,
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('deterministic group artifact staging adopts only exact bytes and '
      'cleans only unreferenced files', () async {
    const identityPeerId = 'identity-peer';
    const groupId = 'group-id';
    const attachmentId = 'attachment-id';
    final bytes = utf8.encode('deterministic encrypted group media bytes');
    final contentHash = sha256.convert(bytes).toString();
    final sourceA = File('${tempDirectory.path}/source-a.enc');
    final sourceB = File('${tempDirectory.path}/source-b.enc');
    await sourceA.writeAsBytes(bytes, flush: true);
    await sourceB.writeAsBytes(bytes, flush: true);

    final first = await store.persistCandidate(
      identityPeerId: identityPeerId,
      groupId: groupId,
      attachmentId: attachmentId,
      encryptedSourcePath: sourceA.path,
      expectedContentHash: contentHash,
    );
    final replay = await store.persistCandidate(
      identityPeerId: identityPeerId,
      groupId: groupId,
      attachmentId: attachmentId,
      encryptedSourcePath: sourceB.path,
      expectedContentHash: contentHash,
    );
    expect(replay.relativePath, first.relativePath);
    expect(replay.absolutePath, first.absolutePath);
    expect(
      first.relativePath,
      startsWith('$kGroupMediaBlobArtifactRootDirectory/'),
    );
    expect(first.relativePath, isNot(startsWith('direct_media_blob_custody')));
    expect(await File(first.absolutePath).readAsBytes(), bytes);

    final retained = await store.cleanupUnreferencedArtifacts(
      identityPeerId: identityPeerId,
      groupId: groupId,
      referencedRelativePaths: <String>{first.relativePath},
    );
    expect(retained.retained, 1);
    expect(File(first.absolutePath).existsSync(), isTrue);

    // A crossed deterministic final is refused without deleting the crossed
    // evidence. The candidate can be reconciled only after exact readback.
    await File(first.absolutePath).writeAsString('crossed', flush: true);
    await expectLater(
      store.persistCandidate(
        identityPeerId: identityPeerId,
        groupId: groupId,
        attachmentId: attachmentId,
        encryptedSourcePath: sourceA.path,
        expectedContentHash: contentHash,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(first.absolutePath).existsSync(), isTrue);

    final deleted = await store.cleanupUnreferencedArtifacts(
      identityPeerId: identityPeerId,
      groupId: groupId,
      referencedRelativePaths: const <String>{},
    );
    expect(deleted.deleted, 1);
    expect(File(first.absolutePath).existsSync(), isFalse);
    expect(
      await store.resolveOwnedArtifactPath(
        identityPeerId: identityPeerId,
        groupId: groupId,
        relativePath: 'direct_media_blob_custody_v1/a/b.blob',
      ),
      isNull,
    );
  });

  test(
    'TC-365-02b identity cleanup retains exact references and deletes group artifacts',
    () async {
      const identityPeerId = 'identity-peer';
      final bytes = utf8.encode('identity-wide group custody artifact');
      final contentHash = sha256.convert(bytes).toString();
      final source = File('${tempDirectory.path}/identity-cleanup.enc');
      await source.writeAsBytes(bytes, flush: true);

      final retained = await store.persistCandidate(
        identityPeerId: identityPeerId,
        groupId: 'retained-group',
        attachmentId: 'retained-attachment',
        encryptedSourcePath: source.path,
        expectedContentHash: contentHash,
      );
      final orphan = await store.persistCandidate(
        identityPeerId: identityPeerId,
        groupId: 'orphan-group',
        attachmentId: 'orphan-attachment',
        encryptedSourcePath: source.path,
        expectedContentHash: contentHash,
      );
      final orphanRoot = await store.absoluteRootForGroup(
        identityPeerId: identityPeerId,
        groupId: 'orphan-group',
      );
      final interruptedPublish = File('$orphanRoot/interrupted.blob.tmp');
      await interruptedPublish.writeAsBytes(<int>[1, 2, 3], flush: true);

      final result = await store.cleanupUnreferencedArtifactsForIdentity(
        identityPeerId: identityPeerId,
        referencedRelativePaths: <String>{retained.relativePath},
      );

      expect(result.scanned, 3);
      expect(result.retained, 1);
      expect(result.deleted, 2);
      expect(await File(retained.absolutePath).exists(), isTrue);
      expect(await File(orphan.absolutePath).exists(), isFalse);
      expect(await interruptedPublish.exists(), isFalse);
    },
  );

  test(
    'TC-365-02b identity cleanup bounds regular blob and temp deletion',
    () async {
      final root = Directory(
        await store.absoluteRootForGroup(
          identityPeerId: 'bounded-identity',
          groupId: 'bounded-group',
        ),
      );
      await root.create(recursive: true);
      final first = File('${root.path}/00.blob');
      final second = File('${root.path}/01.blob.tmp');
      final third = File('${root.path}/02.blob');
      await first.writeAsBytes(<int>[1], flush: true);
      await second.writeAsBytes(<int>[2], flush: true);
      await third.writeAsBytes(<int>[3], flush: true);

      final result = await store.cleanupUnreferencedArtifactsForIdentity(
        identityPeerId: 'bounded-identity',
        referencedRelativePaths: const <String>{},
        limit: 2,
      );

      expect(result.scanned, 2);
      expect(result.deleted, 2);
      expect(result.retained, 0);
      expect(await first.exists(), isFalse);
      expect(await second.exists(), isFalse);
      expect(await third.exists(), isTrue);
    },
  );

  test(
    'TC-365-02b identity cleanup ignores links malformed roots and non-artifacts',
    () async {
      const identityPeerId = 'guarded-identity';
      final validGroupRoot = Directory(
        await store.absoluteRootForGroup(
          identityPeerId: identityPeerId,
          groupId: 'guarded-group',
        ),
      );
      await validGroupRoot.create(recursive: true);
      final eligible = File('${validGroupRoot.path}/eligible.blob');
      final nonArtifact = File('${validGroupRoot.path}/notes.txt');
      final nestedArtifact = File('${validGroupRoot.path}/nested/ignored.blob');
      final symlinkTarget = File('${tempDirectory.path}/link-target.blob');
      final symlink = Link('${validGroupRoot.path}/linked.blob');
      await eligible.writeAsBytes(<int>[1], flush: true);
      await nonArtifact.writeAsBytes(<int>[2], flush: true);
      await nestedArtifact.parent.create(recursive: true);
      await nestedArtifact.writeAsBytes(<int>[3], flush: true);
      await symlinkTarget.writeAsBytes(<int>[4], flush: true);
      await symlink.create(symlinkTarget.path);

      final identityRoot = Directory(
        '${tempDirectory.path}/$kGroupMediaBlobArtifactRootDirectory/'
        '${store.identityScope(identityPeerId)}',
      );
      final malformedGroupArtifact = File(
        '${identityRoot.path}/not-a-group-hash/ignored.blob',
      );
      final wrongDepthArtifact = File('${identityRoot.path}/ignored.blob');
      await malformedGroupArtifact.parent.create(recursive: true);
      await malformedGroupArtifact.writeAsBytes(<int>[5], flush: true);
      await wrongDepthArtifact.writeAsBytes(<int>[6], flush: true);

      final result = await store.cleanupUnreferencedArtifactsForIdentity(
        identityPeerId: identityPeerId,
        referencedRelativePaths: const <String>{},
      );

      expect(result.scanned, 1);
      expect(result.deleted, 1);
      expect(await eligible.exists(), isFalse);
      expect(await nonArtifact.exists(), isTrue);
      expect(await nestedArtifact.exists(), isTrue);
      expect(
        await FileSystemEntity.type(symlink.path, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(await symlinkTarget.exists(), isTrue);
      expect(await malformedGroupArtifact.exists(), isTrue);
      expect(await wrongDepthArtifact.exists(), isTrue);
    },
  );

  test(
    'TC-365-02b identity cleanup rejects malformed or foreign reference inventories',
    () async {
      const identityPeerId = 'validated-identity';
      const groupId = 'validated-group';
      final bytes = utf8.encode('inventory validation artifact');
      final source = File('${tempDirectory.path}/inventory-validation.enc');
      await source.writeAsBytes(bytes, flush: true);
      final artifact = await store.persistCandidate(
        identityPeerId: identityPeerId,
        groupId: groupId,
        attachmentId: 'validated-attachment',
        encryptedSourcePath: source.path,
        expectedContentHash: sha256.convert(bytes).toString(),
      );
      final relativeRoot = store.relativeRootForGroup(
        identityPeerId: identityPeerId,
        groupId: groupId,
      );
      final invalidInventories = <Set<String>>[
        <String>{
          '${store.relativeRootForGroup(identityPeerId: 'foreign-identity', groupId: groupId)}/foreign.blob',
        },
        <String>{artifact.absolutePath},
        <String>{
          '$kGroupMediaBlobArtifactRootDirectory/'
              '${store.identityScope(identityPeerId)}/not-a-sha/artifact.blob',
        },
        <String>{'$relativeRoot/nested/artifact.blob'},
        <String>{'$relativeRoot/interrupted.blob.tmp'},
      ];

      for (final invalidInventory in invalidInventories) {
        await expectLater(
          store.cleanupUnreferencedArtifactsForIdentity(
            identityPeerId: identityPeerId,
            referencedRelativePaths: invalidInventory,
          ),
          throwsFormatException,
        );
        expect(await File(artifact.absolutePath).exists(), isTrue);
      }
    },
  );
}
