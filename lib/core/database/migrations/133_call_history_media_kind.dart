// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '117_call_history.dart';

Future<void> runCallHistoryMediaKindMigration(Database database) async {
  final columns = await database.rawQuery(
    'PRAGMA table_info($kCallHistoryTable)',
  );
  if (columns.any((column) => column['name'] == 'media_kind')) return;

  await database.execute(
    'ALTER TABLE $kCallHistoryTable ADD COLUMN media_kind TEXT '
    "CHECK (media_kind IN ('audio', 'video'))",
  );
}
