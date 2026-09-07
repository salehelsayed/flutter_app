import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/notifications/canonical_recovery_authority_storage_keys.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:uuid/uuid.dart';

export 'canonical_recovery_authority_storage_keys.dart'
    show
        canonicalRuntimeAccountBindingStorageKey,
        canonicalRuntimeInstallationIdStorageKey,
        canonicalRuntimeSharedAccountBindingStorageKey;

final RegExp _canonicalRuntimeOpaqueBindingPattern = RegExp(
  r'^v1:[0-9a-f]{64}$',
);

bool isCanonicalRuntimeOpaqueBinding(Object? value) =>
    value is String &&
    value == value.trim() &&
    _canonicalRuntimeOpaqueBindingPattern.hasMatch(value);

enum CanonicalRuntimeLeaseState { active, draining, released }

final class CanonicalRuntimeLeaseSnapshot {
  const CanonicalRuntimeLeaseSnapshot({
    required this.state,
    required this.generation,
    required this.binding,
    required this.role,
    required this.maximumConcurrentWritableOwners,
  });

  final CanonicalRuntimeLeaseState state;
  final int? generation;
  final String? binding;
  final String? role;
  final int maximumConcurrentWritableOwners;

  factory CanonicalRuntimeLeaseSnapshot.fromPlatform(Object? value) {
    if (value is! Map) {
      throw const FormatException('canonical runtime lease returned no state');
    }
    final rawState = value['state'];
    final state = switch (rawState) {
      'ACTIVE' => CanonicalRuntimeLeaseState.active,
      'DRAINING' => CanonicalRuntimeLeaseState.draining,
      'RELEASED' => CanonicalRuntimeLeaseState.released,
      _ => throw FormatException('invalid canonical lease state: $rawState'),
    };
    final generation = value['generation'];
    final maximumOwners = value['maximumConcurrentWritableOwners'];
    return CanonicalRuntimeLeaseSnapshot(
      state: state,
      generation: generation is int && generation > 0 ? generation : null,
      binding: (value['binding'] as String?)?.trim(),
      role: value['role'] as String?,
      maximumConcurrentWritableOwners: maximumOwners is int
          ? maximumOwners
          : state == CanonicalRuntimeLeaseState.released
          ? 0
          : 1,
    );
  }
}

abstract interface class CanonicalRuntimeLeaseGateway {
  Future<CanonicalRuntimeLeaseSnapshot> acquire(String binding);

  Future<bool> attachRuntime();

  Future<CanonicalRuntimeLeaseSnapshot> rebind(String binding);

  Future<bool> beginDrain();

  Future<bool> quiesceRuntime();

  Future<bool> release({required bool databaseClosed});

  Future<CanonicalRuntimeLeaseSnapshot> status();
}

/// Engine-bound facade. Native fixes owner identity and role at registration;
/// Dart can neither impersonate another engine nor acquire the FCM read-only
/// engine as a writable owner.
final class MethodChannelCanonicalRuntimeLeaseGateway
    implements CanonicalRuntimeLeaseGateway {
  static const channelName = 'mknoon/canonical_runtime_lease';

  MethodChannelCanonicalRuntimeLeaseGateway({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<CanonicalRuntimeLeaseSnapshot> acquire(String binding) async {
    final normalized = _requiredBinding(binding);
    final value = await _channel.invokeMethod<Object?>('acquire', {
      'binding': normalized,
    });
    return CanonicalRuntimeLeaseSnapshot.fromPlatform(value);
  }

  @override
  Future<bool> attachRuntime() async =>
      await _channel.invokeMethod<bool>('attachRuntime') ?? false;

  @override
  Future<CanonicalRuntimeLeaseSnapshot> rebind(String binding) async {
    final normalized = _requiredBinding(binding);
    final value = await _channel.invokeMethod<Object?>('rebind', {
      'binding': normalized,
    });
    return CanonicalRuntimeLeaseSnapshot.fromPlatform(value);
  }

  @override
  Future<bool> beginDrain() async =>
      await _channel.invokeMethod<bool>('beginDrain') ?? false;

  @override
  Future<bool> quiesceRuntime() async =>
      await _channel.invokeMethod<bool>('quiesceRuntime') ?? false;

  @override
  Future<bool> release({required bool databaseClosed}) async =>
      await _channel.invokeMethod<bool>('release', {
        'databaseClosed': databaseClosed,
      }) ??
      false;

  @override
  Future<CanonicalRuntimeLeaseSnapshot> status() async {
    final value = await _channel.invokeMethod<Object?>('status');
    return CanonicalRuntimeLeaseSnapshot.fromPlatform(value);
  }

  String _requiredBinding(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'binding', 'must not be blank');
    }
    return normalized;
  }
}

/// Low-level lease lifecycle shared by foreground bootstrap and the H0 probe.
/// Recovery inbox orchestration lives in CanonicalRecoveryRuntime; this class
/// intentionally knows nothing about markers, drains, projection, or ack.
final class CanonicalWritableRuntimeSession {
  CanonicalWritableRuntimeSession({
    required CanonicalRuntimeLeaseGateway gateway,
  }) : _gateway = gateway;

  final CanonicalRuntimeLeaseGateway _gateway;
  CanonicalRuntimeLeaseState _state = CanonicalRuntimeLeaseState.released;
  bool _hasWritableLease = false;

  bool get hasWritableLease => _hasWritableLease;
  CanonicalRuntimeLeaseState get state => _state;

  Future<T> acquireThenOpen<T>({
    required String binding,
    required Future<T> Function() openDatabase,
    Future<bool> Function()? closeAfterOpenFailure,
    Future<bool> Function(T database)? closeDatabaseOnRuntimeAttachFailure,
  }) async {
    if (_hasWritableLease) {
      throw StateError('canonical writable runtime is already acquired');
    }
    final snapshot = await _gateway.acquire(binding);
    if (snapshot.state != CanonicalRuntimeLeaseState.active) {
      throw StateError('canonical writable lease did not become ACTIVE');
    }
    _hasWritableLease = true;
    _state = CanonicalRuntimeLeaseState.active;
    late final T database;
    try {
      database = await openDatabase();
    } catch (error, stackTrace) {
      final draining = await _gateway.beginDrain();
      if (draining) {
        _state = CanonicalRuntimeLeaseState.draining;
        var databaseClosed = false;
        if (closeAfterOpenFailure != null) {
          try {
            databaseClosed = await closeAfterOpenFailure();
          } catch (_) {
            databaseClosed = false;
          }
        }
        final released = await _gateway.release(databaseClosed: databaseClosed);
        if (released) {
          _hasWritableLease = false;
          _state = CanonicalRuntimeLeaseState.released;
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    Object? attachFailure;
    StackTrace? attachFailureStack;
    try {
      if (!await _gateway.attachRuntime()) {
        attachFailure = StateError(
          'Go runtime could not attach after SQLCipher opened',
        );
        attachFailureStack = StackTrace.current;
      }
    } catch (error, stackTrace) {
      attachFailure = error;
      attachFailureStack = stackTrace;
    }
    if (attachFailure != null) {
      final draining = await _gateway.beginDrain();
      if (draining) {
        _state = CanonicalRuntimeLeaseState.draining;
        var databaseClosed = false;
        var runtimeQuiescent = false;
        try {
          runtimeQuiescent = await _gateway.quiesceRuntime();
        } catch (_) {
          runtimeQuiescent = false;
        }
        if (runtimeQuiescent && closeDatabaseOnRuntimeAttachFailure != null) {
          try {
            databaseClosed = await closeDatabaseOnRuntimeAttachFailure(
              database,
            );
          } catch (_) {
            databaseClosed = false;
          }
        }
        final released = await _gateway.release(databaseClosed: databaseClosed);
        if (released) {
          _hasWritableLease = false;
          _state = CanonicalRuntimeLeaseState.released;
        }
      }
      Error.throwWithStackTrace(attachFailure, attachFailureStack!);
    }
    return database;
  }

  Future<CanonicalRuntimeLeaseSnapshot> rebind(String binding) async {
    if (!_hasWritableLease || _state != CanonicalRuntimeLeaseState.active) {
      throw StateError('only the ACTIVE writable owner can rotate binding');
    }
    return _gateway.rebind(binding);
  }

  /// Seals native Go admission for this exact owner and enters DRAINING.
  ///
  /// Headless recovery separates this cut from SQLCipher close so its Dart
  /// admission/listener fence and authoritative projection settlement can be
  /// proven before the process-wide runtime is stopped.
  Future<bool> beginDrain() async {
    if (!_hasWritableLease) return true;
    if (_state == CanonicalRuntimeLeaseState.draining) return true;
    if (_state != CanonicalRuntimeLeaseState.active) return false;
    final draining = await _gateway.beginDrain();
    if (draining) _state = CanonicalRuntimeLeaseState.draining;
    return draining;
  }

  /// Waits until the native Go owner reports fully quiescent after
  /// [beginDrain]. A false result deliberately keeps DRAINING ownership.
  Future<bool> awaitRuntimeQuiescence() async {
    if (!_hasWritableLease) return true;
    if (_state != CanonicalRuntimeLeaseState.draining) return false;
    return _gateway.quiesceRuntime();
  }

  /// Releases only after the caller has closed the exact SQLCipher handle.
  /// Passing false is an explicit fail-closed retention request.
  Future<bool> releaseAfterDatabaseClose({required bool databaseClosed}) async {
    if (!_hasWritableLease) return true;
    if (_state != CanonicalRuntimeLeaseState.draining) return false;
    final released = await _gateway.release(databaseClosed: databaseClosed);
    if (released) {
      _hasWritableLease = false;
      _state = CanonicalRuntimeLeaseState.released;
    }
    return released;
  }

  /// Ordered detach: reject new work, quiesce Go, close SQLCipher, then release.
  /// Any quiescence/close failure deliberately retains DRAINING ownership.
  Future<void> drainCloseRelease({
    required Future<void> Function() stopRuntime,
    required Future<void> Function() closeDatabase,
  }) async {
    if (!_hasWritableLease) return;
    if (!await beginDrain()) {
      throw StateError('canonical writable owner could not begin draining');
    }

    try {
      await stopRuntime();
    } catch (error, stackTrace) {
      await releaseAfterDatabaseClose(databaseClosed: false);
      Error.throwWithStackTrace(error, stackTrace);
    }

    if (!await awaitRuntimeQuiescence()) {
      await releaseAfterDatabaseClose(databaseClosed: false);
      throw StateError('canonical runtime did not quiesce');
    }

    var databaseClosed = false;
    try {
      await closeDatabase();
      databaseClosed = true;
    } catch (error, stackTrace) {
      await releaseAfterDatabaseClose(databaseClosed: false);
      Error.throwWithStackTrace(error, stackTrace);
    }
    final released = await releaseAfterDatabaseClose(
      databaseClosed: databaseClosed,
    );
    if (!released) {
      throw StateError('canonical writable lease release was rejected');
    }
  }
}

/// Documents and exposes the third-engine rule without creating a writable API.
final class FirebaseReadOnlyRuntimePolicy {
  const FirebaseReadOnlyRuntimePolicy();

  bool get mayAcquireWritableLease => false;
}

final class CanonicalRuntimeStartupBinding {
  const CanonicalRuntimeStartupBinding({
    required this.leaseBinding,
    required this.hasAccount,
  });

  final String leaseBinding;
  final bool hasAccount;
}

typedef CanonicalRuntimeOverlayRebind =
    Future<void> Function(String? opaqueBinding);
typedef CanonicalRuntimeLedgerRebind =
    Future<void> Function(String? opaqueBinding);
typedef CanonicalRuntimeLedgerClaimsSuspend =
    Future<void> Function(String? opaqueBinding);
typedef CanonicalRuntimeSharedBindingPublish =
    Future<void> Function(String? opaqueBinding);
typedef CanonicalRuntimeRemoteAnnouncementRebind =
    Future<void> Function(String? opaqueBinding);

/// Owns the device-local installation secret and opaque account digest.
/// Recovery work remains disabled by default and is enabled only by a caller
/// that explicitly declares the production headless graph registered.
final class CanonicalRuntimeBindingCoordinator {
  CanonicalRuntimeBindingCoordinator({
    required SecureKeyStore secureKeyStore,
    CanonicalRuntimeLeaseGateway? leaseGateway,
    DroppedPushRecoveryBindingPublisher? droppedPushBindingPublisher,
    CanonicalRuntimeOverlayRebind? rebindPendingNotificationOverlay,
    CanonicalRuntimeLedgerRebind? rebindLocalNotificationLedger,
    CanonicalRuntimeLedgerClaimsSuspend? suspendLocalNotificationLedgerClaims,
    CanonicalRuntimeSharedBindingPublish? publishSharedBinding,
    CanonicalRuntimeRemoteAnnouncementRebind? rebindRemoteAnnouncements,
    String Function()? createInstallationId,
    bool recoveryGraphRegistered = false,
  }) : _secureKeyStore = secureKeyStore,
       _leaseGateway = leaseGateway,
       _droppedPushBindingPublisher = droppedPushBindingPublisher,
       _rebindPendingNotificationOverlay = rebindPendingNotificationOverlay,
       _rebindLocalNotificationLedger = rebindLocalNotificationLedger,
       _suspendLocalNotificationLedgerClaims =
           suspendLocalNotificationLedgerClaims,
       _publishSharedBinding = publishSharedBinding,
       _rebindRemoteAnnouncements = rebindRemoteAnnouncements,
       _createInstallationId = createInstallationId ?? const Uuid().v4,
       _recoveryGraphRegistered = recoveryGraphRegistered;

  final SecureKeyStore _secureKeyStore;
  final CanonicalRuntimeLeaseGateway? _leaseGateway;
  final DroppedPushRecoveryBindingPublisher? _droppedPushBindingPublisher;
  final CanonicalRuntimeOverlayRebind? _rebindPendingNotificationOverlay;
  final CanonicalRuntimeLedgerRebind? _rebindLocalNotificationLedger;
  final CanonicalRuntimeLedgerClaimsSuspend?
  _suspendLocalNotificationLedgerClaims;
  final CanonicalRuntimeSharedBindingPublish? _publishSharedBinding;
  final CanonicalRuntimeRemoteAnnouncementRebind? _rebindRemoteAnnouncements;
  final String Function() _createInstallationId;
  final bool _recoveryGraphRegistered;

  Future<CanonicalRuntimeStartupBinding> loadStartupBinding() async {
    final installationId = await _installationId();
    final persisted = (await _secureKeyStore.read(
      canonicalRuntimeAccountBindingStorageKey,
    ))?.trim();
    if (isCanonicalRuntimeOpaqueBinding(persisted)) {
      await _rebindRemoteAnnouncements?.call(persisted);
      await _publishSharedBinding?.call(persisted);
      await _rebindLocalNotificationLedger?.call(persisted);
      await _rebindDerivedOverlayBestEffort(
        persisted,
        operation: 'startup_bind',
      );
      return CanonicalRuntimeStartupBinding(
        leaseBinding: persisted!,
        hasAccount: true,
      );
    }
    if (persisted != null) {
      await _secureKeyStore.delete(canonicalRuntimeAccountBindingStorageKey);
    }
    final provisional = _derive(installationId, accountPeerId: null);
    await _rebindRemoteAnnouncements?.call(null);
    await _publishSharedBinding?.call(null);
    // A no-account binding is still an opaque, installation-local fence. It
    // clears old account records without teaching the ledger about raw account
    // identity, and closes a crash after secure logout but before cleanup.
    await _rebindLocalNotificationLedger?.call(provisional);
    await _rebindDerivedOverlayBestEffort(null, operation: 'startup_retire');
    return CanonicalRuntimeStartupBinding(
      leaseBinding: provisional,
      hasAccount: false,
    );
  }

  Future<String> publishAccount(String accountPeerId) async {
    final normalizedPeerId = accountPeerId.trim();
    if (normalizedPeerId.isEmpty) {
      throw ArgumentError.value(
        accountPeerId,
        'accountPeerId',
        'must not be blank',
      );
    }
    final binding = _derive(
      await _installationId(),
      accountPeerId: normalizedPeerId,
    );
    final previous = await readCurrentAccountBinding();
    await _suspendLocalNotificationLedgerClaims?.call(previous);
    // Exact remote presentation proof can outlive a session. Retire the old
    // account's proof before granting notification authority to the new one.
    await _rebindRemoteAnnouncements?.call(binding);
    await _writeAndVerify(canonicalRuntimeAccountBindingStorageKey, binding);
    await _publishCurrentRecoveryReadiness(binding);
    await _leaseGateway?.rebind(binding);
    await _publishSharedBinding?.call(binding);
    await _rebindLocalNotificationLedger?.call(binding);
    // The overlay is derived cache, never account authority. Commit secure,
    // native, and lease bindings first. A stale overlay is independently
    // unreadable because every operation compares the canonical secure binding.
    await _rebindDerivedOverlayBestEffort(
      binding,
      operation: 'publish_account',
    );
    return binding;
  }

  /// Idempotently reconciles the native worker readiness for the already
  /// committed account binding. This is intentionally a one-shot bootstrap
  /// operation, not a health monitor or retry timer.
  Future<String?> reconcileCurrentAccountRecoveryReadiness() async {
    final binding = await readCurrentAccountBinding();
    if (binding == null) {
      final publisher = _droppedPushBindingPublisher;
      if (publisher != null) {
        final publication = await publisher.setCurrentBinding(
          null,
          activateRecoveryWork: false,
          recoverStaleAuthorityMutations: true,
        );
        if (!publication.exactlyMatches(
          binding: null,
          recoveryWorkEnabled: false,
        )) {
          throw StateError(
            'native recovery binding retirement reconciliation was rejected',
          );
        }
      }
      return null;
    }
    await _publishCurrentRecoveryReadiness(
      binding,
      recoverStaleAuthorityMutations: true,
    );
    return binding;
  }

  Future<String> retireAccount() async {
    final installationId = await _installationId();
    final previous = await readCurrentAccountBinding();
    await _suspendLocalNotificationLedgerClaims?.call(previous);
    await _secureKeyStore.delete(canonicalRuntimeAccountBindingStorageKey);
    if (await _secureKeyStore.read(canonicalRuntimeAccountBindingStorageKey) !=
        null) {
      throw StateError('canonical account binding deletion was not durable');
    }
    final droppedPushBindingPublisher = _droppedPushBindingPublisher;
    if (droppedPushBindingPublisher != null) {
      final publication = await droppedPushBindingPublisher.setCurrentBinding(
        null,
        activateRecoveryWork: false,
      );
      if (!publication.exactlyMatches(
        binding: null,
        recoveryWorkEnabled: false,
      )) {
        throw StateError('native recovery binding retirement was rejected');
      }
    }
    final provisional = _derive(installationId, accountPeerId: null);
    await _leaseGateway?.rebind(provisional);
    await _publishSharedBinding?.call(null);
    await _rebindRemoteAnnouncements?.call(null);
    await _rebindLocalNotificationLedger?.call(provisional);
    await _rebindDerivedOverlayBestEffort(null, operation: 'retire_account');
    return provisional;
  }

  Future<String?> readCurrentAccountBinding() async {
    final value = await _secureKeyStore.read(
      canonicalRuntimeAccountBindingStorageKey,
    );
    return isCanonicalRuntimeOpaqueBinding(value) ? value : null;
  }

  Future<void> _publishCurrentRecoveryReadiness(
    String binding, {
    bool recoverStaleAuthorityMutations = false,
  }) async {
    final droppedPushBindingPublisher = _droppedPushBindingPublisher;
    if (droppedPushBindingPublisher == null) return;
    final recoveryWorkEnabled = _recoveryGraphRegistered;
    final publication = await droppedPushBindingPublisher.setCurrentBinding(
      binding,
      activateRecoveryWork: recoveryWorkEnabled,
      recoverStaleAuthorityMutations: recoverStaleAuthorityMutations,
    );
    if (!publication.exactlyMatches(
      binding: binding,
      recoveryWorkEnabled: recoveryWorkEnabled,
    )) {
      throw StateError('native recovery binding publication was rejected');
    }
  }

  /// Derives the binding for a committed database identity without minting an
  /// installation ID or publishing any authority.
  ///
  /// Headless recovery uses this after its passive SQL identity read so a
  /// stale secure binding cannot authorize the wrong account database.
  Future<String?> deriveExistingAccountBinding(String accountPeerId) async {
    final normalizedPeerId = accountPeerId.trim();
    if (normalizedPeerId.isEmpty) return null;
    final installationId = (await _secureKeyStore.read(
      canonicalRuntimeInstallationIdStorageKey,
    ))?.trim();
    if (installationId == null || installationId.isEmpty) return null;
    return _derive(installationId, accountPeerId: normalizedPeerId);
  }

  Future<void> _rebindDerivedOverlayBestEffort(
    String? binding, {
    required String operation,
  }) async {
    final rebind = _rebindPendingNotificationOverlay;
    if (rebind == null) return;
    try {
      await rebind(binding);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_NOTIFICATION_OVERLAY_REBIND_FAILED',
        details: {
          'operation': operation,
          'bindingPresent': binding != null,
          'errorType': error.runtimeType.toString(),
        },
      );
    }
  }

  Future<String> _installationId() async {
    final existing = (await _secureKeyStore.read(
      canonicalRuntimeInstallationIdStorageKey,
    ))?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final created = _createInstallationId().trim();
    if (created.isEmpty) {
      throw StateError('installation ID generator returned a blank value');
    }
    await _writeAndVerify(canonicalRuntimeInstallationIdStorageKey, created);
    return created;
  }

  Future<void> _writeAndVerify(String key, String value) async {
    await _secureKeyStore.write(key, value);
    if (await _secureKeyStore.read(key) != value) {
      throw StateError('secure binding write was not durable: $key');
    }
  }

  String _derive(String installationId, {required String? accountPeerId}) {
    final account = accountPeerId ?? '<unbound>';
    final bytes = utf8.encode(
      'mknoon/canonical-runtime-binding/v1\u0000$installationId\u0000$account',
    );
    return 'v1:${sha256.convert(bytes)}';
  }
}

/// Publishes the exact opaque account binding to the iOS shared Keychain and
/// verifies the projection before a native notification consumer may use it.
/// A null value retires the projection and requires a read-back miss.
Future<void> publishCanonicalRuntimeSharedBinding({
  required SecureKeyStore sharedKeyStore,
  required String? opaqueBinding,
}) async {
  if (opaqueBinding != null &&
      !isCanonicalRuntimeOpaqueBinding(opaqueBinding)) {
    throw const FormatException('invalid canonical runtime binding');
  }
  if (opaqueBinding == null) {
    await sharedKeyStore.delete(canonicalRuntimeSharedAccountBindingStorageKey);
    if (await sharedKeyStore.read(
          canonicalRuntimeSharedAccountBindingStorageKey,
        ) !=
        null) {
      throw StateError('shared canonical binding retirement was not durable');
    }
    return;
  }
  await sharedKeyStore.write(
    canonicalRuntimeSharedAccountBindingStorageKey,
    opaqueBinding,
  );
  if (await sharedKeyStore.read(
        canonicalRuntimeSharedAccountBindingStorageKey,
      ) !=
      opaqueBinding) {
    throw StateError('shared canonical binding publication was not durable');
  }
}
