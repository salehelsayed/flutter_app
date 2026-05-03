import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 061: Adds verified transport Peer ID storage to group messages.
Future<void> runGroupMessageTransportPeerIdMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MESSAGE_TRANSPORT_PEER_ID_MIGRATION_START',
    details: {'migration': '061_group_message_transport_peer_id'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
    final columnNames = columns.map((column) => column['name']).toSet();

    if (columnNames.contains('transport_peer_id')) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_MESSAGE_TRANSPORT_PEER_ID_MIGRATION_ALREADY_DONE',
        details: {'migration': '061_group_message_transport_peer_id'},
      );
      return;
    }

    await db.execute(
      'ALTER TABLE group_messages ADD COLUMN transport_peer_id TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGE_TRANSPORT_PEER_ID_MIGRATION_SUCCESS',
      details: {'migration': '061_group_message_transport_peer_id'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MESSAGE_TRANSPORT_PEER_ID_MIGRATION_ERROR',
      details: {
        'migration': '061_group_message_transport_peer_id',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
