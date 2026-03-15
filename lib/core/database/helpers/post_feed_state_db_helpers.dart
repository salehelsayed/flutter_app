import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> dbMarkPostFocused(Database db, String postId) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.update('posts', <String, Object?>{'is_focused': 0});
  await db.update(
    'posts',
    <String, Object?>{'is_focused': 1},
    where: 'post_id = ?',
    whereArgs: <Object?>[postId],
  );
  await db.insert('post_feed_state', <String, Object?>{
    'post_id': postId,
    'is_hidden': 0,
    'last_focused_at': now,
    'is_read': 1,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
