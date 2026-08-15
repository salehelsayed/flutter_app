import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String kGroupMediaBlobArtifactRootDirectory =
    'group_media_blob_custody_v1';

typedef GroupMediaBlobDocumentsDirectoryProvider = Future<Directory> Function();

final RegExp _artifactSha256 = RegExp(r'^[0-9a-f]{64}$');
const String _artifactExtension = '.blob';

final class GroupMediaBlobArtifact {
  const GroupMediaBlobArtifact({
    required this.relativePath,
    required this.absolutePath,
    required this.contentHash,
    required this.ciphertextSize,
  });

  final String relativePath;
  final String absolutePath;
  final String contentHash;
  final int ciphertextSize;
}

final class GroupMediaBlobArtifactCleanupResult {
  const GroupMediaBlobArtifactCleanupResult({
    required this.scanned,
    required this.deleted,
    required this.retained,
  });

  final int scanned;
  final int deleted;
  final int retained;
}

/// Owns immutable group ciphertext independently from direct-media custody.
///
/// One candidate may be referenced by several physical-recipient custody rows.
/// Callers therefore remove it only after the lane-qualified database reference
/// count reaches zero.
final class GroupMediaBlobArtifactStore {
  GroupMediaBlobArtifactStore({
    GroupMediaBlobDocumentsDirectoryProvider? documentsDirectoryProvider,
  }) : _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  final GroupMediaBlobDocumentsDirectoryProvider _documentsDirectoryProvider;

  String identityScope(String identityPeerId) =>
      _sha256Scope(identityPeerId, 'identity');

  String groupScope(String groupId) => _sha256Scope(groupId, 'group');

  String relativeRootForGroup({
    required String identityPeerId,
    required String groupId,
  }) => p.posix.join(
    kGroupMediaBlobArtifactRootDirectory,
    identityScope(identityPeerId),
    groupScope(groupId),
  );

  Future<String> absoluteRootForGroup({
    required String identityPeerId,
    required String groupId,
  }) async {
    final documents = await _documentsDirectoryProvider();
    final documentsPath = p.normalize(documents.path);
    final root = p.normalize(
      p.joinAll(<String>[
        documentsPath,
        ...p.posix.split(
          relativeRootForGroup(
            identityPeerId: identityPeerId,
            groupId: groupId,
          ),
        ),
      ]),
    );
    if (!p.isWithin(documentsPath, root)) {
      throw const FileSystemException('unsafe group custody artifact root');
    }
    return root;
  }

  Future<GroupMediaBlobArtifact> persistCandidate({
    required String identityPeerId,
    required String groupId,
    required String attachmentId,
    required String encryptedSourcePath,
    required String expectedContentHash,
  }) async {
    _requireTrimmed(attachmentId, 'attachment');
    if (!_artifactSha256.hasMatch(expectedContentHash)) {
      throw const FormatException('invalid group custody content hash');
    }
    final source = File(encryptedSourcePath);
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException(
        'group ciphertext source is not a regular file',
      );
    }
    final sourceSize = await source.length();
    if (sourceSize <= 0 || await _sha256File(source) != expectedContentHash) {
      throw const FileSystemException('group ciphertext proof mismatch');
    }

    final rootPath = await absoluteRootForGroup(
      identityPeerId: identityPeerId,
      groupId: groupId,
    );
    final rootType = await FileSystemEntity.type(rootPath, followLinks: false);
    if (rootType == FileSystemEntityType.link ||
        (rootType != FileSystemEntityType.directory &&
            rootType != FileSystemEntityType.notFound)) {
      throw const FileSystemException('unsafe group custody artifact root');
    }
    if (rootType == FileSystemEntityType.notFound) {
      await Directory(rootPath).create(recursive: true);
    }
    if (await FileSystemEntity.type(rootPath, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('unsafe group custody artifact root');
    }

    final attachmentScope = sha256
        .convert(utf8.encode(attachmentId))
        .toString();
    final generation = sha256
        .convert(
          utf8.encode(
            'mknoon.group-media-blob-artifact.v1\u0000'
            '$groupId\u0000$attachmentId\u0000$expectedContentHash',
          ),
        )
        .toString();
    final fileName = '$attachmentScope-$generation$_artifactExtension';
    final finalPath = p.normalize(p.join(rootPath, fileName));
    final tempPath = '$finalPath.tmp';
    if (!p.isWithin(rootPath, finalPath) || !p.isWithin(rootPath, tempPath)) {
      throw const FileSystemException('unsafe group custody candidate');
    }

    final temp = File(tempPath);
    final finalFile = File(finalPath);
    final relativePath = p.posix.join(
      relativeRootForGroup(identityPeerId: identityPeerId, groupId: groupId),
      fileName,
    );
    var publishedByThisCall = false;
    try {
      if (await FileSystemEntity.type(finalPath, followLinks: false) ==
          FileSystemEntityType.file) {
        final existing = await verifyOwnedArtifact(
          identityPeerId: identityPeerId,
          groupId: groupId,
          relativePath: relativePath,
          expectedContentHash: expectedContentHash,
          expectedCiphertextSize: sourceSize,
        );
        if (existing == null) {
          throw const FileSystemException(
            'crossed deterministic group custody artifact',
          );
        }
        return existing;
      }
      // A prior process may have stopped between flush and rename. Only the
      // exact deterministic temp owned by this artifact is reconciled here.
      await _deleteIfRegularFile(temp);
      await temp.create(exclusive: true);
      final sink = await temp.open(mode: FileMode.writeOnly);
      try {
        await for (final chunk in source.openRead()) {
          await sink.writeFrom(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      await temp.rename(finalPath);
      publishedByThisCall = true;
      final persisted = await verifyOwnedArtifact(
        identityPeerId: identityPeerId,
        groupId: groupId,
        relativePath: relativePath,
        expectedContentHash: expectedContentHash,
        expectedCiphertextSize: sourceSize,
      );
      if (persisted == null) {
        throw const FileSystemException(
          'group custody artifact verification failed',
        );
      }
      return persisted;
    } catch (_) {
      await _deleteIfRegularFile(temp);
      if (publishedByThisCall) await _deleteIfRegularFile(finalFile);
      rethrow;
    }
  }

  Future<GroupMediaBlobArtifact?> verifyOwnedArtifact({
    required String identityPeerId,
    required String groupId,
    required String relativePath,
    required String expectedContentHash,
    required int expectedCiphertextSize,
  }) async {
    if (!_artifactSha256.hasMatch(expectedContentHash) ||
        expectedCiphertextSize <= 0) {
      return null;
    }
    final absolutePath = await resolveOwnedArtifactPath(
      identityPeerId: identityPeerId,
      groupId: groupId,
      relativePath: relativePath,
    );
    if (absolutePath == null ||
        await FileSystemEntity.type(absolutePath, followLinks: false) !=
            FileSystemEntityType.file) {
      return null;
    }
    final file = File(absolutePath);
    if (await file.length() != expectedCiphertextSize ||
        await _sha256File(file) != expectedContentHash) {
      return null;
    }
    return GroupMediaBlobArtifact(
      relativePath: relativePath,
      absolutePath: absolutePath,
      contentHash: expectedContentHash,
      ciphertextSize: expectedCiphertextSize,
    );
  }

  Future<String?> resolveOwnedArtifactPath({
    required String identityPeerId,
    required String groupId,
    required String relativePath,
  }) async {
    if (relativePath.isEmpty ||
        relativePath.contains(r'\') ||
        p.posix.isAbsolute(relativePath) ||
        p.posix.normalize(relativePath) != relativePath) {
      return null;
    }
    final relativeRoot = relativeRootForGroup(
      identityPeerId: identityPeerId,
      groupId: groupId,
    );
    if (!p.posix.isWithin(relativeRoot, relativePath) ||
        !relativePath.endsWith(_artifactExtension)) {
      return null;
    }
    final documents = await _documentsDirectoryProvider();
    final documentsPath = p.normalize(documents.path);
    final absolutePath = p.normalize(
      p.joinAll(<String>[documentsPath, ...p.posix.split(relativePath)]),
    );
    final absoluteRoot = await absoluteRootForGroup(
      identityPeerId: identityPeerId,
      groupId: groupId,
    );
    if (!p.isWithin(absoluteRoot, absolutePath) ||
        !p.isWithin(documentsPath, absolutePath) ||
        await FileSystemEntity.type(absoluteRoot, followLinks: false) !=
            FileSystemEntityType.directory) {
      return null;
    }
    return absolutePath;
  }

  Future<bool> deleteOwnedArtifact({
    required String identityPeerId,
    required String groupId,
    required String relativePath,
  }) async {
    final absolutePath = await resolveOwnedArtifactPath(
      identityPeerId: identityPeerId,
      groupId: groupId,
      relativePath: relativePath,
    );
    if (absolutePath == null) return false;
    final type = await FileSystemEntity.type(absolutePath, followLinks: false);
    if (type == FileSystemEntityType.notFound) return true;
    if (type != FileSystemEntityType.file) return false;
    await File(absolutePath).delete();
    return await FileSystemEntity.type(absolutePath, followLinks: false) ==
        FileSystemEntityType.notFound;
  }

  Future<GroupMediaBlobArtifactCleanupResult> cleanupUnreferencedArtifacts({
    required String identityPeerId,
    required String groupId,
    required Set<String> referencedRelativePaths,
    int limit = 50,
  }) async {
    if (limit <= 0 || limit > 50) {
      throw RangeError.range(limit, 1, 50, 'limit');
    }
    final relativeRoot = relativeRootForGroup(
      identityPeerId: identityPeerId,
      groupId: groupId,
    );
    if (referencedRelativePaths.any(
      (path) =>
          !p.posix.isWithin(relativeRoot, path) ||
          p.posix.normalize(path) != path ||
          !path.endsWith(_artifactExtension),
    )) {
      throw const FormatException(
        'invalid referenced group custody artifact path',
      );
    }
    final absoluteRoot = await absoluteRootForGroup(
      identityPeerId: identityPeerId,
      groupId: groupId,
    );
    final rootType = await FileSystemEntity.type(
      absoluteRoot,
      followLinks: false,
    );
    if (rootType == FileSystemEntityType.notFound) {
      return const GroupMediaBlobArtifactCleanupResult(
        scanned: 0,
        deleted: 0,
        retained: 0,
      );
    }
    if (rootType != FileSystemEntityType.directory) {
      throw const FileSystemException('unsafe group custody artifact root');
    }
    final entities =
        await Directory(absoluteRoot).list(followLinks: false).toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    var scanned = 0;
    var deleted = 0;
    var retained = 0;
    for (final entity in entities) {
      if (scanned >= limit) break;
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file ||
          (!entity.path.endsWith(_artifactExtension) &&
              !entity.path.endsWith('$_artifactExtension.tmp'))) {
        continue;
      }
      scanned++;
      final relative = p.posix.join(relativeRoot, p.basename(entity.path));
      if (referencedRelativePaths.contains(relative)) {
        retained++;
        continue;
      }
      await File(entity.path).delete();
      deleted++;
    }
    return GroupMediaBlobArtifactCleanupResult(
      scanned: scanned,
      deleted: deleted,
      retained: retained,
    );
  }

  /// Bounded identity-wide reconciliation for artifacts left after a process
  /// stopped between the verified rename and the atomic SQL stage.
  ///
  /// [referencedRelativePaths] is the exact group-lane DB inventory. Unknown
  /// files, links, and malformed directory shapes are ignored; only regular
  /// `.blob`/`.blob.tmp` files under this identity's hashed group roots are
  /// eligible for deletion.
  Future<GroupMediaBlobArtifactCleanupResult>
  cleanupUnreferencedArtifactsForIdentity({
    required String identityPeerId,
    required Set<String> referencedRelativePaths,
    int limit = 50,
  }) async {
    if (limit <= 0 || limit > 50) {
      throw RangeError.range(limit, 1, 50, 'limit');
    }
    final identity = identityScope(identityPeerId);
    final relativeIdentityRoot = p.posix.join(
      kGroupMediaBlobArtifactRootDirectory,
      identity,
    );
    final rootParts = p.posix.split(relativeIdentityRoot);
    if (referencedRelativePaths.any((path) {
      final parts = p.posix.split(path);
      return !p.posix.isWithin(relativeIdentityRoot, path) ||
          p.posix.normalize(path) != path ||
          parts.length != rootParts.length + 2 ||
          !_artifactSha256.hasMatch(parts[rootParts.length]) ||
          !path.endsWith(_artifactExtension);
    })) {
      throw const FormatException(
        'invalid referenced group custody artifact inventory',
      );
    }

    final documents = await _documentsDirectoryProvider();
    final documentsPath = p.normalize(documents.path);
    final absoluteIdentityRoot = p.normalize(
      p.joinAll(<String>[
        documentsPath,
        ...p.posix.split(relativeIdentityRoot),
      ]),
    );
    if (!p.isWithin(documentsPath, absoluteIdentityRoot)) {
      throw const FileSystemException('unsafe group custody identity root');
    }
    final identityRootType = await FileSystemEntity.type(
      absoluteIdentityRoot,
      followLinks: false,
    );
    if (identityRootType == FileSystemEntityType.notFound) {
      return const GroupMediaBlobArtifactCleanupResult(
        scanned: 0,
        deleted: 0,
        retained: 0,
      );
    }
    if (identityRootType != FileSystemEntityType.directory) {
      throw const FileSystemException('unsafe group custody identity root');
    }

    final groupRoots =
        await Directory(absoluteIdentityRoot).list(followLinks: false).toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    var scanned = 0;
    var deleted = 0;
    var retained = 0;
    for (final groupRoot in groupRoots) {
      if (scanned >= limit) break;
      final groupType = await FileSystemEntity.type(
        groupRoot.path,
        followLinks: false,
      );
      final groupScopeName = p.basename(groupRoot.path);
      if (groupType != FileSystemEntityType.directory ||
          !_artifactSha256.hasMatch(groupScopeName) ||
          !p.isWithin(absoluteIdentityRoot, groupRoot.path)) {
        continue;
      }
      final artifacts =
          await Directory(groupRoot.path).list(followLinks: false).toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      for (final artifact in artifacts) {
        if (scanned >= limit) break;
        final type = await FileSystemEntity.type(
          artifact.path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.file ||
            (!artifact.path.endsWith(_artifactExtension) &&
                !artifact.path.endsWith('$_artifactExtension.tmp')) ||
            !p.isWithin(groupRoot.path, artifact.path)) {
          continue;
        }
        scanned++;
        final relative = p.posix.join(
          relativeIdentityRoot,
          groupScopeName,
          p.basename(artifact.path),
        );
        if (referencedRelativePaths.contains(relative)) {
          retained++;
          continue;
        }
        await File(artifact.path).delete();
        deleted++;
      }
    }
    return GroupMediaBlobArtifactCleanupResult(
      scanned: scanned,
      deleted: deleted,
      retained: retained,
    );
  }
}

String _sha256Scope(String value, String label) {
  _requireTrimmed(value, label);
  return sha256.convert(utf8.encode(value)).toString();
}

void _requireTrimmed(String value, String label) {
  if (value.trim().isEmpty || value != value.trim()) {
    throw FormatException('invalid group custody $label scope');
  }
}

Future<String> _sha256File(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> _deleteIfRegularFile(File file) async {
  try {
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file) {
      await file.delete();
    }
  } catch (_) {}
}
