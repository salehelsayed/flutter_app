import 'dart:typed_data';

import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Secure-storage key constants for the three critical secrets.
const String _kPrivateKey = 'identity_private_key';
const String _kMnemonic12 = 'identity_mnemonic12';
const String _kMlKemSecretKey = 'identity_ml_kem_secret_key';

class IdentityRepositoryImpl implements IdentityRepository {
  final Future<Map<String, Object?>?> Function() _dbLoadIdentityRow;
  final Future<void> Function(Map<String, Object?> row) _dbUpsertIdentityRow;
  final SecureKeyStore _secureKeyStore;

  IdentityRepositoryImpl({
    required Future<Map<String, Object?>?> Function() dbLoadIdentityRow,
    required Future<void> Function(Map<String, Object?> row) dbUpsertIdentityRow,
    required SecureKeyStore secureKeyStore,
  })  : _dbLoadIdentityRow = dbLoadIdentityRow,
        _dbUpsertIdentityRow = dbUpsertIdentityRow,
        _secureKeyStore = secureKeyStore;

  @override
  Future<IdentityModel?> loadIdentity() async {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_REPO_LOAD_IDENTITY_CALL',
      details: {},
    );

    final row = await _dbLoadIdentityRow();

    if (row == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ID_REPO_LOAD_IDENTITY_NOT_FOUND',
        details: {},
      );
      return null;
    }

    // Read secrets from secure storage, fall back to DB columns (pre-migration)
    final ssPrivateKey = await _secureKeyStore.read(_kPrivateKey);
    final ssMnemonic12 = await _secureKeyStore.read(_kMnemonic12);
    final ssMlKemSecretKey = await _secureKeyStore.read(_kMlKemSecretKey);

    final privateKey = ssPrivateKey ?? row['private_key'] as String?;
    final mnemonic12 = ssMnemonic12 ?? row['mnemonic12'] as String?;
    final mlKemSecretKey = ssMlKemSecretKey ?? row['ml_kem_secret_key'] as String?;

    print('[EAR] loadIdentity secret sources:');
    print('[EAR]   private_key  from: ${ssPrivateKey != null ? "SECURE STORAGE" : (row['private_key'] != null ? "DB FALLBACK" : "MISSING")}');
    print('[EAR]   mnemonic12   from: ${ssMnemonic12 != null ? "SECURE STORAGE" : (row['mnemonic12'] != null ? "DB FALLBACK" : "MISSING")}');
    print('[EAR]   mlkem_secret from: ${ssMlKemSecretKey != null ? "SECURE STORAGE" : (row['ml_kem_secret_key'] != null ? "DB FALLBACK" : "n/a")}');
    print('[EAR]   DB private_key column: ${row['private_key'] == null ? "NULL (good)" : "HAS VALUE (pre-migration)"}');
    print('[EAR]   DB mnemonic12 column:  ${row['mnemonic12'] == null ? "NULL (good)" : "HAS VALUE (pre-migration)"}');

    if (privateKey == null || mnemonic12 == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ID_REPO_LOAD_IDENTITY_MISSING_SECRETS',
        details: {'peerId': row['peer_id'] as String},
      );
      return null;
    }

    final identity = IdentityModel(
      peerId: row['peer_id'] as String,
      publicKey: row['public_key'] as String,
      privateKey: privateKey,
      mnemonic12: mnemonic12,
      mlKemPublicKey: row['ml_kem_public_key'] as String?,
      mlKemSecretKey: mlKemSecretKey,
      username: row['username'] as String? ?? 'Username',
      avatarBlob: row['avatar_blob'] as Uint8List?,
      createdAt: row['created_at'] as String,
      updatedAt: row['updated_at'] as String,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'ID_REPO_LOAD_IDENTITY_FOUND',
      details: {'peerId': identity.peerId},
    );

    return identity;
  }

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_REPO_SAVE_IDENTITY_CALL',
      details: {'peerId': identity.peerId},
    );

    // Write secrets to secure storage
    await _secureKeyStore.write(_kPrivateKey, identity.privateKey);
    await _secureKeyStore.write(_kMnemonic12, identity.mnemonic12);
    if (identity.mlKemSecretKey != null) {
      await _secureKeyStore.write(_kMlKemSecretKey, identity.mlKemSecretKey!);
    }

    print('[EAR] saveIdentity: secrets written to SECURE STORAGE');
    print('[EAR]   private_key  → secure storage: YES');
    print('[EAR]   mnemonic12   → secure storage: YES');
    print('[EAR]   mlkem_secret → secure storage: ${identity.mlKemSecretKey != null ? "YES" : "n/a"}');
    print('[EAR]   DB columns will be: NULL (secrets NOT in DB)');

    // Write DB row with secret columns set to null
    final row = <String, Object?>{
      'peer_id': identity.peerId,
      'public_key': identity.publicKey,
      'private_key': null,
      'mnemonic12': null,
      'ml_kem_public_key': identity.mlKemPublicKey,
      'ml_kem_secret_key': null,
      'username': identity.username,
      'avatar_path': null,
      'avatar_blob': identity.avatarBlob,
      'created_at': identity.createdAt,
      'updated_at': identity.updatedAt,
    };

    await _dbUpsertIdentityRow(row);

    emitFlowEvent(
      layer: 'FL',
      event: 'ID_REPO_SAVE_IDENTITY_SUCCESS',
      details: {},
    );
  }
}
