import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Migration 013: Add `waveform` column to `media_attachments` table.
///
/// Stores a JSON-encoded list of normalized amplitude values for audio
/// visualization. Existing rows get NULL (no waveform data).
Future<void> runWaveformColumnMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(media_attachments)');
  final hasColumn = columns.any((col) => col['name'] == 'waveform');
  if (hasColumn) {
    emitFlowEvent(
      layer: 'DB',
      event: 'WAVEFORM_COLUMN_MIGRATION_ALREADY_DONE',
      details: {'migration': '013_waveform_column'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'WAVEFORM_COLUMN_MIGRATION_START',
    details: {'migration': '013_waveform_column'},
  );

  try {
    await db.execute(
      'ALTER TABLE media_attachments ADD COLUMN waveform TEXT',
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'WAVEFORM_COLUMN_MIGRATION_SUCCESS',
      details: {'migration': '013_waveform_column'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'WAVEFORM_COLUMN_MIGRATION_ERROR',
      details: {'migration': '013_waveform_column', 'error': e.toString()},
    );
    rethrow;
  }
}
