import 'dart:io';

import 'package:path/path.dart' as p;

/// Removes the owned support-directory claims after account work is retired.
Future<void> eraseAccountNotificationClaims({
  required Directory supportDirectory,
}) async {
  final claims = Directory(
    p.join(supportDirectory.path, 'ReactionNotificationClaims'),
  );
  if (await FileSystemEntity.type(claims.path, followLinks: false) ==
      FileSystemEntityType.notFound) {
    return;
  }
  await claims.delete(recursive: true);
  if (await FileSystemEntity.type(claims.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw FileSystemException(
      'Account notification claims erasure incomplete',
      claims.path,
    );
  }
}
