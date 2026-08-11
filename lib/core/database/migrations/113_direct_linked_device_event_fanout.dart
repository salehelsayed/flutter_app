// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _migrationName = '113_direct_linked_device_event_fanout';

/// Adds the additive DB v113 blob-free direct-event fanout facts
/// (Plan 361 / GAP-N01 adopter).
///
/// Nullable additive columns ONLY — no table rebuild, no FK, no backfill:
///
/// * `messages.direct_event_fanout_generation_id` — the message ID for a
///   fanout initial, or the exact CURRENT edit/deletion event ID. Legacy and
///   historical messages stay NULL. It persists through receipt settlement and
///   hidden-tombstone reconstruction and is atomically replaced only by a
///   genuinely later edit/deletion generation.
/// * `direct_inbox_custody_outbox.contact_account_peer_id` — the LOGICAL
///   contact a fanout sibling belongs to. NULL retains the incumbent
///   single-target meaning (`recipient_peer_id` IS the logical contact).
/// * `direct_reaction_inbox_custody_outbox.contact_account_peer_id` — same
///   logical-contact fact for event siblings.
/// * `direct_reaction_inbox_custody_outbox.parent_message_id` — the logical
///   parent a v109 event names. The deletion outer envelope deliberately hides
///   its target, so a new linked row must persist this at authoring time; a
///   historical deletion may keep NULL even after its parent/contact is gone.
///
/// Historical rows are never promoted or guessed. Each added TEXT column
/// enforces `NULL` or nonblank with a column-local CHECK; the cross-column
/// generation shape is an application/helper invariant on NEW rows only, so
/// neither table is rebuilt merely to add a cross-column CHECK.
///
/// The only new indexes are generation-first lookups: every sibling of one
/// logical event must be loadable by `message_id` (v108) / `event_id` (v109)
/// without scanning the fair-load index.
///
/// v113 remains a one-way schema floor.
Future<void> runDirectLinkedDeviceEventFanoutMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'DIRECT_LINKED_DEVICE_EVENT_FANOUT_MIGRATION_START',
    details: const {'migration': _migrationName},
  );

  try {
    final messageColumns = await _columnNames(db, 'messages');
    if (!messageColumns.contains('direct_event_fanout_generation_id')) {
      await db.execute('''
        ALTER TABLE messages
        ADD COLUMN direct_event_fanout_generation_id TEXT
        CHECK(
          direct_event_fanout_generation_id IS NULL OR
          length(trim(direct_event_fanout_generation_id)) > 0
        )
      ''');
    }

    final custodyColumns = await _columnNames(
      db,
      'direct_inbox_custody_outbox',
    );
    if (!custodyColumns.contains('contact_account_peer_id')) {
      await db.execute('''
        ALTER TABLE direct_inbox_custody_outbox
        ADD COLUMN contact_account_peer_id TEXT
        CHECK(
          contact_account_peer_id IS NULL OR
          length(trim(contact_account_peer_id)) > 0
        )
      ''');
    }

    final eventColumns = await _columnNames(
      db,
      'direct_reaction_inbox_custody_outbox',
    );
    if (!eventColumns.contains('contact_account_peer_id')) {
      await db.execute('''
        ALTER TABLE direct_reaction_inbox_custody_outbox
        ADD COLUMN contact_account_peer_id TEXT
        CHECK(
          contact_account_peer_id IS NULL OR
          length(trim(contact_account_peer_id)) > 0
        )
      ''');
    }
    if (!eventColumns.contains('parent_message_id')) {
      await db.execute('''
        ALTER TABLE direct_reaction_inbox_custody_outbox
        ADD COLUMN parent_message_id TEXT
        CHECK(
          parent_message_id IS NULL OR
          length(trim(parent_message_id)) > 0
        )
      ''');
    }

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_direct_inbox_custody_outbox_generation
      ON direct_inbox_custody_outbox(message_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS
        idx_direct_reaction_inbox_custody_outbox_generation
      ON direct_reaction_inbox_custody_outbox(event_id)
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_LINKED_DEVICE_EVENT_FANOUT_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_LINKED_DEVICE_EVENT_FANOUT_MIGRATION_ERROR',
      details: {'migration': _migrationName, 'error': error.toString()},
    );
    rethrow;
  }
}

Future<Set<String>> _columnNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'] as String).toSet();
}
