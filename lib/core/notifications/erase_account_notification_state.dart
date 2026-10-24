import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Removes owned notification files after account work is retired.
///
/// Call for application support and, on iOS, the shared notification container.
/// Containers and unrelated configuration (including the App Group path) survive.
/// An unavailable shared container is logged and skipped.
Future<void> eraseAccountNotificationState({
  required Directory? directory,
}) async {
  if (directory == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_NOTIFICATION_ERASE_SKIPPED',
      details: {'reason': 'shared_container_unavailable'},
    );
    return;
  }
  for (final name in const [
    'ReactionNotificationClaims',
    'NotificationConversationIds',
    'PendingConversationNotificationOverlay',
    'NotificationServiceDedupe',
    'NotificationToneLeases',
    'RecentRemoteShown',
    'mknoon_recent_remote_notifications.json.aliases',
  ]) {
    await _deleteAndReadBack(Directory(p.join(directory.path, name)));
  }
  for (final name in const [
    'mknoon_recent_remote_notifications.json',
    'mknoon_recent_remote_notifications.json.account',
    '.NotificationServiceDedupe.lock',
  ]) {
    await _deleteAndReadBack(File(p.join(directory.path, name)));
  }
}

Future<void> _deleteAndReadBack(FileSystemEntity entry) async {
  if (await FileSystemEntity.type(entry.path, followLinks: false) ==
      FileSystemEntityType.notFound) {
    return;
  }
  await entry.delete(recursive: true);
  if (await FileSystemEntity.type(entry.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw FileSystemException(
      'Account notification state erasure incomplete',
      entry.path,
    );
  }
}
