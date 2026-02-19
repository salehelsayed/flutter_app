import 'package:sqflite_sqlcipher/sqflite.dart';

import 'secure_key_store.dart';
import '../utils/flow_event_emitter.dart';

/// Secure-storage key constants (same as identity_repository_impl.dart).
const String _kPrivateKey = 'identity_private_key';
const String _kMnemonic12 = 'identity_mnemonic12';
const String _kMlKemSecretKey = 'identity_ml_kem_secret_key';
const String _kSecretsMigrated = 'secrets_migrated';

/// One-time migration: copies secrets from DB columns to secure storage,
/// then nulls the DB columns.
///
/// Idempotent — safe to re-run if interrupted. Uses `secrets_migrated`
/// sentinel in secure storage to skip on subsequent launches.
Future<void> migrateSecretsToSecureStorage({
  required Database db,
  required SecureKeyStore secureKeyStore,
}) async {
  // Already migrated — fast exit
  if (await secureKeyStore.containsKey(_kSecretsMigrated)) {
    print('[EAR] Secrets migration: ALREADY DONE (sentinel found)');
    emitFlowEvent(
      layer: 'FL',
      event: 'SECRETS_MIGRATION_ALREADY_DONE',
      details: {},
    );
    return;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'SECRETS_MIGRATION_START',
    details: {},
  );

  // Load identity row
  final rows = await db.query('identity', where: 'id = ?', whereArgs: [1], limit: 1);

  if (rows.isEmpty) {
    // Fresh install — no identity yet, mark as migrated
    await secureKeyStore.write(_kSecretsMigrated, 'true');
    print('[EAR] Secrets migration: FRESH INSTALL (no identity row, sentinel set)');
    emitFlowEvent(
      layer: 'FL',
      event: 'SECRETS_MIGRATION_NO_IDENTITY',
      details: {},
    );
    return;
  }

  final row = rows.first;
  final privateKey = row['private_key'] as String?;
  final mnemonic12 = row['mnemonic12'] as String?;
  final mlKemSecretKey = row['ml_kem_secret_key'] as String?;

  // Copy secrets to secure storage (only if present in DB)
  if (privateKey != null) {
    await secureKeyStore.write(_kPrivateKey, privateKey);
  }
  if (mnemonic12 != null) {
    await secureKeyStore.write(_kMnemonic12, mnemonic12);
  }
  if (mlKemSecretKey != null) {
    await secureKeyStore.write(_kMlKemSecretKey, mlKemSecretKey);
  }

  // Null out secret columns in DB
  await db.update(
    'identity',
    {
      'private_key': null,
      'mnemonic12': null,
      'ml_kem_secret_key': null,
    },
    where: 'id = ?',
    whereArgs: [1],
  );

  // Set sentinel
  await secureKeyStore.write(_kSecretsMigrated, 'true');

  print('[EAR] Secrets migration: COMPLETE');
  print('[EAR]   private_key  → secure storage: ${privateKey != null ? "YES" : "n/a (was null)"}');
  print('[EAR]   mnemonic12   → secure storage: ${mnemonic12 != null ? "YES" : "n/a (was null)"}');
  print('[EAR]   mlkem_secret → secure storage: ${mlKemSecretKey != null ? "YES" : "n/a (was null)"}');
  print('[EAR]   DB columns nulled: YES');

  emitFlowEvent(
    layer: 'FL',
    event: 'SECRETS_MIGRATION_SUCCESS',
    details: {},
  );
}
