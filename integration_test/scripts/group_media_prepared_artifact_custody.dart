import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Returns a deterministic digest of every member of a prepared directory.
///
/// Links are attested as links and are never followed. This binds iOS code,
/// Flutter assets, test products, plists, signatures, and empty directories
/// instead of relying on a hand-maintained subset of important files.
String groupMediaPreparedDirectorySha256(Directory suppliedRoot) {
  if (FileSystemEntity.typeSync(suppliedRoot.path, followLinks: true) !=
      FileSystemEntityType.directory) {
    throw const FileSystemException(
      'Prepared artifact custody root is not a directory.',
    );
  }
  final root = Directory(suppliedRoot.resolveSymbolicLinksSync()).absolute;
  final prefix = root.path.endsWith(Platform.pathSeparator)
      ? root.path
      : '${root.path}${Platform.pathSeparator}';
  final entries = <Map<String, Object?>>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    final absolutePath = entity.absolute.path;
    if (!absolutePath.startsWith(prefix)) {
      throw const FileSystemException(
        'Prepared artifact member escaped its custody root.',
      );
    }
    final relativePath = absolutePath.substring(prefix.length);
    if (relativePath.isEmpty) {
      throw const FileSystemException(
        'Prepared artifact member has no relative path.',
      );
    }
    final type = FileSystemEntity.typeSync(absolutePath, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        entries.add(<String, Object?>{
          'path': relativePath,
          'type': 'directory',
        });
      case FileSystemEntityType.file:
        final bytes = File(absolutePath).readAsBytesSync();
        entries.add(<String, Object?>{
          'path': relativePath,
          'type': 'file',
          'length': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        });
      case FileSystemEntityType.link:
        final link = Link(absolutePath);
        final target = link.targetSync();
        _validatePreparedArtifactLink(
          rootPath: root.path,
          linkPath: absolutePath,
          target: target,
        );
        entries.add(<String, Object?>{
          'path': relativePath,
          'type': 'link',
          'target': target,
        });
      default:
        throw const FileSystemException(
          'Prepared artifact contains an unsupported member type.',
        );
    }
  }
  entries.sort((left, right) {
    final pathOrder = (left['path']! as String).compareTo(
      right['path']! as String,
    );
    if (pathOrder != 0) return pathOrder;
    return (left['type']! as String).compareTo(right['type']! as String);
  });
  final canonical = jsonEncode(<String, Object?>{
    'schema': 'mknoon.group-media-prepared-directory-custody.v1',
    'entries': entries,
  });
  return sha256.convert(utf8.encode(canonical)).toString();
}

void _validatePreparedArtifactLink({
  required String rootPath,
  required String linkPath,
  required String target,
}) {
  final targetPath = _containedRelativeLinkTarget(
    rootPath: rootPath,
    linkPath: linkPath,
    target: target,
  );
  _validatePreparedArtifactLinkChain(
    rootPath: rootPath,
    requestedPath: targetPath,
    activeLinks: <String>{p.normalize(linkPath)},
  );
}

void _validatePreparedArtifactLinkChain({
  required String rootPath,
  required String requestedPath,
  required Set<String> activeLinks,
}) {
  _requirePreparedArtifactPathContained(rootPath, requestedPath);
  final relative = p.relative(requestedPath, from: rootPath);
  if (relative == '.') return;

  var current = rootPath;
  final components = p.split(relative);
  for (var index = 0; index < components.length; index += 1) {
    current = p.normalize(p.join(current, components[index]));
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Prepared artifact contains a dangling link chain.',
        current,
      );
    }
    if (type != FileSystemEntityType.link) continue;
    if (!activeLinks.add(current)) {
      throw FileSystemException(
        'Prepared artifact contains a cyclic link chain.',
        current,
      );
    }
    final target = Link(current).targetSync();
    final next = _containedRelativeLinkTarget(
      rootPath: rootPath,
      linkPath: current,
      target: target,
    );
    final remaining = components.skip(index + 1).toList(growable: false);
    final continued = remaining.isEmpty
        ? next
        : p.normalize(p.joinAll(<String>[next, ...remaining]));
    _validatePreparedArtifactLinkChain(
      rootPath: rootPath,
      requestedPath: continued,
      activeLinks: activeLinks,
    );
    activeLinks.remove(current);
    return;
  }
}

String _containedRelativeLinkTarget({
  required String rootPath,
  required String linkPath,
  required String target,
}) {
  if (target.isEmpty ||
      p.isAbsolute(target) ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(target) ||
      target.startsWith(r'\\')) {
    throw FileSystemException(
      'Prepared artifact contains an absolute link target.',
      linkPath,
    );
  }

  final parent = p.dirname(linkPath);
  final parentRelative = p.relative(parent, from: rootPath);
  var depth = parentRelative == '.' ? 0 : p.split(parentRelative).length;
  for (final component in p.split(target)) {
    if (component == '.' || component.isEmpty) continue;
    if (component == '..') {
      depth -= 1;
      if (depth < 0) {
        throw FileSystemException(
          'Prepared artifact link target escapes its custody root.',
          linkPath,
        );
      }
    } else {
      depth += 1;
    }
  }

  final resolved = p.normalize(p.join(parent, target));
  _requirePreparedArtifactPathContained(rootPath, resolved);
  return resolved;
}

void _requirePreparedArtifactPathContained(String rootPath, String candidate) {
  final normalizedRoot = p.normalize(rootPath);
  final normalizedCandidate = p.normalize(candidate);
  if (p.equals(normalizedRoot, normalizedCandidate) ||
      p.isWithin(normalizedRoot, normalizedCandidate)) {
    return;
  }
  throw FileSystemException(
    'Prepared artifact link chain escapes its custody root.',
    candidate,
  );
}
