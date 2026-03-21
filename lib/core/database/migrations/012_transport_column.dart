import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Migration 012: Add `transport` column to `messages` table.
///
/// Stores the transport type used for the message: 'wifi', 'relay', 'inbox',
/// or NULL (unknown / pre-migration messages).
Future<void> runTransportColumnMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(messages)');
  final hasColumn = columns.any((col) => col['name'] == 'transport');
  if (hasColumn) {
    emitFlowEvent(
      layer: 'DB',
      event: 'TRANSPORT_COLUMN_MIGRATION_ALREADY_DONE',
      details: {'migration': '012_transport_column'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'TRANSPORT_COLUMN_MIGRATION_START',
    details: {'migration': '012_transport_column'},
  );

  try {
    await db.execute(
      'ALTER TABLE messages ADD COLUMN transport TEXT',
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'TRANSPORT_COLUMN_MIGRATION_SUCCESS',
      details: {'migration': '012_transport_column'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'TRANSPORT_COLUMN_MIGRATION_ERROR',
      details: {'migration': '012_transport_column', 'error': e.toString()},
    );
    rethrow;
  }
}
