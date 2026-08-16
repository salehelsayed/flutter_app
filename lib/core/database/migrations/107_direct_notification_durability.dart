// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _migrationName = '107_direct_notification_durability';

/// Adds identifier-only durability for direct notification projection.
///
/// None of these tables stores notification copy, decrypted payloads, emoji,
/// or media paths. Foreign keys are deliberately absent: display and read
/// custody can arrive before canonical materialization, while reconciliation
/// must survive deletion of its contact/message owner long enough to retire the
/// corresponding OS card.
///
/// Direct reaction terminal state is intentionally separate from the shared
/// `message_reactions` table. That legacy table has no direct/group lane key;
/// joining it to a message table cannot make a colliding row typed.
Future<void> runDirectNotificationDurabilityMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'DIRECT_NOTIFICATION_DURABILITY_MIGRATION_START',
    details: const {'migration': _migrationName},
  );

  try {
    await _addNullableTextColumnIfMissing(
      db,
      'messages',
      'notification_display_terminal_event_id',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS direct_notification_read_acknowledgements (
        peer_id TEXT NOT NULL
          CHECK(length(trim(peer_id)) BETWEEN 1 AND 1024),
        content_kind TEXT NOT NULL
          CHECK(content_kind IN ('message', 'reaction')),
        event_identity TEXT NOT NULL CHECK(length(trim(event_identity)) >= 1),
        message_id TEXT NOT NULL CHECK(length(trim(message_id)) >= 1),
        actor_peer_id TEXT,
        generation TEXT NOT NULL
          CHECK(length(trim(generation)) BETWEEN 1 AND 1024),
        acknowledged_at TEXT NOT NULL
          CHECK(length(trim(acknowledged_at)) > 0),
        PRIMARY KEY(peer_id, content_kind, event_identity, generation),
        CHECK(
          (content_kind = 'message' AND actor_peer_id IS NULL
            AND event_identity = message_id)
          OR
          (content_kind = 'reaction' AND actor_peer_id IS NOT NULL
            AND length(trim(actor_peer_id)) BETWEEN 1 AND 1024)
        )
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS
        idx_direct_notification_read_acknowledgements_peer
      ON direct_notification_read_acknowledgements(
        peer_id, acknowledged_at, event_identity
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS
        idx_direct_notification_read_acknowledgements_message
      ON direct_notification_read_acknowledgements(
        peer_id, message_id, content_kind, actor_peer_id
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS direct_notification_reaction_terminal_events (
        peer_id TEXT NOT NULL
          CHECK(length(trim(peer_id)) BETWEEN 1 AND 1024),
        message_id TEXT NOT NULL CHECK(length(trim(message_id)) >= 1),
        actor_peer_id TEXT NOT NULL
          CHECK(length(trim(actor_peer_id)) BETWEEN 1 AND 1024),
        reaction_id TEXT NOT NULL CHECK(length(trim(reaction_id)) >= 1),
        terminal_event_id TEXT NOT NULL
          CHECK(length(trim(terminal_event_id)) >= 1),
        notification_acknowledged_at TEXT,
        updated_at TEXT NOT NULL CHECK(length(trim(updated_at)) > 0),
        PRIMARY KEY(peer_id, message_id, actor_peer_id)
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS
        idx_direct_notification_reaction_terminal_event
      ON direct_notification_reaction_terminal_events(
        peer_id, terminal_event_id
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS
        idx_direct_notification_reaction_terminal_message
      ON direct_notification_reaction_terminal_events(
        peer_id, message_id, actor_peer_id
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS direct_notification_display_outbox (
        event_id TEXT NOT NULL CHECK(length(trim(event_id)) > 0),
        event_kind TEXT NOT NULL CHECK(event_kind IN ('message', 'reaction')),
        peer_id TEXT NOT NULL
          CHECK(length(trim(peer_id)) BETWEEN 1 AND 1024),
        message_id TEXT NOT NULL CHECK(length(trim(message_id)) > 0),
        actor_peer_id TEXT NOT NULL
          CHECK(length(trim(actor_peer_id)) BETWEEN 1 AND 1024),
        event_timestamp TEXT NOT NULL CHECK(length(trim(event_timestamp)) > 0),
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
        created_at TEXT NOT NULL CHECK(length(trim(created_at)) > 0),
        updated_at TEXT NOT NULL CHECK(length(trim(updated_at)) > 0),
        PRIMARY KEY(peer_id, event_kind, event_id),
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
            AND length(trim(reaction_id)) > 0
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
      CREATE INDEX IF NOT EXISTS idx_direct_notification_display_outbox_ready
      ON direct_notification_display_outbox(
        readiness, next_attempt_at, created_at, event_id
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS
        idx_direct_notification_display_outbox_peer_message
      ON direct_notification_display_outbox(
        peer_id, message_id, created_at, event_id
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_direct_notification_display_outbox_reaction
      ON direct_notification_display_outbox(
        peer_id, message_id, actor_peer_id, reaction_id, created_at, event_id
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS direct_notification_reconciliation_outbox (
        peer_id TEXT PRIMARY KEY
          CHECK(length(trim(peer_id)) BETWEEN 1 AND 1024),
        incarnation_id TEXT NOT NULL CHECK(length(incarnation_id) = 32),
        revision INTEGER NOT NULL DEFAULT 1 CHECK(revision >= 1),
        retry_count INTEGER NOT NULL DEFAULT 0 CHECK(retry_count >= 0),
        last_attempt_at TEXT,
        next_attempt_at TEXT,
        created_at TEXT NOT NULL CHECK(length(trim(created_at)) > 0),
        updated_at TEXT NOT NULL CHECK(length(trim(updated_at)) > 0)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS
        idx_direct_notification_reconciliation_outbox_eligible
      ON direct_notification_reconciliation_outbox(
        next_attempt_at, created_at, peer_id
      )
    ''');

    // A read can race ahead of relay/canonical materialization. The incoming
    // message consumes only its exact peer-scoped fact. Updating read_at also
    // invokes the reconciliation trigger below, so no second enqueue is needed.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_direct_notification_read_ack_message_insert
      AFTER INSERT ON messages
      WHEN NEW.is_incoming = 1 AND EXISTS (
        SELECT 1 FROM direct_notification_read_acknowledgements AS ack
        WHERE ack.peer_id = NEW.contact_peer_id
          AND ack.content_kind = 'message'
          AND ack.event_identity = NEW.id
          AND ack.message_id = NEW.id
      )
      BEGIN
        UPDATE messages
        SET read_at = COALESCE(
          read_at,
          (
            SELECT MAX(acknowledged_at)
            FROM direct_notification_read_acknowledgements AS ack
            WHERE ack.peer_id = NEW.contact_peer_id
              AND ack.content_kind = 'message'
              AND ack.event_identity = NEW.id
              AND ack.message_id = NEW.id
          )
        )
        WHERE id = NEW.id AND contact_peer_id = NEW.contact_peer_id;

        DELETE FROM direct_notification_read_acknowledgements
        WHERE peer_id = NEW.contact_peer_id
          AND content_kind = 'message'
          AND event_identity = NEW.id
          AND message_id = NEW.id;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_direct_notification_reconcile_contact_policy
      AFTER UPDATE OF is_archived, is_blocked ON contacts
      WHEN OLD.is_archived IS NOT NEW.is_archived
        OR OLD.is_blocked IS NOT NEW.is_blocked
      BEGIN
        INSERT INTO direct_notification_reconciliation_outbox (
          peer_id, incarnation_id, revision, retry_count,
          last_attempt_at, next_attempt_at, created_at, updated_at
        ) VALUES (
          NEW.peer_id, lower(hex(randomblob(16))), 1, 0, NULL, NULL,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
        ON CONFLICT(peer_id) DO UPDATE SET
          revision = revision + 1,
          retry_count = 0,
          last_attempt_at = NULL,
          next_attempt_at = NULL,
          updated_at = excluded.updated_at;
      END
    ''');

    // Contacts are commonly persisted through INSERT OR REPLACE. The INSERT
    // leg therefore acts as the durable notification-policy invalidation seam.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_direct_notification_reconcile_contact_insert
      AFTER INSERT ON contacts
      BEGIN
        INSERT INTO direct_notification_reconciliation_outbox (
          peer_id, incarnation_id, revision, retry_count,
          last_attempt_at, next_attempt_at, created_at, updated_at
        ) VALUES (
          NEW.peer_id, lower(hex(randomblob(16))), 1, 0, NULL, NULL,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
        ON CONFLICT(peer_id) DO UPDATE SET
          revision = revision + 1,
          retry_count = 0,
          last_attempt_at = NULL,
          next_attempt_at = NULL,
          updated_at = excluded.updated_at;
      END
    ''');

    await _installDirectNotificationContactDeleteTrigger(db);

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_direct_notification_reconcile_message_read
      AFTER UPDATE OF read_at ON messages
      WHEN OLD.read_at IS NULL AND NEW.read_at IS NOT NULL
      BEGIN
        INSERT INTO direct_notification_reconciliation_outbox (
          peer_id, incarnation_id, revision, retry_count,
          last_attempt_at, next_attempt_at, created_at, updated_at
        ) VALUES (
          NEW.contact_peer_id, lower(hex(randomblob(16))), 1, 0, NULL, NULL,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
        ON CONFLICT(peer_id) DO UPDATE SET
          revision = revision + 1,
          retry_count = 0,
          last_attempt_at = NULL,
          next_attempt_at = NULL,
          updated_at = excluded.updated_at;
      END
    ''');

    await _installDirectNotificationMessageDeleteTrigger(db);

    // Direct private delete-for-me and logical deletion are UPDATEs, not
    // physical DELETEs. Both remove the row from notification eligibility and
    // must durably invalidate a card even when no listener is alive.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS
        trg_direct_notification_reconcile_message_eligibility
      AFTER UPDATE OF hidden_at, deleted_at ON messages
      WHEN OLD.hidden_at IS NOT NEW.hidden_at
        OR OLD.deleted_at IS NOT NEW.deleted_at
      BEGIN
        INSERT INTO direct_notification_reconciliation_outbox (
          peer_id, incarnation_id, revision, retry_count,
          last_attempt_at, next_attempt_at, created_at, updated_at
        ) VALUES (
          NEW.contact_peer_id, lower(hex(randomblob(16))), 1, 0, NULL, NULL,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        )
        ON CONFLICT(peer_id) DO UPDATE SET
          revision = revision + 1,
          retry_count = 0,
          last_attempt_at = NULL,
          next_attempt_at = NULL,
          updated_at = excluded.updated_at;
      END
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_NOTIFICATION_DURABILITY_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (_) {
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_NOTIFICATION_DURABILITY_MIGRATION_ERROR',
      details: const {'migration': _migrationName},
    );
    rethrow;
  }
}

/// Replaces the historical v107 delete triggers on an already-current DB.
///
/// Editing an already-completed migration cannot repair installations whose
/// `user_version` already advanced past it. Production invokes this idempotent
/// transaction immediately after opening the writable database. Exact READY
/// custody is revisioned and stamped as canonical retirement evidence; only
/// unarmed rows are physically removed.
Future<void> repairDirectNotificationDurabilityDeleteTriggers(Database db) =>
    db.transaction<void>((txn) async {
      await txn.execute(
        'DROP TRIGGER IF EXISTS '
        'trg_direct_notification_reconcile_contact_delete',
      );
      await txn.execute(
        'DROP TRIGGER IF EXISTS '
        'trg_direct_notification_reconcile_message_delete',
      );
      await _installDirectNotificationContactDeleteTrigger(txn);
      await _installDirectNotificationMessageDeleteTrigger(txn);
    });

Future<void> _installDirectNotificationContactDeleteTrigger(
  DatabaseExecutor db,
) => db.execute('''
  CREATE TRIGGER IF NOT EXISTS
    trg_direct_notification_reconcile_contact_delete
  AFTER DELETE ON contacts
  BEGIN
    INSERT INTO direct_notification_reconciliation_outbox (
      peer_id, incarnation_id, revision, retry_count,
      last_attempt_at, next_attempt_at, created_at, updated_at
    ) VALUES (
      OLD.peer_id, lower(hex(randomblob(16))), 1, 0, NULL, NULL,
      strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
      strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
    )
    ON CONFLICT(peer_id) DO UPDATE SET
      revision = revision + 1,
      retry_count = 0,
      last_attempt_at = NULL,
      next_attempt_at = NULL,
      updated_at = excluded.updated_at;

    UPDATE direct_notification_display_outbox
    SET revision = revision + 1,
        retry_count = 0,
        last_error_code = 'state_unavailable',
        last_attempt_at = 'canonical_retired',
        next_attempt_at = NULL,
        updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
    WHERE peer_id = OLD.peer_id AND readiness = 'ready';
    DELETE FROM direct_notification_display_outbox
    WHERE peer_id = OLD.peer_id AND readiness = 'not_ready';
    DELETE FROM direct_notification_read_acknowledgements
    WHERE peer_id = OLD.peer_id;
    DELETE FROM direct_notification_reaction_terminal_events
    WHERE peer_id = OLD.peer_id;
  END
''');

Future<void> _installDirectNotificationMessageDeleteTrigger(
  DatabaseExecutor db,
) => db.execute('''
  CREATE TRIGGER IF NOT EXISTS
    trg_direct_notification_reconcile_message_delete
  AFTER DELETE ON messages
  BEGIN
    INSERT INTO direct_notification_reconciliation_outbox (
      peer_id, incarnation_id, revision, retry_count,
      last_attempt_at, next_attempt_at, created_at, updated_at
    ) VALUES (
      OLD.contact_peer_id, lower(hex(randomblob(16))), 1, 0, NULL, NULL,
      strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
      strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
    )
    ON CONFLICT(peer_id) DO UPDATE SET
      revision = revision + 1,
      retry_count = 0,
      last_attempt_at = NULL,
      next_attempt_at = NULL,
      updated_at = excluded.updated_at;

    UPDATE direct_notification_display_outbox
    SET revision = revision + 1,
        retry_count = 0,
        last_error_code = 'state_unavailable',
        last_attempt_at = 'canonical_retired',
        next_attempt_at = NULL,
        updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
    WHERE peer_id = OLD.contact_peer_id AND message_id = OLD.id
      AND readiness = 'ready';
    DELETE FROM direct_notification_display_outbox
    WHERE peer_id = OLD.contact_peer_id AND message_id = OLD.id
      AND readiness = 'not_ready';
    DELETE FROM direct_notification_read_acknowledgements
    WHERE peer_id = OLD.contact_peer_id AND message_id = OLD.id;
    DELETE FROM direct_notification_reaction_terminal_events
    WHERE peer_id = OLD.contact_peer_id AND message_id = OLD.id;
  END
''');

Future<void> _addNullableTextColumnIfMissing(
  Database db,
  String table,
  String column,
) async {
  final columns = await db.rawQuery('PRAGMA table_info($table)');
  if (columns.any((candidate) => candidate['name'] == column)) return;
  await db.execute('ALTER TABLE $table ADD COLUMN $column TEXT');
}
