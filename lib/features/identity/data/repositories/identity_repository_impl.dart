import 'dart:typed_data';

import 'package:flutter_app/core/notifications/canonical_recovery_authority_storage_keys.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/group_reaction_notification_projection.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/core/secure_storage/ml_kem_secret_ring.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

export 'package:flutter_app/core/notifications/canonical_recovery_authority_storage_keys.dart'
    show identityPrivateKeyStorageKey;

/// Secure-storage key constants for the three critical secrets.
const String identityMnemonic12StorageKey = 'identity_mnemonic12';
const String identityMlKemSecretKeyStorageKey = 'identity_ml_kem_secret_key';

/// Loads the committed identity and its secure secrets without publishing,
/// rebinding, mirroring, caching, or writing any projection.
///
/// The foreground repository deliberately wraps this passive decoder with its
/// existing projection/binding side effects. The production headless graph
/// calls it directly after acquiring the lease and opening the existing DB.
Future<IdentityModel?> loadPassiveIdentitySnapshot({
  required Future<Map<String, Object?>?> Function() dbLoadIdentityRow,
  required SecureKeyStore secureKeyStore,
}) async {
  final row = await dbLoadIdentityRow();
  if (row == null) return null;
  return decodePassiveIdentitySnapshot(
    row: row,
    secureKeyStore: secureKeyStore,
  );
}

Future<IdentityModel?> decodePassiveIdentitySnapshot({
  required Map<String, Object?> row,
  required SecureKeyStore secureKeyStore,
}) async {
  final secureValues = await Future.wait<String?>([
    secureKeyStore.read(identityPrivateKeyStorageKey),
    secureKeyStore.read(identityMnemonic12StorageKey),
    secureKeyStore.read(identityMlKemSecretKeyStorageKey),
  ]);
  final privateKey = secureValues[0] ?? row['private_key'] as String?;
  final mnemonic12 = secureValues[1] ?? row['mnemonic12'] as String?;
  final mlKemSecretKey = secureValues[2] ?? row['ml_kem_secret_key'] as String?;
  if (privateKey == null || mnemonic12 == null) return null;

  return IdentityModel(
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
}

class IdentityRepositoryImpl implements IdentityRepository {
  final Future<Map<String, Object?>?> Function() _dbLoadIdentityRow;
  final Future<void> Function(Map<String, Object?> row) _dbUpsertIdentityRow;
  final SecureKeyStore _secureKeyStore;
  final SecureKeyStore? _pushSharedKeyStore;
  final DirectReactionNotificationProjection? _directReactionProjection;
  final GroupReactionNotificationProjection? _groupReactionProjection;
  final Future<void> Function(String accountPeerId)?
  _publishCanonicalAccountBinding;
  final Future<void> Function()? _retireCanonicalAccountBinding;
  final Future<void> Function()? _retireIosNseInboxTransport;
  final Future<void> Function(IdentityModel identity)?
  _refreshIosNseInboxTransport;
  IdentityModel? _cachedIdentity;
  bool _hasCachedIdentity = false;

  IdentityRepositoryImpl({
    required Future<Map<String, Object?>?> Function() dbLoadIdentityRow,
    required Future<void> Function(Map<String, Object?> row)
    dbUpsertIdentityRow,
    required SecureKeyStore secureKeyStore,
    SecureKeyStore? pushSharedKeyStore,
    DirectReactionNotificationProjection? directReactionProjection,
    GroupReactionNotificationProjection? groupReactionProjection,
    Future<void> Function(String accountPeerId)? publishCanonicalAccountBinding,
    Future<void> Function()? retireCanonicalAccountBinding,
    Future<void> Function()? retireIosNseInboxTransport,
    Future<void> Function(IdentityModel identity)? refreshIosNseInboxTransport,
  }) : _dbLoadIdentityRow = dbLoadIdentityRow,
       _dbUpsertIdentityRow = dbUpsertIdentityRow,
       _secureKeyStore = secureKeyStore,
       _pushSharedKeyStore = pushSharedKeyStore,
       _directReactionProjection = directReactionProjection,
       _groupReactionProjection = groupReactionProjection,
       _publishCanonicalAccountBinding = publishCanonicalAccountBinding,
       _retireCanonicalAccountBinding = retireCanonicalAccountBinding,
       _retireIosNseInboxTransport = retireIosNseInboxTransport,
       _refreshIosNseInboxTransport = refreshIosNseInboxTransport;

  void invalidateCache() {
    _cachedIdentity = null;
    _hasCachedIdentity = false;
  }

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
        details: cachedIdentity == null
            ? {}
            : {'peerId': cachedIdentity.peerId},
      );
      return cachedIdentity;
    }

    // An uncached load can cross account/private-key generations after a cold
    // start or import. Retire the old physical credential before reading the
    // authoritative row; the qualified node start republishes only committed
    // current bytes.
    await _retireIosNseInboxTransport?.call();

    final row = await _dbLoadIdentityRow();

    if (row == null) {
      await _groupReactionProjection?.clearForLogout();
      await _directReactionProjection?.clearForLogout();
      await _retireCanonicalAccountBinding?.call();
      _cachedIdentity = null;
      _hasCachedIdentity = true;
      emitFlowEvent(
        layer: 'FL',
        event: 'ID_REPO_LOAD_IDENTITY_NOT_FOUND',
        details: {},
      );
      return null;
    }

    // Publish an empty new-owner group generation first so old group and
    // announcement routes become ineligible immediately. Then replace direct
    // documents: any old direct owner mismatches the new group identity until
    // both empty direct documents are committed. All of this precedes secret
    // reads and DB publication.
    await _groupReactionProjection?.replaceLocalIdentity(
      accountPeerId: row['peer_id'] as String,
      deviceId: row['peer_id'] as String,
      transportPeerId: row['peer_id'] as String,
    );
    await _directReactionProjection?.replaceLocalIdentity(
      accountPeerId: row['peer_id'] as String,
    );

    // Read secrets from secure storage in parallel, fall back to DB columns (pre-migration)
    final identity = await decodePassiveIdentitySnapshot(
      row: row,
      secureKeyStore: _secureKeyStore,
    );

    if (identity == null) {
      await _groupReactionProjection?.clearForLogout();
      await _directReactionProjection?.clearForLogout();
      await _retireCanonicalAccountBinding?.call();
      _cachedIdentity = null;
      _hasCachedIdentity = true;
      emitFlowEvent(
        layer: 'FL',
        event: 'ID_REPO_LOAD_IDENTITY_MISSING_SECRETS',
        details: {'peerId': row['peer_id'] as String},
      );
      return null;
    }

    await _mirrorMlKemSecretForPush(identity.mlKemSecretKey);
    await _publishCanonicalAccountBinding?.call(identity.peerId);
    await _refreshIosNseInboxTransport?.call(identity);
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

    // Identity/account-key replacement is also a physical inbox-authority
    // boundary. A failed retirement aborts before secrets or SQL change.
    await _retireIosNseInboxTransport?.call();

    // Make every old group/announcement route ineligible first, then bind the
    // empty direct documents. These transitions happen before secrets or DB so
    // a later save failure remains fail-closed for both notification families.
    await _groupReactionProjection?.replaceLocalIdentity(
      accountPeerId: identity.peerId,
      deviceId: identity.peerId,
      transportPeerId: identity.peerId,
    );
    await _directReactionProjection?.replaceLocalIdentity(
      accountPeerId: identity.peerId,
    );

    // Write secrets to secure storage
    await _secureKeyStore.write(
      identityPrivateKeyStorageKey,
      identity.privateKey,
    );
    await _secureKeyStore.write(
      identityMnemonic12StorageKey,
      identity.mnemonic12,
    );
    if (identity.mlKemSecretKey != null) {
      // P0-B: before overwriting with a DIFFERENT secret, preserve the old
      // one on the ring so already-in-flight traffic encrypted to the old
      // public key stays decryptable on this device.
      final previousSecret = await _secureKeyStore.read(
        identityMlKemSecretKeyStorageKey,
      );
      if (previousSecret != null &&
          previousSecret.isNotEmpty &&
          previousSecret != identity.mlKemSecretKey) {
        await pushMlKemSecretKeyRing(_secureKeyStore, previousSecret);
      }
      await _secureKeyStore.write(
        identityMlKemSecretKeyStorageKey,
        identity.mlKemSecretKey!,
      );
    }
    await _mirrorMlKemSecretForPush(identity.mlKemSecretKey);

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
    await _publishCanonicalAccountBinding?.call(identity.peerId);
    // Republish only after the identity and binding are committed. When no
    // node is qualified yet this remains absent until node start; when a live
    // qualified node exists, profile/account-key saves restore exact current
    // transport bytes immediately. Failure deliberately leaves it retired.
    await _refreshIosNseInboxTransport?.call(identity);
    _cachedIdentity = identity;
    _hasCachedIdentity = true;

    emitFlowEvent(
      layer: 'FL',
      event: 'ID_REPO_SAVE_IDENTITY_SUCCESS',
      details: {},
    );
  }

  Future<void> _mirrorMlKemSecretForPush(String? mlKemSecretKey) async {
    final pushSharedKeyStore = _pushSharedKeyStore;
    if (pushSharedKeyStore == null) {
      return;
    }
    try {
      if (mlKemSecretKey == null) {
        await pushSharedKeyStore.delete(identityMlKemSecretKeyStorageKey);
      } else {
        await pushSharedKeyStore.write(
          identityMlKemSecretKeyStorageKey,
          mlKemSecretKey,
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ID_REPO_PUSH_SECRET_MIRROR_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
