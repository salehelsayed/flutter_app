import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Migration 014: Add `wire_envelope` column to `messages` table.
///
/// Stores the serialized wire envelope (JSON) for outgoing messages that
/// were written to the stream but not ACK'd. Used by the retry service
/// to store the message in the relay inbox without re-encrypting.
Future<void> runWireEnvelopeMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(messages)');
  final hasColumn = columns.any((col) => col['name'] == 'wire_envelope');
  if (hasColumn) {
    emitFlowEvent(
      layer: 'DB',
      event: 'WIRE_ENVELOPE_MIGRATION_ALREADY_DONE',
      details: {'migration': '014_wire_envelope_column'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'WIRE_ENVELOPE_MIGRATION_START',
    details: {'migration': '014_wire_envelope_column'},
  );

  try {
    await db.execute(
      'ALTER TABLE messages ADD COLUMN wire_envelope TEXT',
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'WIRE_ENVELOPE_MIGRATION_SUCCESS',
      details: {'migration': '014_wire_envelope_column'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'WIRE_ENVELOPE_MIGRATION_ERROR',
      details: {'migration': '014_wire_envelope_column', 'error': e.toString()},
    );
    rethrow;
  }
}
