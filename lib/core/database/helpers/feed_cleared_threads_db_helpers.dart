import 'package:sqflite_sqlcipher/sqflite.dart';

/// Free-function DB helpers for the `feed_cleared_threads` table (migration
/// 092). These take the `Database` as the first argument so the feed-cleared
/// repository can inject them as closures (the repo never references a
/// `Database` directly — mirrors `post_privacy_state_db_helpers.dart`).

/// Upsert a cleared watermark. Replaces any existing row for the same
/// `(threadKind, threadId)` PK so re-clearing simply advances the watermark.
Future<void> dbMarkFeedClearedThread(
  Database db,
  String threadKind,
  String threadId,
  int clearedAtMs,
) async {
  await db.insert(
    'feed_cleared_threads',
    <String, Object?>{
      'thread_kind': threadKind,
      'thread_id': threadId,
      'cleared_at_ms': clearedAtMs,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

/// Remove a cleared watermark (Undo of a prior dismiss/commit).
Future<void> dbClearFeedClearedThread(
  Database db,
  String threadKind,
  String threadId,
) async {
  await db.delete(
    'feed_cleared_threads',
    where: 'thread_kind = ? AND thread_id = ?',
    whereArgs: <Object?>[threadKind, threadId],
  );
}

/// Load every cleared watermark row.
Future<List<Map<String, Object?>>> dbLoadFeedClearedThreads(Database db) async {
  return db.query('feed_cleared_threads');
}
