import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> runPostsPassAvatarSnapshotsMigration(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS post_pass_avatar_snapshots (
      post_id TEXT PRIMARY KEY,
      author_peer_id TEXT NOT NULL,
      avatar_blob BLOB NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
}
