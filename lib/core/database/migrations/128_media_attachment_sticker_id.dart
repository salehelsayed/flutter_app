// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

/// Stickers v1: the pack-list id of a sticker attachment. Nullable, no default
/// and no backfill: every other row and every existing row keeps NULL.
Future<void> runMediaAttachmentStickerIdMigration(Database database) async {
  final columns = await database.rawQuery(
    'PRAGMA table_info(media_attachments)',
  );
  if (!columns.any((column) => column['name'] == 'sticker_id')) {
    await database.execute(
      'ALTER TABLE media_attachments ADD COLUMN sticker_id TEXT',
    );
  }
}
