// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 092: feed-only `feed_cleared_threads` table for the pending-reply
/// inbox redesign (134, decision 2).
///
/// A "cleared" row hides a thread from the Feed (the self-emptying inbox)
/// WITHOUT mutating read-state, the unread badge, the Orbit badge, or archive
/// (INV-2 dismiss isolation). Commit (swipe-right) writes a cleared row AND
/// marks the conversation read; dismiss (swipe-left) writes only the cleared
/// row. A thread re-surfaces when a newer incoming message arrives with a
/// timestamp strictly greater than `cleared_at_ms`.
///
/// Schema: `(thread_kind, thread_id, cleared_at_ms)` with a composite primary
/// key `(thread_kind, thread_id)`:
///   - `thread_kind` ∈ {'contact','group','connection'}
///   - `thread_id`   = peerId / groupId / contactPeerId
///   - `cleared_at_ms` = the epoch-ms watermark (connection letters use
///     presence — a row exists → drop — rather than a timestamp compare).
///
/// `CREATE TABLE IF NOT EXISTS` makes the migration intrinsically idempotent,
/// so a re-run (or an upgrade landing on an already-created table) is a no-op
/// that preserves existing rows.
Future<void> runFeedClearedThreadsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'FEED_CLEARED_THREADS_MIGRATION_START',
    details: {'migration': '092_feed_cleared_threads'},
  );

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS feed_cleared_threads (
        thread_kind TEXT NOT NULL,
        thread_id TEXT NOT NULL,
        cleared_at_ms INTEGER NOT NULL,
        PRIMARY KEY (thread_kind, thread_id)
      )
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'FEED_CLEARED_THREADS_MIGRATION_SUCCESS',
      details: {'migration': '092_feed_cleared_threads'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'FEED_CLEARED_THREADS_MIGRATION_ERROR',
      details: {
        'migration': '092_feed_cleared_threads',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
