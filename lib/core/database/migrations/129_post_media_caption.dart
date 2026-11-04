// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

/// The short caption of a Thought media item (a voice note today), kept on
/// the stored attachment and on its upload recovery row so a retried upload
/// still sends it. Nullable, no default and no backfill.
Future<void> runPostMediaCaptionMigration(Database database) async {
  for (final table in [
    'post_media_attachments',
    'post_media_upload_recovery',
  ]) {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((column) => column['name'] == 'caption')) {
      await database.execute('ALTER TABLE $table ADD COLUMN caption TEXT');
    }
  }
}
