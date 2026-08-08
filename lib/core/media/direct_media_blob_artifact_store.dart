import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const kDirectMediaBlobArtifactRootDirectory = 'direct_media_blob_custody_v1';

typedef DirectMediaBlobDocumentsDirectoryProvider =
    Future<Directory> Function();

final RegExp _artifactSha256 = RegExp(r'^[0-9a-f]{64}$');
const _artifactExtension = '.blob';

final class DirectMediaBlobArtifact {
  const DirectMediaBlobArtifact({
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

final class DirectMediaBlobArtifactCleanupResult {
  const DirectMediaBlobArtifactCleanupResult({
    required this.scanned,
    required this.deleted,
    required this.retained,
  });

  final int scanned;
  final int deleted;
  final int retained;
}

/// Owns immutable outgoing ciphertext files independently from render media.
///
/// Candidate paths are unique, so concurrent preparers can publish one DB
/// winner without ever overwriting or deleting another preparer's file.
final class DirectMediaBlobArtifactStore {
  DirectMediaBlobArtifactStore({
    DirectMediaBlobDocumentsDirectoryProvider? documentsDirectoryProvider,
    Uuid uuid = const Uuid(),
  }) : _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
       _uuid = uuid;

  final DirectMediaBlobDocumentsDirectoryProvider _documentsDirectoryProvider;
  final Uuid _uuid;

  String identityScope(String identityPeerId) {
    final normalized = identityPeerId.trim();
    if (normalized.isEmpty || normalized != identityPeerId) {
      throw const FormatException('invalid custody identity scope');
    }
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  String relativeRootForIdentity(String identityPeerId) => p.posix.join(
    kDirectMediaBlobArtifactRootDirectory,
    identityScope(identityPeerId),
  );

  Future<String> absoluteRootForIdentity(String identityPeerId) async {
    final documents = await _documentsDirectoryProvider();
    final documentsPath = p.normalize(documents.path);
    final root = p.normalize(
      p.join(
        documentsPath,
        kDirectMediaBlobArtifactRootDirectory,
        identityScope(identityPeerId),
      ),
    );
    if (!p.isWithin(documentsPath, root)) {
      throw const FileSystemException('unsafe custody artifact root');
    }
    return root;
  }

  Future<DirectMediaBlobArtifact> persistCandidate({
    required String identityPeerId,
    required String attachmentId,
    required String encryptedSourcePath,
    required String expectedContentHash,
  }) async {
    if (attachmentId.trim().isEmpty || attachmentId != attachmentId.trim()) {
      throw const FormatException('invalid custody attachment id');
    }
    if (!_artifactSha256.hasMatch(expectedContentHash)) {
      throw const FormatException('invalid custody content hash');
    }
    final source = File(encryptedSourcePath);
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException('ciphertext source is not a regular file');
    }
    final sourceSize = await source.length();
    if (sourceSize <= 0) {
      throw const FileSystemException('ciphertext source is empty');
    }
    final sourceHash = await _sha256File(source);
    if (sourceHash != expectedContentHash) {
      throw const FileSystemException('ciphertext source hash mismatch');
    }

    final rootPath = await absoluteRootForIdentity(identityPeerId);
    final root = Directory(rootPath);
    final rootType = await FileSystemEntity.type(rootPath, followLinks: false);
    if (rootType == FileSystemEntityType.link ||
        (rootType != FileSystemEntityType.directory &&
            rootType != FileSystemEntityType.notFound)) {
      throw const FileSystemException('unsafe custody artifact root');
    }
    if (rootType == FileSystemEntityType.notFound) {
      await root.create(recursive: true);
    }
    if (await FileSystemEntity.type(rootPath, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('unsafe custody artifact root');
    }

    final attachmentScope = sha256
        .convert(utf8.encode(attachmentId))
        .toString();
    final generation = _uuid.v4().replaceAll('-', '');
    final fileName = '$attachmentScope-$generation$_artifactExtension';
    final finalPath = p.normalize(p.join(rootPath, fileName));
    final tempPath = '$finalPath.tmp';
    if (!p.isWithin(rootPath, finalPath) || !p.isWithin(rootPath, tempPath)) {
      throw const FileSystemException('unsafe custody artifact candidate');
    }

    final temp = File(tempPath);
    final finalFile = File(finalPath);
    try {
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
      if (await finalFile.exists()) {
        throw const FileSystemException('custody artifact collision');
      }
      await temp.rename(finalPath);
      final persisted = await verifyOwnedArtifact(
        identityPeerId: identityPeerId,
        relativePath: p.posix.join(
          relativeRootForIdentity(identityPeerId),
          fileName,
        ),
        expectedContentHash: expectedContentHash,
        expectedCiphertextSize: sourceSize,
      );
      if (persisted == null) {
        throw const FileSystemException('custody artifact verification failed');
      }
      return persisted;
    } catch (_) {
      await _deleteIfRegularFile(temp);
      await _deleteIfRegularFile(finalFile);
      rethrow;
    }
  }

  Future<DirectMediaBlobArtifact?> verifyOwnedArtifact({
    required String identityPeerId,
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
    return DirectMediaBlobArtifact(
      relativePath: relativePath,
      absolutePath: absolutePath,
      contentHash: expectedContentHash,
      ciphertextSize: expectedCiphertextSize,
    );
  }

  Future<String?> resolveOwnedArtifactPath({
    required String identityPeerId,
    required String relativePath,
  }) async {
    if (relativePath.isEmpty ||
        relativePath.contains('\\') ||
        p.posix.isAbsolute(relativePath) ||
        p.posix.normalize(relativePath) != relativePath) {
      return null;
    }
    final relativeRoot = relativeRootForIdentity(identityPeerId);
    if (!p.posix.isWithin(relativeRoot, relativePath) ||
        !relativePath.endsWith(_artifactExtension)) {
      return null;
    }
    final documents = await _documentsDirectoryProvider();
    final documentsPath = p.normalize(documents.path);
    final absolutePath = p.normalize(
      p.joinAll(<String>[documentsPath, ...p.posix.split(relativePath)]),
    );
    final absoluteRoot = await absoluteRootForIdentity(identityPeerId);
    if (!p.isWithin(absoluteRoot, absolutePath) ||
        !p.isWithin(documentsPath, absolutePath)) {
      return null;
    }
    final rootType = await FileSystemEntity.type(
      absoluteRoot,
      followLinks: false,
    );
    if (rootType != FileSystemEntityType.directory) return null;
    return absolutePath;
  }

  Future<bool> deleteOwnedArtifact({
    required String identityPeerId,
    required String relativePath,
  }) async {
    final absolutePath = await resolveOwnedArtifactPath(
      identityPeerId: identityPeerId,
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

  /// Removes a bounded page of files that have no v111 authority.
  ///
  /// Callers must hold the shared media-custody lifecycle lock. That is the
  /// file-before-row publication barrier: an active candidate cannot be
  /// mistaken for a crash orphan while this scan runs.
  Future<DirectMediaBlobArtifactCleanupResult> cleanupUnreferencedArtifacts({
    required String identityPeerId,
    required Set<String> referencedRelativePaths,
    int limit = 50,
  }) async {
    if (limit <= 0 || limit > 50) {
      throw RangeError.range(limit, 1, 50, 'limit');
    }
    final relativeRoot = relativeRootForIdentity(identityPeerId);
    if (referencedRelativePaths.any(
      (path) =>
          !p.posix.isWithin(relativeRoot, path) ||
          p.posix.normalize(path) != path ||
          !path.endsWith(_artifactExtension),
    )) {
      throw const FormatException('invalid referenced custody artifact path');
    }
    final absoluteRoot = await absoluteRootForIdentity(identityPeerId);
    final rootType = await FileSystemEntity.type(
      absoluteRoot,
      followLinks: false,
    );
    if (rootType == FileSystemEntityType.notFound) {
      return const DirectMediaBlobArtifactCleanupResult(
        scanned: 0,
        deleted: 0,
        retained: 0,
      );
    }
    if (rootType != FileSystemEntityType.directory) {
      throw const FileSystemException('unsafe custody artifact root');
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
    return DirectMediaBlobArtifactCleanupResult(
      scanned: scanned,
      deleted: deleted,
      retained: retained,
    );
  }
}

Future<String> _sha256File(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

Future<void> _deleteIfRegularFile(File file) async {
  try {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.file) await file.delete();
  } catch (_) {}
}
