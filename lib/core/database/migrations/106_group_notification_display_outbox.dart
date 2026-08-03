// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _migrationName = '106_group_notification_display_outbox';

/// Adds durable custody for group notification display and reconciliation.
///
/// Both outboxes deliberately contain only canonical or opaque identifiers
/// and exact state comparands. Notification title/body/preview/media paths
/// never enter either table. Neither has foreign keys: display custody can
/// precede its canonical event, while reconciliation custody must survive a
/// canonical group deletion long enough to remove its projected card.
Future<void> runGroupNotificationDisplayOutboxMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_NOTIFICATION_DISPLAY_OUTBOX_MIGRATION_START',
    details: const {'migration': _migrationName},
  );

  try {
    // These identifier-only terminal facts live on the canonical rows instead
    // of in a second receipt/outbox table. Their storage is therefore bounded
    // by canonical history retention: message/reaction deletion, group-history
    // deletion, and account-database reset remove them with their owner.
    await _addTerminalDisplayColumnIfMissing(db, 'group_messages');
    await _addTerminalDisplayColumnIfMissing(db, 'message_reactions');
    await _addNullableTextColumnIfMissing(
      db,
      'message_reactions',
      'notification_acknowledged_at',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_notification_read_acknowledgements (
        group_id TEXT NOT NULL
          CHECK(length(trim(group_id)) BETWEEN 1 AND 1024),
        content_kind TEXT NOT NULL
          CHECK(content_kind IN ('message', 'reaction')),
      event_identity TEXT NOT NULL
          CHECK(length(trim(event_identity)) >= 1),
        generation TEXT NOT NULL
          CHECK(length(trim(generation)) BETWEEN 1 AND 1024),
        acknowledged_at TEXT NOT NULL
          CHECK(length(trim(acknowledged_at)) > 0),
        PRIMARY KEY(group_id, content_kind, event_identity, generation)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS
        idx_group_notification_read_acknowledgements_group
      ON group_notification_read_acknowledgements(
        group_id, acknowledged_at, event_identity
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_notification_display_outbox (
        event_id TEXT PRIMARY KEY CHECK(length(event_id) > 0),
        event_kind TEXT NOT NULL CHECK(event_kind IN ('message', 'reaction')),
        group_id TEXT NOT NULL CHECK(length(group_id) > 0),
        message_id TEXT NOT NULL CHECK(length(message_id) > 0),
        actor_peer_id TEXT NOT NULL CHECK(length(actor_peer_id) > 0),
        event_timestamp TEXT NOT NULL CHECK(length(event_timestamp) > 0),
        reaction_id TEXT,
        reaction_action TEXT,
        reaction_tombstone INTEGER,
        readiness TEXT NOT NULL DEFAULT 'not_ready'
          CHECK(readiness IN ('not_ready', 'ready')),
        revision INTEGER NOT NULL DEFAULT 1 CHECK(revision >= 1),
        retry_count INTEGER NOT NULL DEFAULT 0 CHECK(retry_count >= 0),
        last_error_code TEXT CHECK(last_error_code IS NULL OR last_error_code IN (
          'display_failed',
          'claim_pending',
          'state_unavailable'
        )),
        last_attempt_at TEXT,
        next_attempt_at TEXT,
        created_at TEXT NOT NULL CHECK(length(created_at) > 0),
        updated_at TEXT NOT NULL CHECK(length(updated_at) > 0),
        CHECK(
          (
            event_kind = 'message'
            AND reaction_id IS NULL
            AND reaction_action IS NULL
            AND reaction_tombstone IS NULL
          )
          OR (
            event_kind = 'reaction'
            AND reaction_id IS NOT NULL
            AND length(reaction_id) > 0
            AND reaction_action IN ('add', 'remove')
            AND reaction_tombstone IN (0, 1)
            AND (
              (reaction_action = 'add' AND reaction_tombstone = 0)
              OR (reaction_action = 'remove' AND reaction_tombstone = 1)
            )
          )
        )
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_notification_display_outbox_ready
      ON group_notification_display_outbox(
        readiness, next_attempt_at, created_at, event_id
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_notification_display_outbox_group_message
      ON group_notification_display_outbox(
        group_id, message_id, created_at, event_id
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_notification_display_outbox_reaction
      ON group_notification_display_outbox(
        group_id, message_id, reaction_id, created_at, event_id
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_notification_reconciliation_outbox (
        group_id TEXT PRIMARY KEY CHECK(length(trim(group_id)) > 0),
        incarnation_id TEXT NOT NULL
          CHECK(length(incarnation_id) = 32),
        revision INTEGER NOT NULL DEFAULT 1 CHECK(revision >= 1),
        retry_count INTEGER NOT NULL DEFAULT 0 CHECK(retry_count >= 0),
        last_attempt_at TEXT,
        next_attempt_at TEXT,
        created_at TEXT NOT NULL CHECK(length(created_at) > 0),
        updated_at TEXT NOT NULL CHECK(length(updated_at) > 0)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS
        idx_group_notification_reconciliation_outbox_eligible
      ON group_notification_reconciliation_outbox(
        next_attempt_at, created_at, group_id
      )
    ''');
    // A headless push can be acknowledged before its canonical message reaches
    // the inbox. Materialization atomically absorbs that exact identifier-only
    // fact so the new row cannot become unread after the user already viewed
    // the conversation.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_group_notification_read_ack_message_insert
      AFTER INSERT ON group_messages
      WHEN NEW.is_incoming = 1 AND EXISTS (
        SELECT 1 FROM group_notification_read_acknowledgements AS ack
        WHERE ack.group_id = NEW.group_id
          AND ack.content_kind = 'message'
          AND ack.event_identity = NEW.id
      )
      BEGIN
        UPDATE group_messages
        SET read_at = COALESCE(
          read_at,
          (
            SELECT MAX(acknowledged_at)
            FROM group_notification_read_acknowledgements AS ack
            WHERE ack.group_id = NEW.group_id
              AND ack.content_kind = 'message'
              AND ack.event_identity = NEW.id
          )
        )
        WHERE id = NEW.id AND group_id = NEW.group_id;

        DELETE FROM group_notification_read_acknowledgements
        WHERE group_id = NEW.group_id
          AND content_kind = 'message'
          AND event_identity = NEW.id;

        INSERT INTO group_notification_reconciliation_outbox (
          group_id, incarnation_id, revision, retry_count,
          last_attempt_at, next_attempt_at, created_at, updated_at
        ) VALUES (
          NEW.group_id,
          lower(hex(randomblob(16))),
          1,
          0,
          NULL,
          NULL,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
        ON CONFLICT(group_id) DO UPDATE SET
          revision = revision + 1,
          retry_count = 0,
          last_attempt_at = NULL,
          next_attempt_at = NULL,
          updated_at = excluded.updated_at;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_group_notification_reconcile_policy_change
      AFTER UPDATE OF
        type, is_muted, is_archived, is_dissolved, dissolved_at,
        self_removed_at
      ON groups
      WHEN OLD.type IS NOT NEW.type
        OR OLD.is_muted IS NOT NEW.is_muted
        OR OLD.is_archived IS NOT NEW.is_archived
        OR OLD.is_dissolved IS NOT NEW.is_dissolved
        OR OLD.dissolved_at IS NOT NEW.dissolved_at
        OR OLD.self_removed_at IS NOT NEW.self_removed_at
      BEGIN
        INSERT INTO group_notification_reconciliation_outbox (
          group_id,
          incarnation_id,
          revision,
          retry_count,
          last_attempt_at,
          next_attempt_at,
          created_at,
          updated_at
        ) VALUES (
          NEW.id,
          lower(hex(randomblob(16))),
          1,
          0,
          NULL,
          NULL,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
        ON CONFLICT(group_id) DO UPDATE SET
          revision = revision + 1,
          retry_count = 0,
          last_attempt_at = NULL,
          next_attempt_at = NULL,
          updated_at = excluded.updated_at;
      END
    ''');
    // Existing groups can be written through INSERT OR REPLACE. SQLite does
    // not classify that path as UPDATE (and its implicit DELETE trigger is
    // conditional on recursive_triggers), so the INSERT leg is the durable
    // policy-invalidation authority for both replacements and fresh rows. A
    // fresh row has no managed card and reconciles to a cheap no-op.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_group_notification_reconcile_group_insert
      AFTER INSERT ON groups
      BEGIN
        INSERT INTO group_notification_reconciliation_outbox (
          group_id,
          incarnation_id,
          revision,
          retry_count,
          last_attempt_at,
          next_attempt_at,
          created_at,
          updated_at
        ) VALUES (
          NEW.id,
          lower(hex(randomblob(16))),
          1,
          0,
          NULL,
          NULL,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
        ON CONFLICT(group_id) DO UPDATE SET
          revision = revision + 1,
          retry_count = 0,
          last_attempt_at = NULL,
          next_attempt_at = NULL,
          updated_at = excluded.updated_at;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_group_notification_reconcile_group_delete
      AFTER DELETE ON groups
      BEGIN
        INSERT INTO group_notification_reconciliation_outbox (
          group_id,
          incarnation_id,
          revision,
          retry_count,
          last_attempt_at,
          next_attempt_at,
          created_at,
          updated_at
        ) VALUES (
          OLD.id,
          lower(hex(randomblob(16))),
          1,
          0,
          NULL,
          NULL,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
        ON CONFLICT(group_id) DO UPDATE SET
          revision = revision + 1,
          retry_count = 0,
          last_attempt_at = NULL,
          next_attempt_at = NULL,
          updated_at = excluded.updated_at;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_group_notification_read_ack_group_delete
      AFTER DELETE ON groups
      BEGIN
        DELETE FROM group_notification_read_acknowledgements
        WHERE group_id = OLD.id;
      END
    ''');
    // Canonical display policy depends on the local account still having a
    // current membership row. Enqueue every member deletion because SQLite
    // triggers cannot cheaply distinguish the local identity; group-keyed
    // coalescing makes non-local removals harmless while preserving durable
    // self-membership invalidation across crashes and process boundaries.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_group_notification_reconcile_member_delete
      AFTER DELETE ON group_members
      BEGIN
        INSERT INTO group_notification_reconciliation_outbox (
          group_id,
          incarnation_id,
          revision,
          retry_count,
          last_attempt_at,
          next_attempt_at,
          created_at,
          updated_at
        ) VALUES (
          OLD.group_id,
          lower(hex(randomblob(16))),
          1,
          0,
          NULL,
          NULL,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
        ON CONFLICT(group_id) DO UPDATE SET
          revision = revision + 1,
          retry_count = 0,
          last_attempt_at = NULL,
          next_attempt_at = NULL,
          updated_at = excluded.updated_at;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_group_notification_reconcile_message_delete
      AFTER DELETE ON group_messages
      BEGIN
        INSERT INTO group_notification_reconciliation_outbox (
          group_id,
          incarnation_id,
          revision,
          retry_count,
          last_attempt_at,
          next_attempt_at,
          created_at,
          updated_at
        ) VALUES (
          OLD.group_id,
          lower(hex(randomblob(16))),
          1,
          0,
          NULL,
          NULL,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
        ON CONFLICT(group_id) DO UPDATE SET
          revision = revision + 1,
          retry_count = 0,
          last_attempt_at = NULL,
          next_attempt_at = NULL,
          updated_at = excluded.updated_at;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_group_notification_reconcile_message_read
      AFTER UPDATE OF read_at ON group_messages
      WHEN OLD.read_at IS NULL AND NEW.read_at IS NOT NULL
      BEGIN
        INSERT INTO group_notification_reconciliation_outbox (
          group_id,
          incarnation_id,
          revision,
          retry_count,
          last_attempt_at,
          next_attempt_at,
          created_at,
          updated_at
        ) VALUES (
          NEW.group_id,
          lower(hex(randomblob(16))),
          1,
          0,
          NULL,
          NULL,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
        ON CONFLICT(group_id) DO UPDATE SET
          revision = revision + 1,
          retry_count = 0,
          last_attempt_at = NULL,
          next_attempt_at = NULL,
          updated_at = excluded.updated_at;
      END
    ''');
    // A target deletion already leaves only identifier-only notification
    // authority on the retained reaction row. Keep that exact event binding:
    // the deletion trigger above queues canonical reconciliation, which needs
    // the marker to prove that the now-invalid OS generation must retire.
    // Drop the earlier development trigger as well so re-running this
    // idempotent migration repairs databases created from that draft.
    await db.execute(
      'DROP TRIGGER IF EXISTS '
      'trg_group_message_delete_clear_reaction_notification_terminal',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_NOTIFICATION_DISPLAY_OUTBOX_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (_) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_NOTIFICATION_DISPLAY_OUTBOX_MIGRATION_ERROR',
      details: const {'migration': _migrationName},
    );
    rethrow;
  }
}

Future<void> _addTerminalDisplayColumnIfMissing(
  Database db,
  String table,
) async {
  await _addNullableTextColumnIfMissing(
    db,
    table,
    'notification_display_terminal_event_id',
  );
}

Future<void> _addNullableTextColumnIfMissing(
  Database db,
  String table,
  String column,
) async {
  final columns = await db.rawQuery('PRAGMA table_info($table)');
  if (columns.any((candidate) => candidate['name'] == column)) {
    return;
  }
  await db.execute('ALTER TABLE $table ADD COLUMN $column TEXT');
}
