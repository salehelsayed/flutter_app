// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

/// Task 12b: durable state for the reply-once existing-contact repair.
///
/// * `contact_relationship_consent` remembers a NEW deletion or decline as a
///   revisioned relationship record. Triggers on `contacts` and
///   `contact_requests` keep it in step with every deletion path (including the
///   atomic purge) without each caller having to remember. A REPLACE upsert of
///   an existing contact does not fire the delete trigger (recursive triggers
///   are off), and the insert trigger only bumps a non-active record, so
///   routine ML-KEM re-announces never change the revision. Existing contacts
///   are backfilled as `active` revision 1. Historical deletions are NOT
///   reconstructed: a peer with no record keeps today's first-contact
///   behaviour.
/// * `contact_repair_requests` holds one row per authenticated signed request
///   ID: the reply reservation, its immutable prebuilt envelope and its
///   bounded retry state. Its primary key is the duplicate guard.
/// * `contact_repair_peer_state` holds the per-peer reply pacing and whether
///   the peer has demonstrated support for the signed marker.
/// * `contact_repair_clock` holds the persisted effective-clock high-water.
///
/// Historical backfill for the repair tables is deliberately empty.
Future<void> runContactRepairMigration(Database database) async {
  final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
  await database.execute('''
CREATE TABLE IF NOT EXISTS contact_relationship_consent (
  peer_id TEXT PRIMARY KEY NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('active', 'withdrawn', 'declined')),
  revision INTEGER NOT NULL CHECK (revision >= 1),
  updated_at_ms INTEGER NOT NULL
)''');
  await database.execute(
    'INSERT OR IGNORE INTO contact_relationship_consent '
    '(peer_id, state, revision, updated_at_ms) '
    "SELECT peer_id, 'active', 1, ? FROM contacts",
    <Object?>[nowMs],
  );
  await database.execute('''
CREATE TABLE IF NOT EXISTS contact_repair_requests (
  peer_id TEXT NOT NULL,
  request_id TEXT NOT NULL,
  request_digest TEXT NOT NULL,
  signed_at_ms INTEGER NOT NULL,
  guard_until_ms INTEGER NOT NULL,
  authority_fingerprint TEXT NOT NULL,
  local_authority_fingerprint TEXT NOT NULL,
  relationship_revision INTEGER NOT NULL,
  state TEXT NOT NULL CHECK (state IN (
    'buildable', 'ready', 'sending',
    'completed', 'exhausted', 'expired', 'cancelled')),
  reply_id TEXT NOT NULL UNIQUE,
  due_at_ms INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  claim_token TEXT,
  envelope_json TEXT,
  grant_generation INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (peer_id, request_id)
)''');
  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_contact_repair_requests_due '
    'ON contact_repair_requests(state, due_at_ms)',
  );
  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_contact_repair_requests_guard '
    'ON contact_repair_requests(guard_until_ms)',
  );
  await database.execute('''
CREATE TABLE IF NOT EXISTS contact_repair_peer_state (
  peer_id TEXT PRIMARY KEY NOT NULL,
  next_reply_not_before_ms INTEGER NOT NULL DEFAULT 0,
  supports_marked INTEGER NOT NULL DEFAULT 0 CHECK (supports_marked IN (0, 1)),
  updated_at_ms INTEGER NOT NULL
)''');
  await database.execute('''
CREATE TABLE IF NOT EXISTS contact_repair_clock (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  high_water_ms INTEGER NOT NULL
)''');
  await database.execute('''
CREATE TRIGGER IF NOT EXISTS contact_relationship_consent_contact_insert
AFTER INSERT ON contacts
BEGIN
  INSERT INTO contact_relationship_consent
    (peer_id, state, revision, updated_at_ms)
  VALUES
    (NEW.peer_id, 'active', 1, CAST(strftime('%s', 'now') AS INTEGER) * 1000)
  ON CONFLICT(peer_id) DO UPDATE SET
    state = 'active',
    revision = contact_relationship_consent.revision + 1,
    updated_at_ms = excluded.updated_at_ms
  WHERE contact_relationship_consent.state != 'active';
END''');
  await database.execute('''
CREATE TRIGGER IF NOT EXISTS contact_relationship_consent_contact_delete
AFTER DELETE ON contacts
BEGIN
  INSERT INTO contact_relationship_consent
    (peer_id, state, revision, updated_at_ms)
  VALUES
    (OLD.peer_id, 'withdrawn', 1, CAST(strftime('%s', 'now') AS INTEGER) * 1000)
  ON CONFLICT(peer_id) DO UPDATE SET
    state = 'withdrawn',
    revision = contact_relationship_consent.revision + 1,
    updated_at_ms = excluded.updated_at_ms;
  UPDATE contact_repair_requests
    SET state = 'cancelled', claim_token = NULL,
        updated_at_ms = CAST(strftime('%s', 'now') AS INTEGER) * 1000
    WHERE peer_id = OLD.peer_id
      AND state IN ('buildable', 'ready', 'sending');
END''');
  await database.execute('''
CREATE TRIGGER IF NOT EXISTS contact_relationship_consent_request_declined
AFTER UPDATE OF status ON contact_requests
WHEN NEW.status = 'declined'
  AND NOT EXISTS (SELECT 1 FROM contacts WHERE peer_id = NEW.peer_id)
BEGIN
  INSERT INTO contact_relationship_consent
    (peer_id, state, revision, updated_at_ms)
  VALUES
    (NEW.peer_id, 'declined', 1, CAST(strftime('%s', 'now') AS INTEGER) * 1000)
  ON CONFLICT(peer_id) DO UPDATE SET
    state = 'declined',
    revision = contact_relationship_consent.revision + 1,
    updated_at_ms = excluded.updated_at_ms
  WHERE contact_relationship_consent.state != 'declined';
END''');
  await database.execute('''
CREATE TRIGGER IF NOT EXISTS contact_repair_cancel_on_block
AFTER UPDATE OF is_blocked ON contacts
WHEN NEW.is_blocked = 1
BEGIN
  UPDATE contact_repair_requests
    SET state = 'cancelled', claim_token = NULL,
        updated_at_ms = CAST(strftime('%s', 'now') AS INTEGER) * 1000
    WHERE peer_id = NEW.peer_id
      AND state IN ('buildable', 'ready', 'sending');
END''');
}
