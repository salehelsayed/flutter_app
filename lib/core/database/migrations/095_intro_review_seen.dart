// ignore_for_file: file_names
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _createIntroReviewSeenSql = '''
CREATE TABLE IF NOT EXISTS intro_review_seen (
  item_key TEXT PRIMARY KEY,
  seen_at TEXT NOT NULL
);
''';

Future<void> runIntroReviewSeenMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'INTRO_REVIEW_SEEN_MIGRATION_START',
    details: {'migration': '095_intro_review_seen'},
  );

  try {
    await db.execute(_createIntroReviewSeenSql);
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRO_REVIEW_SEEN_MIGRATION_SUCCESS',
      details: {'migration': '095_intro_review_seen'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'INTRO_REVIEW_SEEN_MIGRATION_ERROR',
      details: {'migration': '095_intro_review_seen', 'error': e.toString()},
    );
    rethrow;
  }
}
