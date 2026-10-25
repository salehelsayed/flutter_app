// ignore_for_file: file_names
import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> runAuthoredDirectTextIntentsMigration(Database db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS authored_direct_text_intents (
    id TEXT PRIMARY KEY NOT NULL,
    contact_peer_id TEXT NOT NULL,
    text TEXT NOT NULL CHECK(length(text) > 0),
    quoted_message_id TEXT,
    timestamp TEXT NOT NULL,
    token TEXT NOT NULL UNIQUE
  )''');
}
