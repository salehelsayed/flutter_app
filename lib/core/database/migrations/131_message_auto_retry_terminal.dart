// ignore_for_file: file_names
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Local retry policy only; historical rows retain their existing eligibility.
Future<void> runMessageAutoRetryTerminalMigration(Database database) async {
  final columns = await database.rawQuery('PRAGMA table_info(messages)');
  if (!columns.any(
    (column) => column['name'] == 'auto_retry_terminal_reason',
  )) {
    await database.execute(
      'ALTER TABLE messages ADD COLUMN auto_retry_terminal_reason TEXT',
    );
  }
}
