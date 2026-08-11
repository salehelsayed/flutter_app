// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _migrationName = '112_direct_linked_device_addressing';

/// Fixed per-contact capacity for linked device bindings (Plan 360).
///
/// Enforced by the helper rather than by SQL because overflow must refuse the
/// whole staging attempt all-zero, not partially insert and then fail a
/// trigger. Exact replay of an already-known binding is allowed to win BEFORE
/// this bound so a re-scanned QR is idempotent even at capacity.
const int directContactDeviceBindingCapacity = 16;

/// Remote-contact linked-device roster (Plan 360 / GAP-N01).
///
/// Deliberate schema decisions:
///
/// * No FOREIGN KEY to `contacts`. Ordinary contact upsert uses SQLite
///   REPLACE semantics (`dbUpsertContact`), so an FK with ON DELETE CASCADE
///   would silently destroy an explicitly-verified roster every time the same
///   contact re-announced a key. Only the exact contact-deletion owner
///   (`dbDeleteContact`) removes roster rows, transactionally.
/// * `transport_peer_id` is globally UNIQUE. A transport peer identifies one
///   physical installation; two contacts claiming the same transport owner is
///   either a copy-paste attack or a bug, and both must refuse.
/// * `transport_peer_id <> contact_account_peer_id` unconditionally. Every row
///   in this table describes a LINKED device, never the contact's own primary
///   account transport — that target stays dynamic in `contacts` and is
///   resolved through the metadata table's legacy state instead.
/// * The immutable fingerprint deliberately excludes QR issued-at and both
///   signatures, so a freshly-issued QR for the same credential replays as
///   identical rather than as a contradictory second binding.
const _createDirectContactDeviceBindingsTableSql = '''
CREATE TABLE IF NOT EXISTS direct_contact_device_bindings (
  contact_account_peer_id TEXT NOT NULL
    CHECK(length(trim(contact_account_peer_id)) > 0),
  device_id TEXT NOT NULL CHECK(
    typeof(device_id) = 'text' AND
    device_id = trim(device_id) AND
    length(device_id) > 0 AND
    length(device_id) <= 128
  ),
  verified_account_signing_public_key TEXT NOT NULL
    CHECK(length(trim(verified_account_signing_public_key)) > 0),
  transport_peer_id TEXT NOT NULL
    CHECK(length(trim(transport_peer_id)) > 0),
  transport_public_key TEXT NOT NULL
    CHECK(length(trim(transport_public_key)) > 0),
  device_ml_kem_public_key TEXT NOT NULL
    CHECK(length(trim(device_ml_kem_public_key)) > 0),
  binding_fingerprint TEXT NOT NULL CHECK(
    typeof(binding_fingerprint) = 'text' AND
    length(binding_fingerprint) = 64 AND
    length(CAST(binding_fingerprint AS BLOB)) = 64 AND
    binding_fingerprint NOT GLOB '*[^0-9a-f]*'
  ),
  state TEXT NOT NULL CHECK(
    state IN ('pending', 'active', 'rejected', 'revoked')
  ),
  staged_at TEXT NOT NULL CHECK(length(trim(staged_at)) > 0),
  decided_at TEXT CHECK(decided_at IS NULL OR length(trim(decided_at)) > 0),

  PRIMARY KEY (contact_account_peer_id, device_id),

  -- A linked device is never the contact's own account transport.
  CHECK(transport_peer_id <> contact_account_peer_id),
  -- A device never re-uses the account's Ed25519 key as its transport key.
  CHECK(transport_public_key <> verified_account_signing_public_key),
  -- `pending` is the only state without a recorded decision.
  CHECK(
    (state = 'pending' AND decided_at IS NULL) OR
    (state <> 'pending' AND decided_at IS NOT NULL)
  )
);
''';

/// One transport peer belongs to exactly one linked device, globally.
const _createDirectContactDeviceBindingsTransportIndexSql = '''
CREATE UNIQUE INDEX IF NOT EXISTS
  idx_direct_contact_device_bindings_transport_owner
ON direct_contact_device_bindings(transport_peer_id);
''';

/// Target resolution reads active rows per contact; capacity counting reads
/// every row per contact.
const _createDirectContactDeviceBindingsContactStateIndexSql = '''
CREATE INDEX IF NOT EXISTS
  idx_direct_contact_device_bindings_contact_state
ON direct_contact_device_bindings(contact_account_peer_id, state, device_id);
''';

/// Per-contact roster metadata (Plan 360 / GAP-N01).
///
/// `roster_initialized` is EXPLICIT rather than derived from "has any binding
/// row". A contact whose only device was rejected, or whose legacy target was
/// revoked, is still initialized — deriving the flag would silently resurrect
/// the legacy fallback and re-prompt for a decision the user already made.
///
/// `legacy_target_state` tracks the contact's own dynamic account target. It
/// is NOT materialized as a binding row: the legacy peer/ML-KEM live in
/// `contacts` and change under ordinary key rotation, whereas every binding
/// row's material is immutable by construction.
const _createDirectContactDeviceRosterMetadataTableSql = '''
CREATE TABLE IF NOT EXISTS direct_contact_device_roster_metadata (
  contact_account_peer_id TEXT NOT NULL PRIMARY KEY
    CHECK(length(trim(contact_account_peer_id)) > 0),
  roster_initialized INTEGER NOT NULL DEFAULT 0
    CHECK(roster_initialized IN (0, 1)),
  legacy_target_state TEXT NOT NULL DEFAULT 'active'
    CHECK(legacy_target_state IN ('active', 'revoked')),
  initialized_at TEXT CHECK(
    initialized_at IS NULL OR length(trim(initialized_at)) > 0
  ),
  legacy_revoked_at TEXT CHECK(
    legacy_revoked_at IS NULL OR length(trim(legacy_revoked_at)) > 0
  ),
  updated_at TEXT NOT NULL CHECK(length(trim(updated_at)) > 0),

  CHECK(
    (roster_initialized = 0 AND initialized_at IS NULL) OR
    (roster_initialized = 1 AND initialized_at IS NOT NULL)
  ),
  CHECK(
    (legacy_target_state = 'active' AND legacy_revoked_at IS NULL) OR
    (legacy_target_state = 'revoked' AND legacy_revoked_at IS NOT NULL)
  ),
  -- The legacy target can only be revoked once the roster is initialized;
  -- otherwise a contact would have no reachable target and no recorded
  -- decision explaining why.
  CHECK(legacy_target_state = 'active' OR roster_initialized = 1)
);
''';

/// Adds the remote-contact linked-device roster at DB v112.
///
/// Historical backfill is deliberately EMPTY. Legacy canonical contact data
/// (the `contacts` peer/ML-KEM pair) must NOT be materialized as an immutable
/// binding: it is dynamic, it was never authenticated by a dual-signed device
/// QR, and freezing it would make ordinary key rotation look like a device
/// forgery. Before explicit initialization, target resolution stays exactly
/// the unchanged `ContactModel` peer/ML-KEM.
///
/// v112 is a one-way LOCAL schema floor. Remote-contact roster tables transfer
/// through an account Move; the installation's own linked role and transport
/// credential never do — those are device-local secure records outside every
/// migration bundle.
Future<void> runDirectLinkedDeviceAddressingMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'DIRECT_LINKED_DEVICE_ADDRESSING_MIGRATION_START',
    details: const {'migration': _migrationName},
  );

  try {
    await db.execute(_createDirectContactDeviceBindingsTableSql);
    await db.execute(_createDirectContactDeviceBindingsTransportIndexSql);
    await db.execute(_createDirectContactDeviceBindingsContactStateIndexSql);
    await db.execute(_createDirectContactDeviceRosterMetadataTableSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_LINKED_DEVICE_ADDRESSING_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_LINKED_DEVICE_ADDRESSING_MIGRATION_ERROR',
      details: {'migration': _migrationName, 'error': error.toString()},
    );
    rethrow;
  }
}
