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
  IdentityModel? _cachedIdentity;
  bool _hasCachedIdentity = false;

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

    if (_hasCachedIdentity) {
      final cachedIdentity = _cachedIdentity;
      emitFlowEvent(
        layer: 'FL',
        event: cachedIdentity == null
            ? 'ID_REPO_LOAD_IDENTITY_NOT_FOUND'
            : 'ID_REPO_LOAD_IDENTITY_FOUND',
        details: cachedIdentity == null ? {} : {'peerId': cachedIdentity.peerId},
      );
      return cachedIdentity;
    }

    final row = await _dbLoadIdentityRow();

    if (row == null) {
      _cachedIdentity = null;
      _hasCachedIdentity = true;
      emitFlowEvent(
        layer: 'FL',
        event: 'ID_REPO_LOAD_IDENTITY_NOT_FOUND',
        details: {},
      );
      return null;
    }

    // Read secrets from secure storage in parallel, fall back to DB columns (pre-migration)
    final ssResults = await Future.wait([
      _secureKeyStore.read(_kPrivateKey),
      _secureKeyStore.read(_kMnemonic12),
      _secureKeyStore.read(_kMlKemSecretKey),
    ]);
    final ssPrivateKey = ssResults[0];
    final ssMnemonic12 = ssResults[1];
    final ssMlKemSecretKey = ssResults[2];

    final privateKey = ssPrivateKey ?? row['private_key'] as String?;
    final mnemonic12 = ssMnemonic12 ?? row['mnemonic12'] as String?;
    final mlKemSecretKey = ssMlKemSecretKey ?? row['ml_kem_secret_key'] as String?;

    if (privateKey == null || mnemonic12 == null) {
      _cachedIdentity = null;
      _hasCachedIdentity = true;
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
      avatarVersion: row['avatar_version'] as String?,
      createdAt: row['created_at'] as String,
      updatedAt: row['updated_at'] as String,
    );
    _cachedIdentity = identity;
    _hasCachedIdentity = true;

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
      'avatar_version': identity.avatarVersion,
      'created_at': identity.createdAt,
      'updated_at': identity.updatedAt,
    };

    await _dbUpsertIdentityRow(row);
    _cachedIdentity = identity;
    _hasCachedIdentity = true;

    emitFlowEvent(
      layer: 'FL',
      event: 'ID_REPO_SAVE_IDENTITY_SUCCESS',
      details: {},
    );
  }
}
