import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_app/core/notifications/canonical_recovery_authority_storage_keys.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';

import 'secure_key_store.dart';

/// The resolved `keychain-access-groups` entitlement shared by Runner and the
/// notification service extension. `flutter_secure_storage` forwards this
/// value directly to `kSecAttrAccessGroup`, so the AppIdentifierPrefix must be
/// present; the raw App Group identifier is not a valid Keychain access group.
const mknoonSharedAppleAccessGroup = '397R9Q4WMX.group.com.mknoon.app.share';

/// Production [SecureKeyStore] backed by flutter_secure_storage.
///
/// Uses iOS Keychain on iOS and EncryptedSharedPreferences on Android.
/// - iOS: kSecAttrAccessibleWhenUnlockedThisDeviceOnly — keys stay on-device,
///   inaccessible while locked, excluded from iCloud/iTunes backups.
/// - Android: EncryptedSharedPreferences backed by Android Keystore.
class FlutterSecureKeyStore implements SecureKeyStore {
  final FlutterSecureStorage _storage;
  final String? appleAccessGroup;
  final DroppedPushRecoveryAuthorityMutationPublisher?
  _authorityMutationPublisher;

  FlutterSecureKeyStore({
    this.appleAccessGroup,
    DroppedPushRecoveryAuthorityMutationPublisher? authorityMutationPublisher,
  }) : _storage = FlutterSecureStorage(
         aOptions: AndroidOptions(encryptedSharedPreferences: true),
         iOptions: IOSOptions(
           accessibility: KeychainAccessibility.first_unlock_this_device,
           groupId: appleAccessGroup,
         ),
       ),
       _authorityMutationPublisher =
           authorityMutationPublisher ??
           (defaultTargetPlatform == TargetPlatform.android
               ? DroppedPushRecoveryBridge()
               : null);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _mutate(
    key: key,
    operation: 'write',
    action: () => _storage.write(key: key, value: value),
  );

  @override
  Future<void> delete(String key) => _mutate(
    key: key,
    operation: 'delete',
    action: () => _storage.delete(key: key),
  );

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);

  /// Bounded harness support for a dedicated disposable application namespace.
  /// Production code must continue to use key-specific deletes.
  Future<void> deleteAll() => _mutate(
    key: canonicalRuntimeAccountBindingStorageKey,
    operation: 'delete_all',
    action: _storage.deleteAll,
  );

  /// Read-back used to prove the dedicated namespace is empty after reset.
  Future<Map<String, String>> readAll() => _storage.readAll();

  Future<void> _mutate({
    required String key,
    required String operation,
    required Future<void> Function() action,
  }) async {
    final publisher = _authorityMutationPublisher;
    if (publisher == null || !isCanonicalRecoveryAuthorityStorageKey(key)) {
      await action();
      return;
    }

    final begin = await publisher.beginRecoveryAuthorityMutation();
    if (!begin.isCommittedBegin) {
      throw CanonicalRecoveryAuthorityMutationException(
        operation: operation,
        phase: 'begin',
      );
    }
    final token = begin.token!;
    Object? actionError;
    StackTrace? actionStackTrace;
    try {
      await action();
    } catch (error, stackTrace) {
      actionError = error;
      actionStackTrace = stackTrace;
    }

    final finish = await publisher.finishRecoveryAuthorityMutation(token);
    if (!finish.isCommittedFinish) {
      throw CanonicalRecoveryAuthorityMutationException(
        operation: operation,
        phase: 'finish',
        primaryError: actionError,
      );
    }
    if (actionError != null) {
      Error.throwWithStackTrace(
        actionError,
        actionStackTrace ?? StackTrace.current,
      );
    }
  }
}

final class CanonicalRecoveryAuthorityMutationException implements Exception {
  const CanonicalRecoveryAuthorityMutationException({
    required this.operation,
    required this.phase,
    this.primaryError,
  });

  final String operation;
  final String phase;
  final Object? primaryError;

  @override
  String toString() =>
      'CanonicalRecoveryAuthorityMutationException('
      'operation: $operation, phase: $phase, '
      'primaryError: $primaryError)';
}
