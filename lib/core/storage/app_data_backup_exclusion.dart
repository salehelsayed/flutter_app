import 'dart:io';

import 'package:flutter_app/core/notifications/app_group_path_channel.dart';
import 'package:flutter_app/core/storage/exclude_from_backup.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps message data out of iCloud backups (owner, 11-01).
///
/// iOS applies a folder's exclusion to everything inside it, including files
/// created later, so marking two roots covers identity.db and the files
/// SQLite recreates beside it, all media, drafts and the migration bundle
/// (Documents), and what the notification and share extensions write (the
/// App Group container). It runs on every launch because a restore or an OS
/// reset can clear the mark; a refused mark is reported without any path or
/// content and never blocks the app.
Future<void> excludeAppDataFromBackup({
  bool? isIOS,
  Future<String?> Function()? documentsPath,
  Future<String?> Function()? appGroupPath,
  Future<bool> Function(String path)? exclude,
  void Function(String root)? reportRefused,
}) async {
  if (!(isIOS ?? Platform.isIOS)) return;
  final roots = <String, Future<String?> Function()>{
    'documents':
        documentsPath ??
        () async => (await getApplicationDocumentsDirectory()).path,
    'app_group': appGroupPath ?? AppGroupPathChannel().containerPath,
  };
  for (final MapEntry(key: root, value: resolve) in roots.entries) {
    var excluded = false;
    try {
      final path = await resolve();
      if (path == null) continue;
      excluded = await (exclude ?? excludeDirectoryFromBackup)(path);
    } on Object {
      excluded = false;
    }
    if (!excluded) (reportRefused ?? _reportRefused)(root);
  }
}

void _reportRefused(String root) => emitFlowEvent(
  layer: 'storage',
  event: 'BACKUP_EXCLUSION_REFUSED',
  details: {'root': root},
);
