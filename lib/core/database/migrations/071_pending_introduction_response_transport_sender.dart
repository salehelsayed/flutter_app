import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 071: Adds verified transport Peer ID storage to pending intro responses.
Future<void> runPendingIntroductionResponseTransportSenderMigration(
  Database db,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_INTRO_RESPONSE_TRANSPORT_SENDER_MIGRATION_START',
    details: {
      'migration': '071_pending_introduction_response_transport_sender',
    },
  );

  try {
    final columns = await db.rawQuery(
      'PRAGMA table_info(pending_introduction_responses)',
    );
    final columnNames = columns.map((column) => column['name']).toSet();

    if (!columnNames.contains('transport_sender_peer_id')) {
      await db.execute(
        'ALTER TABLE pending_introduction_responses ADD COLUMN transport_sender_peer_id TEXT',
      );
    }

    final rowsUpdated = await db.rawUpdate(
      'UPDATE pending_introduction_responses SET transport_sender_peer_id = responder_id WHERE transport_sender_peer_id IS NULL',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_INTRO_RESPONSE_TRANSPORT_SENDER_MIGRATION_SUCCESS',
      details: {
        'migration': '071_pending_introduction_response_transport_sender',
        'backfilled': rowsUpdated,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_INTRO_RESPONSE_TRANSPORT_SENDER_MIGRATION_ERROR',
      details: {
        'migration': '071_pending_introduction_response_transport_sender',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
