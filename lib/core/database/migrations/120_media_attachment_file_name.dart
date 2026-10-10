// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

/// 414: display name of a document attachment (PDF). Nullable, no default and
/// no backfill: image/video/audio rows and every existing row keep NULL.
Future<void> runMediaAttachmentFileNameMigration(Database database) async {
  final columns = await database.rawQuery(
    'PRAGMA table_info(media_attachments)',
  );
  if (!columns.any((column) => column['name'] == 'file_name')) {
    await database.execute(
      'ALTER TABLE media_attachments ADD COLUMN file_name TEXT',
    );
  }
}
