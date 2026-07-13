import 'dart:io';

import 'package:path/path.dart' as p;

/// Canonical identifier and filesystem containment authority shared by every
/// direct-private path consumer. Validation is read-only and must run before
/// transfer, promotion, adoption, or destructive cleanup.
class DirectPrivateMediaPathGuard {
  const DirectPrivateMediaPathGuard._();

  static bool isSafeSegment(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value) &&
      value != '.' &&
      value != '..';

  static bool identifiersAreSafe({
    required String contactPeerId,
    required String messageId,
    required String attachmentId,
  }) =>
      isSafeSegment(contactPeerId) &&
      isSafeSegment(messageId) &&
      isSafeSegment(attachmentId);

  /// Authorizes [targetPath] beneath [authorityRoot] without following any
  /// symlink component. Missing leaf paths are safe only when
  /// [requireExistingFile] is false; all existing ancestors are still
  /// inspected so a symlinked contact/message directory fails closed.
  static Future<bool> authorizeTarget({
    required String targetPath,
    required String authorityRoot,
    bool requireExistingFile = false,
  }) async {
    final target = p.normalize(targetPath);
    final root = p.normalize(authorityRoot);
    if (!p.isAbsolute(target) ||
        !p.isAbsolute(root) ||
        !p.isWithin(root, target)) {
      return false;
    }

    final rootType = await FileSystemEntity.type(root, followLinks: false);
    if (rootType == FileSystemEntityType.link ||
        (rootType != FileSystemEntityType.directory &&
            rootType != FileSystemEntityType.notFound)) {
      return false;
    }
    if (rootType == FileSystemEntityType.notFound) {
      return !requireExistingFile;
    }

    final relative = p.relative(target, from: root);
    var current = root;
    final parts = p.split(relative);
    for (var index = 0; index < parts.length; index += 1) {
      current = p.join(current, parts[index]);
      final type = await FileSystemEntity.type(current, followLinks: false);
      final isLeaf = index == parts.length - 1;
      if (type == FileSystemEntityType.link) return false;
      if (type == FileSystemEntityType.notFound) {
        return !requireExistingFile;
      }
      if (!isLeaf && type != FileSystemEntityType.directory) return false;
      if (isLeaf && type != FileSystemEntityType.file) return false;
    }

    try {
      final realRoot = p.normalize(
        await Directory(root).resolveSymbolicLinks(),
      );
      final realTarget = p.normalize(await File(target).resolveSymbolicLinks());
      return p.isWithin(realRoot, realTarget);
    } catch (_) {
      return false;
    }
  }
}
