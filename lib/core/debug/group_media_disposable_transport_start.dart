import 'dart:convert';

import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/application/start_node_use_case.dart';

const String groupMediaDisposableTransportIdentityStorageKey =
    'group_media_269_transport_identity';
const String groupMediaDisposableTransportIdentitySchema =
    'mknoon.group-media-269-transport-identity.v1';

typedef GenerateGroupMediaDisposableTransportIdentity =
    Future<Map<String, dynamic>> Function();
typedef StartGroupMediaDisposableTransportNode =
    Future<bool> Function(String privateKeyBase64, String peerId);
typedef ReadGroupMediaDisposableTransportPeerId = String? Function();

bool isGroupMediaDisposableTransportProfile(String profileId) =>
    profileId == groupMediaAndroidDisposableBuildProfile ||
    profileId == groupMediaIosDisposableBuildProfile;

/// Starts the dedicated P269 profiles with a stable transport identity that is
/// distinct from the logical account identity.
///
/// The transport credential pair is persisted as one account-bound secure
/// storage document. An existing document is never repaired or replaced: a
/// malformed document or an account-binding mismatch fails closed so a
/// disposable-profile reset remains the only way to change its authority.
Future<StartNodeResult> startGroupMediaDisposableTransportNode({
  required IdentityRepository identityRepository,
  required SecureKeyStore secureKeyStore,
  required GenerateGroupMediaDisposableTransportIdentity generateIdentity,
  required StartGroupMediaDisposableTransportNode startNode,
  required ReadGroupMediaDisposableTransportPeerId currentTransportPeerId,
  AccountMigrationNetworkGate accountMigrationNetworkGate =
      allowAccountMigrationNetworkSideEffects,
  String installedProfileId = const String.fromEnvironment(
    'SIMS_BUILD_PROFILE_ID',
  ),
}) async {
  if (!isGroupMediaDisposableTransportProfile(installedProfileId)) {
    return StartNodeResult.bridgeError;
  }

  try {
    final accountIdentity = await identityRepository.loadIdentity();
    if (accountIdentity == null) {
      return StartNodeResult.noIdentity;
    }

    final migrationAllowsNetwork = await accountMigrationNetworkGate(
      peerId: accountIdentity.peerId,
      operation: 'p2p_start',
    );
    if (!migrationAllowsNetwork) {
      return StartNodeResult.accountMigrationBlocked;
    }

    final storedDocument = await secureKeyStore.read(
      groupMediaDisposableTransportIdentityStorageKey,
    );
    late final _DisposableTransportCredentials credentials;
    if (storedDocument == null) {
      final generated = await generateIdentity();
      final generatedCredentials = _credentialsFromGeneratedIdentity(
        generated,
        accountPeerId: accountIdentity.peerId,
      );
      if (generatedCredentials == null) {
        return StartNodeResult.bridgeError;
      }
      credentials = generatedCredentials;
      await secureKeyStore.write(
        groupMediaDisposableTransportIdentityStorageKey,
        credentials.toStoredDocument(accountPeerId: accountIdentity.peerId),
      );
    } else {
      final restoredCredentials = _credentialsFromStoredDocument(
        storedDocument,
        accountPeerId: accountIdentity.peerId,
      );
      if (restoredCredentials == null) {
        return StartNodeResult.bridgeError;
      }
      credentials = restoredCredentials;
    }

    final started = await startNode(
      credentials.privateKeyBase64,
      credentials.peerId,
    );
    if (!started) {
      return StartNodeResult.bridgeError;
    }

    final currentPeerId = currentTransportPeerId()?.trim();
    if (currentPeerId == null ||
        currentPeerId.isEmpty ||
        currentPeerId == accountIdentity.peerId ||
        currentPeerId != credentials.peerId) {
      return StartNodeResult.bridgeError;
    }
    return StartNodeResult.success;
  } catch (_) {
    return StartNodeResult.bridgeError;
  }
}

_DisposableTransportCredentials? _credentialsFromGeneratedIdentity(
  Map<String, dynamic> response, {
  required String accountPeerId,
}) {
  if (response['ok'] != true) {
    return null;
  }
  final identity = response['identity'];
  if (identity is! Map) {
    return null;
  }
  return _validatedCredentials(
    peerId: identity['peerId'],
    privateKeyBase64: identity['privateKey'],
    accountPeerId: accountPeerId,
  );
}

_DisposableTransportCredentials? _credentialsFromStoredDocument(
  String storedDocument, {
  required String accountPeerId,
}) {
  try {
    final decoded = jsonDecode(storedDocument);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 4 ||
        decoded['schema'] != groupMediaDisposableTransportIdentitySchema ||
        decoded['accountPeerId'] != accountPeerId) {
      return null;
    }
    return _validatedCredentials(
      peerId: decoded['transportPeerId'],
      privateKeyBase64: decoded['transportPrivateKey'],
      accountPeerId: accountPeerId,
    );
  } catch (_) {
    return null;
  }
}

_DisposableTransportCredentials? _validatedCredentials({
  required Object? peerId,
  required Object? privateKeyBase64,
  required String accountPeerId,
}) {
  if (peerId is! String || privateKeyBase64 is! String) {
    return null;
  }
  final normalizedPeerId = peerId.trim();
  final normalizedPrivateKey = privateKeyBase64.trim();
  if (normalizedPeerId.isEmpty ||
      normalizedPrivateKey.isEmpty ||
      normalizedPeerId != peerId ||
      normalizedPrivateKey != privateKeyBase64 ||
      normalizedPeerId == accountPeerId) {
    return null;
  }
  return _DisposableTransportCredentials(
    peerId: normalizedPeerId,
    privateKeyBase64: normalizedPrivateKey,
  );
}

final class _DisposableTransportCredentials {
  const _DisposableTransportCredentials({
    required this.peerId,
    required this.privateKeyBase64,
  });

  final String peerId;
  final String privateKeyBase64;

  String toStoredDocument({required String accountPeerId}) =>
      jsonEncode(<String, String>{
        'schema': groupMediaDisposableTransportIdentitySchema,
        'accountPeerId': accountPeerId,
        'transportPeerId': peerId,
        'transportPrivateKey': privateKeyBase64,
      });

  @override
  String toString() => '_DisposableTransportCredentials(redacted)';
}
