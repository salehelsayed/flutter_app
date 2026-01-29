import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

class IdentityRepositoryImpl implements IdentityRepository {
  final Future<Map<String, Object?>?> Function() _dbLoadIdentityRow;
  final Future<void> Function(Map<String, Object?> row) _dbUpsertIdentityRow;

  IdentityRepositoryImpl({
    required Future<Map<String, Object?>?> Function() dbLoadIdentityRow,
    required Future<void> Function(Map<String, Object?> row) dbUpsertIdentityRow,
  })  : _dbLoadIdentityRow = dbLoadIdentityRow,
        _dbUpsertIdentityRow = dbUpsertIdentityRow;

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

    final identity = IdentityModel(
      peerId: row['peer_id'] as String,
      publicKey: row['public_key'] as String,
      privateKey: row['private_key'] as String,
      mnemonic12: row['mnemonic12'] as String,
      username: row['username'] as String? ?? 'Username',
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

    final row = <String, Object?>{
      'peer_id': identity.peerId,
      'public_key': identity.publicKey,
      'private_key': identity.privateKey,
      'mnemonic12': identity.mnemonic12,
      'username': identity.username,
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
