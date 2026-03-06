import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 020: Adds introduction banner columns to the contacts table.
///
/// - `intros_banner_dismissed INTEGER DEFAULT 0` — 0 = shown, 1 = dismissed
/// - `intros_sent_at TEXT` — nullable; ISO-8601 timestamp of last intro sent
///
/// Idempotent: checks PRAGMA table_info before running.
Future<void> runIntroBannerColumnsMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(contacts)');
  final hasIntroBannerDismissed =
      columns.any((col) => col['name'] == 'intros_banner_dismissed');
  if (hasIntroBannerDismissed) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRO_BANNER_COLUMNS_MIGRATION_ALREADY_DONE',
      details: {'migration': '020_intro_banner_columns'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'INTRO_BANNER_COLUMNS_MIGRATION_START',
    details: {'migration': '020_intro_banner_columns'},
  );

  try {
    await db.transaction((txn) async {
      await txn.execute(
        'ALTER TABLE contacts ADD COLUMN intros_banner_dismissed INTEGER DEFAULT 0',
      );
      await txn.execute(
        'ALTER TABLE contacts ADD COLUMN intros_sent_at TEXT',
      );
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'INTRO_BANNER_COLUMNS_MIGRATION_SUCCESS',
      details: {'migration': '020_intro_banner_columns'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRO_BANNER_COLUMNS_MIGRATION_ERROR',
      details: {'migration': '020_intro_banner_columns', 'error': e.toString()},
    );
    rethrow;
  }
}
