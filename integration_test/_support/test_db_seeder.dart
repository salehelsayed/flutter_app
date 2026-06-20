/// Canonical encrypted-DB bootstrap for integration_test harnesses.
///
/// This is the ONE place that owns the migration list, version gating, and the
/// SQLCipher opener flags used by the device E2E harnesses. It replaces the
/// copy-pasted `_openDb` / `_setupStack`-inline-opener / `_deleteTestDatabase`
/// bootstrap that previously lived (verbatim and drifting) in every harness.
///
/// STRICT BEHAVIOR PRESERVATION — this opens REAL device databases. A wrong
/// migration list or version silently breaks device tests. The migration
/// sequence below is the COMPLETE, schema-correct order (001-026, 043, 044,
/// 075, 077, 079) and is identical to the inline opener in
/// `transport_e2e_test.dart` (version 79). Lower-version call sites (the
/// `routing_smoke_*` and `transport_census` harnesses at version 44) get the
/// EXACT same schema they had inline, because the create/upgrade paths gate
/// 075/077/079 behind the requested [version] using the standard
/// `if (oldVersion < N)` idiom that every inline opener already used.
///
/// Public API (drop-in for the inline `_openDb` / `_deleteTestDatabase`):
///   * [openE2EDatabase] — opens (and recreates fresh) the encrypted test DB.
///   * [deleteTestDatabase] — deletes the DB file + its WAL/SHM/.encrypted
///     sidecars (superset-safe: missing sidecars are skipped).
///
/// DB name: callers pass [dbName] explicitly. The harnesses derive that name
/// from the `E2E_DB_NAME` dart-define (and per-test counters); this helper does
/// NOT read the dart-define itself so each call site keeps its existing
/// name-handling. See [defaultE2EDbName] for the shared default if needed.
library;

import 'dart:io';

import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';

// Canonical migration list — KEEP THE ORDER. This mirrors the inline opener in
// transport_e2e_test.dart (the most current / complete inline copy).
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/006_read_at_column.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/migrations/009_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/011_avatar_version.dart';
import 'package:flutter_app/core/database/migrations/012_transport_column.dart';
import 'package:flutter_app/core/database/migrations/013_waveform_column.dart';
import 'package:flutter_app/core/database/migrations/014_wire_envelope_column.dart';
import 'package:flutter_app/core/database/migrations/015_message_status_cleanup.dart';
import 'package:flutter_app/core/database/migrations/016_message_reactions.dart';
import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/019_introductions_table.dart';
import 'package:flutter_app/core/database/migrations/020_intro_banner_columns.dart';
import 'package:flutter_app/core/database/migrations/021_contact_introduced_by.dart';
import 'package:flutter_app/core/database/migrations/022_introduction_keys.dart';
import 'package:flutter_app/core/database/migrations/023_introduction_recipient_keys.dart';
import 'package:flutter_app/core/database/migrations/024_contact_introduced_by_peer_id.dart';
import 'package:flutter_app/core/database/migrations/025_introduction_already_connected_status.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/043_messages_edited_at.dart';
import 'package:flutter_app/core/database/migrations/044_messages_deleted_state.dart';
import 'package:flutter_app/core/database/migrations/075_contacts_ml_kem_key_updated_ts.dart';
import 'package:flutter_app/core/database/migrations/077_message_relay_custody.dart';
import 'package:flutter_app/core/database/migrations/079_message_dedup_key.dart';

/// Default DB-schema version for the canonical bootstrap. This matches the
/// current production migration head used by `transport_e2e_test.dart` and
/// `wifi_relay_fallback_smoke_test.dart`. Lower-version harnesses MUST pass
/// their own [version] (e.g. 44) so the schema is preserved exactly.
const int kCanonicalE2EDbVersion = 79;

/// The shared default DB-name dart-define key (`E2E_DB_NAME`). Provided for
/// reference; call sites read the dart-define themselves and pass [dbName].
const String kE2EDbNameDefine = 'E2E_DB_NAME';

/// Convenience default DB name read from the `E2E_DB_NAME` dart-define.
const String defaultE2EDbName = String.fromEnvironment(
  kE2EDbNameDefine,
  defaultValue: 'e2e_test.db',
);

/// Runs the canonical onCreate migration sequence up to [version].
///
/// Each migration past the v44 head is gated on [version] so a v44 caller
/// gets the exact v44 schema (no 075/077/079) while a v79 caller gets the full
/// schema. This is the same gating the inline `onUpgrade` callbacks used.
Future<void> _runCreateMigrations(sqlcipher.Database db, int version) async {
  await runIdentityTableMigration(db);
  await runMessagesTableMigration(db);
  await runMlKemKeysMigration(db);
  await runSecretNullChecksMigration(db);
  await runReadAtColumnMigration(db);
  await runArchiveColumnsMigration(db);
  await runBlockColumnsMigration(db);
  await runQuotedMessageIdMigration(db);
  await runMediaAttachmentsMigration(db);
  await runAvatarVersionMigration(db);
  await runTransportColumnMigration(db);
  await runWaveformColumnMigration(db);
  await runWireEnvelopeMigration(db);
  await runMessageStatusCleanupMigration(db);
  await runMessageReactionsMigration(db);
  await runGroupsTablesMigration(db);
  await runGroupMessagesTablesMigration(db);
  await runIntroductionsTableMigration(db);
  await runIntroBannerColumnsMigration(db);
  await runContactIntroducedByMigration(db);
  await runIntroductionKeysMigration(db);
  await runIntroductionRecipientKeysMigration(db);
  await runContactIntroducedByPeerIdMigration(db);
  await runIntroductionAlreadyConnectedMigration(db);
  await runGroupQuotedMessageIdMigration(db);
  await runMessagesEditedAtMigration(db);
  await runMessagesDeletedStateMigration(db);
  // Migrations introduced after v44 — gated so v44 callers keep their schema.
  if (version >= 75) await runContactsMlKemKeyUpdatedTsMigration(db);
  if (version >= 77) await runMessageRelayCustodyMigration(db);
  if (version >= 79) await runMessageDedupKeyMigration(db);
}

/// Runs the canonical onUpgrade migration sequence (standard `oldVersion <`
/// gating). Bounded by [version] so the same gating applies on upgrade.
Future<void> _runUpgradeMigrations(
  sqlcipher.Database db,
  int oldVersion,
  int version,
) async {
  if (oldVersion < 2) await runMessagesTableMigration(db);
  if (oldVersion < 3) await runMlKemKeysMigration(db);
  if (oldVersion < 5) await runSecretNullChecksMigration(db);
  if (oldVersion < 6) await runReadAtColumnMigration(db);
  if (oldVersion < 7) await runArchiveColumnsMigration(db);
  if (oldVersion < 8) await runBlockColumnsMigration(db);
  if (oldVersion < 9) await runQuotedMessageIdMigration(db);
  if (oldVersion < 10) await runMediaAttachmentsMigration(db);
  if (oldVersion < 11) await runAvatarVersionMigration(db);
  if (oldVersion < 12) await runTransportColumnMigration(db);
  if (oldVersion < 13) await runWaveformColumnMigration(db);
  if (oldVersion < 14) await runWireEnvelopeMigration(db);
  if (oldVersion < 15) await runMessageStatusCleanupMigration(db);
  if (oldVersion < 16) await runMessageReactionsMigration(db);
  if (oldVersion < 17) await runGroupsTablesMigration(db);
  if (oldVersion < 18) await runGroupMessagesTablesMigration(db);
  if (oldVersion < 19) await runIntroductionsTableMigration(db);
  if (oldVersion < 20) await runIntroBannerColumnsMigration(db);
  if (oldVersion < 21) await runContactIntroducedByMigration(db);
  if (oldVersion < 22) await runIntroductionKeysMigration(db);
  if (oldVersion < 23) await runIntroductionRecipientKeysMigration(db);
  if (oldVersion < 24) await runContactIntroducedByPeerIdMigration(db);
  if (oldVersion < 25) await runIntroductionAlreadyConnectedMigration(db);
  if (oldVersion < 26) await runGroupQuotedMessageIdMigration(db);
  if (oldVersion < 43) await runMessagesEditedAtMigration(db);
  if (oldVersion < 44) await runMessagesDeletedStateMigration(db);
  if (version >= 75 && oldVersion < 75) {
    await runContactsMlKemKeyUpdatedTsMigration(db);
  }
  if (version >= 77 && oldVersion < 77) {
    await runMessageRelayCustodyMigration(db);
  }
  if (version >= 79 && oldVersion < 79) {
    await runMessageDedupKeyMigration(db);
  }
}

/// Deletes the test database file plus its SQLCipher sidecars
/// (`-wal`, `-shm`, `.encrypted`). Missing sidecars are skipped, so this is a
/// safe superset of the inline `_deleteTestDatabase` variants (some inline
/// copies omitted `.encrypted`; deleting a nonexistent file is a no-op).
///
/// Drop-in replacement for the inline `_deleteTestDatabase(String dbName)`.
Future<void> deleteTestDatabase(String dbName) async {
  try {
    final dbPath = await sqlcipher.getDatabasesPath();
    final fullPath = '$dbPath/$dbName';
    for (final path in [
      fullPath,
      '$fullPath-wal',
      '$fullPath-shm',
      '$fullPath.encrypted',
    ]) {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    await sqlcipher.deleteDatabase(fullPath);
  } catch (_) {}
}

/// Opens a fresh encrypted test database with the canonical migration list.
///
/// This deletes any pre-existing DB file first (matching the inline `_openDb`,
/// which always recreated a fresh DB before opening), then opens via
/// [openEncryptedDatabase] with the same SQLCipher flags.
///
/// Drop-in replacement for the inline `_openDb(SecureKeyStore keyStore)` /
/// `_openTestDatabase(SecureKeyStore, String)` / `_setupStack`-inline opener.
///
/// * [secureKeyStore] — the (fake) secure key store the harness already builds.
/// * [dbName] — the per-role DB file name (callers derive this from the
///   `E2E_DB_NAME` dart-define and any per-test counter).
/// * [version] — the schema version. Defaults to [kCanonicalE2EDbVersion]
///   (79). Pass `44` to reproduce the routing_smoke / transport_census schema
///   exactly (no 075/077/079).
Future<sqlcipher.Database> openE2EDatabase({
  required SecureKeyStore secureKeyStore,
  required String dbName,
  int version = kCanonicalE2EDbVersion,
}) async {
  await deleteTestDatabase(dbName);
  return openEncryptedDatabase(
    secureKeyStore: secureKeyStore,
    dbName: dbName,
    version: version,
    onCreate: (db, _) => _runCreateMigrations(db, version),
    onUpgrade: (db, oldVersion, _) =>
        _runUpgradeMigrations(db, oldVersion, version),
  );
}
