// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 087 (finding 05 Phase 4): per-row retry backoff + terminal state
/// for outgoing group messages.
///
/// Adds:
///   * `retry_attempt_count INTEGER NOT NULL DEFAULT 0` — how many times the
///     background retrier has re-sent this row, used to apply exponential
///     backoff and to flip the row to the terminal `send_failed` status once a
///     cap is exceeded (so a permanently-undeliverable send stops being retried
///     forever).
///   * `next_eligible_at INTEGER` (epoch ms, nullable) — the earliest time the
///     retrier should attempt this row again; NULL means immediately eligible.
///
/// Additive + idempotent (column-exists guards), no CHECK constraints — mirrors
/// the `042_media_attachment_reliability_columns` precedent. The columns are
/// managed exclusively by dedicated setters; they are intentionally NOT written
/// by `GroupMessage.toMap()` so ordinary row updates cannot clobber the backoff
/// state.
Future<void> runGroupMessageRetryBackoffColumnsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGE_RETRY_BACKOFF_COLUMNS_MIGRATION_START',
    details: {'migration': '087_group_message_retry_backoff_columns'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
    final columnNames = columns.map((column) => column['name']).toSet();

    if (!columnNames.contains('retry_attempt_count')) {
      await db.execute(
        'ALTER TABLE group_messages '
        'ADD COLUMN retry_attempt_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!columnNames.contains('next_eligible_at')) {
      await db.execute(
        'ALTER TABLE group_messages ADD COLUMN next_eligible_at INTEGER',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGE_RETRY_BACKOFF_COLUMNS_MIGRATION_SUCCESS',
      details: {'migration': '087_group_message_retry_backoff_columns'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGE_RETRY_BACKOFF_COLUMNS_MIGRATION_ERROR',
      details: {
        'migration': '087_group_message_retry_backoff_columns',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
