import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/app/bootstrap/production_canonical_inbox_projection_composition.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/107_direct_notification_durability.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/canonical_recovery_runtime.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';
import 'package:flutter_app/core/notifications/headless_canonical_recovery_entrypoint.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/legacy_group_secret_storage_scrub.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// One synchronous admission fence for direct, staged, protected-group and
/// foreground/background drain callbacks.
final class ProductionHeadlessRecoveryAdmissionBarrier {
  final Set<Future<void>> _admitted = <Future<void>>{};
  bool _sealed = false;
  bool _rejectedAfterSeal = false;
  Object? _firstError;
  StackTrace? _firstStackTrace;

  bool get isSealed => _sealed;
  bool get hasRejectedAfterSeal => _rejectedAfterSeal;
  int get admittedCount => _admitted.length;

  /// Returns false synchronously after the seal. [onRejected] must persist the
  /// offered work for a successor before this method returns.
  bool tryAdmit(
    Future<void> Function() work, {
    required void Function() onRejected,
  }) {
    if (_sealed) {
      _rejectedAfterSeal = true;
      onRejected();
      return false;
    }
    late final Future<void> tracked;
    tracked = Future<void>.sync(work)
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            _firstError ??= error;
            _firstStackTrace ??= stackTrace;
          },
        )
        .whenComplete(() => _admitted.remove(tracked));
    _admitted.add(tracked);
    return true;
  }

  Future<void> sealAndAwait() async {
    _sealed = true;
    while (_admitted.isNotEmpty) {
      await Future.wait<void>(_admitted.toList(growable: false));
    }
    final error = _firstError;
    if (error != null) {
      Error.throwWithStackTrace(error, _firstStackTrace ?? StackTrace.current);
    }
  }
}

final class ProductionHeadlessCustodyTotals {
  const ProductionHeadlessCustodyTotals({
    required this.directDisplay,
    required this.directReconciliation,
    required this.groupDisplay,
    required this.groupReconciliation,
    required this.unresolvedLedgerRecords,
  });

  final int directDisplay;
  final int directReconciliation;
  final int groupDisplay;
  final int groupReconciliation;
  final int unresolvedLedgerRecords;

  int get sqlTotal =>
      directDisplay + directReconciliation + groupDisplay + groupReconciliation;

  bool get isConverged => sqlTotal == 0 && unresolvedLedgerRecords == 0;
}

final class ProductionHeadlessCanonicalAuthoritySnapshot {
  const ProductionHeadlessCanonicalAuthoritySnapshot({
    required this.binding,
    required this.marker,
    required this.recoveryWorkEnabled,
    required this.migrationAllowsRecovery,
    required this.roleAllowsRecovery,
    required this.authorityFingerprint,
    this.authorityRevision = 0,
    this.authorityMutationInProgress = false,
  });

  final String? binding;
  final CanonicalRecoveryMarker? marker;
  final bool recoveryWorkEnabled;
  final bool migrationAllowsRecovery;
  final bool roleAllowsRecovery;
  final String? authorityFingerprint;
  final int authorityRevision;
  final bool authorityMutationInProgress;

  bool get isEligibleForAcquisition =>
      binding != null &&
      binding!.trim().isNotEmpty &&
      recoveryWorkEnabled &&
      migrationAllowsRecovery &&
      roleAllowsRecovery &&
      authorityRevision >= 0 &&
      !authorityMutationInProgress &&
      authorityFingerprint != null &&
      authorityFingerprint!.trim().isNotEmpty;
}

final class ProductionHeadlessQualifiedIdentity {
  const ProductionHeadlessQualifiedIdentity({
    required this.accountPeerId,
    required this.physicalPeerId,
    required this.physicalPrivateKey,
    required this.binding,
    required this.authorityFingerprint,
    required this.isLinked,
  });

  final String accountPeerId;
  final String physicalPeerId;
  final String physicalPrivateKey;
  final String binding;
  final String authorityFingerprint;
  final bool isLinked;
}

final class ProductionHeadlessRecoverySessionDelegates {
  const ProductionHeadlessRecoverySessionDelegates({
    required this.ensureRuntimeReady,
    required this.ensureTransportHealthy,
    required this.drainDirectInbox,
    required this.drainGroupInbox,
    required this.settleNotificationProjection,
    required this.sealExternalAdmission,
    required this.awaitExternalInFlight,
    required this.stopGroupMessageListener,
    required this.disposeProjectionOwners,
    required this.disposeRuntimeOwnersAfterNativeQuiescence,
    required this.admissionBarrier,
    this.quiesceRuntime,
    this.hasExternalPostSealRetryableWork,
  });

  final Future<void> Function() ensureRuntimeReady;
  final Future<void> Function() ensureTransportHealthy;
  final Future<CanonicalRecoveryDrainOutcome> Function() drainDirectInbox;
  final Future<CanonicalRecoveryDrainOutcome> Function() drainGroupInbox;
  final Future<CanonicalRecoveryProjectionOutcome> Function({
    required bool authoritative,
  })
  settleNotificationProjection;
  final void Function() sealExternalAdmission;
  final Future<void> Function() awaitExternalInFlight;
  final Future<void> Function() stopGroupMessageListener;
  final Future<void> Function() disposeProjectionOwners;

  /// Bound only by the acquisition owner after native drain ownership is
  /// available. A raw composition deliberately leaves this absent.
  final Future<bool> Function()? quiesceRuntime;
  final Future<bool> Function() disposeRuntimeOwnersAfterNativeQuiescence;
  final ProductionHeadlessRecoveryAdmissionBarrier admissionBarrier;
  final bool Function()? hasExternalPostSealRetryableWork;
}

abstract interface class ProductionHeadlessOwnedRecoverySession
    implements CanonicalRecoverySession {
  HeadlessCanonicalRecoveryCleanup get lifecycleFacts;

  Future<HeadlessCanonicalRecoveryCleanup> emergencyCleanup();
}

final class ProductionHeadlessCanonicalRecoverySession
    implements
        ProductionHeadlessOwnedRecoverySession,
        CanonicalRecoveryPostSealRetryState {
  ProductionHeadlessCanonicalRecoverySession({
    required ProductionHeadlessRecoverySessionDelegates delegates,
    required Future<bool> Function() closeDatabase,
    required Future<bool> Function({required bool databaseClosed})
    releaseOwnership,
  }) : _delegates = delegates,
       _closeDatabase = closeDatabase,
       _releaseOwnership = releaseOwnership;

  final ProductionHeadlessRecoverySessionDelegates _delegates;
  final Future<bool> Function() _closeDatabase;
  final Future<bool> Function({required bool databaseClosed}) _releaseOwnership;
  bool _databaseClosed = false;
  bool _leaseReleased = false;
  bool _sealed = false;
  bool _groupStopped = false;
  bool _ownersDisposed = false;
  bool _runtimeQuiesced = false;
  int _settlementPass = 0;
  Future<HeadlessCanonicalRecoveryCleanup>? _emergencyCleanupInFlight;

  @override
  HeadlessCanonicalRecoveryCleanup get lifecycleFacts =>
      HeadlessCanonicalRecoveryCleanup(
        databaseClosed: _databaseClosed,
        leaseReleased: _leaseReleased,
      );

  @override
  Future<void> ensureRuntimeReady() => _delegates.ensureRuntimeReady();

  @override
  Future<void> ensureTransportHealthy() => _delegates.ensureTransportHealthy();

  @override
  Future<CanonicalRecoveryDrainOutcome> drainDirectInbox() =>
      _delegates.drainDirectInbox();

  @override
  Future<CanonicalRecoveryDrainOutcome> drainGroupInbox() =>
      _delegates.drainGroupInbox();

  @override
  Future<CanonicalRecoveryProjectionOutcome>
  settleNotificationProjection() async {
    final authoritative = _settlementPass++ > 0;
    return _delegates.settleNotificationProjection(
      authoritative: authoritative,
    );
  }

  @override
  Future<void> sealAdmissionAndAwaitInFlight() async {
    if (!_sealed) {
      _delegates.sealExternalAdmission();
      _sealed = true;
    }
    await Future.wait<void>([
      _delegates.admissionBarrier.sealAndAwait(),
      _delegates.awaitExternalInFlight(),
    ]);
  }

  @override
  Future<void> stopGroupMessageListener() async {
    if (_groupStopped) return;
    await _delegates.stopGroupMessageListener();
    _groupStopped = true;
  }

  @override
  Future<void> disposeProjectionOwners() async {
    if (_ownersDisposed) return;
    await _delegates.disposeProjectionOwners();
    _ownersDisposed = true;
  }

  @override
  Future<bool> quiesceRuntime() async {
    if (_runtimeQuiesced) return true;
    final quiesce = _delegates.quiesceRuntime;
    if (quiesce == null) return false;
    _runtimeQuiesced = await quiesce();
    return _runtimeQuiesced;
  }

  @override
  bool get hasPostSealRetryableWork =>
      _delegates.admissionBarrier.hasRejectedAfterSeal ||
      (_delegates.hasExternalPostSealRetryableWork?.call() ?? false);

  @override
  Future<bool> closeDatabase() async {
    if (_databaseClosed) return true;
    _databaseClosed = await _closeDatabase();
    return _databaseClosed;
  }

  @override
  Future<bool> releaseOwnership({required bool databaseClosed}) async {
    if (_leaseReleased) return true;
    _leaseReleased = await _releaseOwnership(databaseClosed: databaseClosed);
    return _leaseReleased;
  }

  @override
  Future<HeadlessCanonicalRecoveryCleanup> emergencyCleanup() {
    final current = _emergencyCleanupInFlight;
    if (current != null) return current;
    late final Future<HeadlessCanonicalRecoveryCleanup> operation;
    operation =
        () async {
          var dartOwnersQuiesced = false;
          try {
            await sealAdmissionAndAwaitInFlight();
            await stopGroupMessageListener();
            if (!_ownersDisposed) {
              await _delegates.disposeProjectionOwners();
              _ownersDisposed = true;
            }
          } catch (_) {
            dartOwnersQuiesced = false;
          }
          if (_sealed && _groupStopped && _ownersDisposed) {
            dartOwnersQuiesced = true;
          }
          var runtimeQuiesced = false;
          try {
            runtimeQuiesced = await quiesceRuntime();
          } catch (_) {
            runtimeQuiesced = false;
          }
          if (!dartOwnersQuiesced || !runtimeQuiesced) {
            try {
              await releaseOwnership(databaseClosed: false);
            } catch (_) {}
            return lifecycleFacts;
          }
          try {
            final closed = await closeDatabase();
            await releaseOwnership(databaseClosed: closed);
          } catch (_) {
            // The exact facts remain fail-closed. Native retains a DRAINING owner
            // whenever any ordered cleanup cut cannot be proven.
          }
          return lifecycleFacts;
        }().whenComplete(() {
          if (identical(_emergencyCleanupInFlight, operation)) {
            _emergencyCleanupInFlight = null;
          }
        });
    _emergencyCleanupInFlight = operation;
    return operation;
  }
}

abstract interface class ProductionHeadlessCanonicalRecoveryBackend {
  Future<ProductionHeadlessCanonicalAuthoritySnapshot> loadAuthority();

  Future<ProductionHeadlessOwnedRecoverySession?> acquireSession({
    required String binding,
    required CanonicalRecoveryReason reason,
    CanonicalRecoveryMarker? expectedMarker,
  });

  Future<bool> acknowledgeHeadlessMarker(
    CanonicalRecoveryMarker marker, {
    int? authorityRevision,
  });

  HeadlessCanonicalRecoveryCleanup get lifecycleFacts;

  Future<HeadlessCanonicalRecoveryCleanup> emergencyCleanup();
}

typedef ProductionHeadlessAcquireThenOpen<TDatabase> =
    Future<TDatabase> Function({
      required String binding,
      required Future<TDatabase> Function() openDatabase,
      required Future<bool> Function() closeAfterOpenFailure,
      required Future<bool> Function(TDatabase database)
      closeDatabaseOnRuntimeAttachFailure,
    });

/// The qualified identity plus platform-specific data needed to build the
/// recovery composition. Authority comparisons remain owned by the shared
/// acquisition owner rather than by an injected test model.
final class ProductionHeadlessCanonicalRecoveryQualification<TContext> {
  const ProductionHeadlessCanonicalRecoveryQualification({
    required this.identity,
    required this.context,
  });

  final ProductionHeadlessQualifiedIdentity identity;
  final TContext context;
}

/// Platform-neutral owner for the single production acquisition and cleanup
/// state machine. Android supplies the real SQLCipher/Go lease callbacks; host
/// tests inject deterministic callbacks into this exact production-used type.
final class ProductionHeadlessCanonicalRecoveryAcquisitionOwner<
  TDatabase,
  TContext
>
    implements ProductionHeadlessCanonicalRecoveryBackend {
  ProductionHeadlessCanonicalRecoveryAcquisitionOwner({
    required Future<ProductionHeadlessCanonicalAuthoritySnapshot> Function()
    loadAuthority,
    required bool Function() hasWritableOwnership,
    required ProductionHeadlessAcquireThenOpen<TDatabase> acquireThenOpen,
    required Future<TDatabase> Function({
      required void Function(TDatabase database) onOpened,
    })
    openExistingDatabase,
    required Future<ProductionHeadlessCanonicalRecoveryQualification<TContext>?>
    Function({
      required TDatabase database,
      required String binding,
      required ProductionHeadlessCanonicalAuthoritySnapshot preflight,
    })
    qualifyDatabase,
    required Future<ProductionHeadlessRecoverySessionDelegates> Function({
      required TDatabase database,
      required ProductionHeadlessCanonicalRecoveryQualification<TContext>
      qualification,
      required CanonicalRecoveryReason reason,
    })
    buildSession,
    required Future<bool> Function(TDatabase database) closeDatabase,
    required Future<bool> Function() beginOwnershipDrain,
    required Future<bool> Function() awaitOwnershipQuiescence,
    required Future<bool> Function({required bool databaseClosed})
    releaseOwnership,
    required Future<bool> Function(
      CanonicalRecoveryMarker marker, {
      int? authorityRevision,
    })
    acknowledgeHeadlessMarker,
  }) : _loadAuthority = loadAuthority,
       _hasWritableOwnership = hasWritableOwnership,
       _acquireThenOpen = acquireThenOpen,
       _openExistingDatabase = openExistingDatabase,
       _qualifyDatabase = qualifyDatabase,
       _buildSession = buildSession,
       _closeDatabase = closeDatabase,
       _beginOwnershipDrain = beginOwnershipDrain,
       _awaitOwnershipQuiescence = awaitOwnershipQuiescence,
       _releaseOwnership = releaseOwnership,
       _acknowledgeHeadlessMarker = acknowledgeHeadlessMarker;

  final Future<ProductionHeadlessCanonicalAuthoritySnapshot> Function()
  _loadAuthority;
  final bool Function() _hasWritableOwnership;
  final ProductionHeadlessAcquireThenOpen<TDatabase> _acquireThenOpen;
  final Future<TDatabase> Function({
    required void Function(TDatabase database) onOpened,
  })
  _openExistingDatabase;
  final Future<ProductionHeadlessCanonicalRecoveryQualification<TContext>?>
  Function({
    required TDatabase database,
    required String binding,
    required ProductionHeadlessCanonicalAuthoritySnapshot preflight,
  })
  _qualifyDatabase;
  final Future<ProductionHeadlessRecoverySessionDelegates> Function({
    required TDatabase database,
    required ProductionHeadlessCanonicalRecoveryQualification<TContext>
    qualification,
    required CanonicalRecoveryReason reason,
  })
  _buildSession;
  final Future<bool> Function(TDatabase database) _closeDatabase;
  final Future<bool> Function() _beginOwnershipDrain;
  final Future<bool> Function() _awaitOwnershipQuiescence;
  final Future<bool> Function({required bool databaseClosed}) _releaseOwnership;
  final Future<bool> Function(
    CanonicalRecoveryMarker marker, {
    int? authorityRevision,
  })
  _acknowledgeHeadlessMarker;

  ProductionHeadlessOwnedRecoverySession? _activeSession;
  TDatabase? _database;
  ProductionHeadlessRecoverySessionDelegates? _delegates;
  ProductionCanonicalRecoveryConstructionCleanupProof?
  _partialCompositionCleanupProof;
  bool _databaseClosed = true;
  bool _leaseReleased = true;
  Future<ProductionHeadlessOwnedRecoverySession?>? _acquisitionInFlight;
  Future<HeadlessCanonicalRecoveryCleanup>? _cleanupInFlight;
  Future<HeadlessCanonicalRecoveryCleanup>? _emergencyCleanupInFlight;

  @override
  Future<ProductionHeadlessCanonicalAuthoritySnapshot> loadAuthority() =>
      _loadAuthority();

  @override
  HeadlessCanonicalRecoveryCleanup get lifecycleFacts {
    final active = _activeSession;
    return active?.lifecycleFacts ??
        HeadlessCanonicalRecoveryCleanup(
          databaseClosed: _databaseClosed,
          leaseReleased: _leaseReleased,
        );
  }

  @override
  Future<ProductionHeadlessOwnedRecoverySession?> acquireSession({
    required String binding,
    required CanonicalRecoveryReason reason,
    CanonicalRecoveryMarker? expectedMarker,
  }) {
    if (_acquisitionInFlight != null ||
        _cleanupInFlight != null ||
        _emergencyCleanupInFlight != null) {
      return Future<ProductionHeadlessOwnedRecoverySession?>.value(null);
    }
    if (_activeSession != null || _hasWritableOwnership()) {
      return Future<ProductionHeadlessOwnedRecoverySession?>.value(null);
    }
    late final Future<ProductionHeadlessOwnedRecoverySession?> operation;
    operation =
        _acquireSession(
          binding: binding,
          reason: reason,
          expectedMarker: expectedMarker,
        ).whenComplete(() {
          if (identical(_acquisitionInFlight, operation)) {
            _acquisitionInFlight = null;
          }
        });
    _acquisitionInFlight = operation;
    return operation;
  }

  Future<ProductionHeadlessOwnedRecoverySession?> _acquireSession({
    required String binding,
    required CanonicalRecoveryReason reason,
    required CanonicalRecoveryMarker? expectedMarker,
  }) async {
    final preflight = await _loadAuthority();
    if (!preflight.isEligibleForAcquisition || preflight.binding != binding) {
      throw const ProductionHeadlessCanonicalRecoveryRefused(
        'pre_open_authority_refused',
      );
    }
    if (expectedMarker != null && preflight.marker != expectedMarker) {
      throw const ProductionHeadlessCanonicalRecoveryRefused(
        'pre_open_generation_changed',
      );
    }

    late ProductionHeadlessCanonicalRecoveryQualification<TContext>
    qualification;
    try {
      final database = await _acquireThenOpen(
        binding: binding,
        openDatabase: () async {
          final opened = await _openExistingDatabase(
            onOpened: (database) {
              _database = database;
              _databaseClosed = false;
              _leaseReleased = false;
            },
          );
          if (!identical(_database, opened)) {
            throw const ProductionHeadlessCanonicalRecoveryRefused(
              'opened_database_identity_changed',
            );
          }
          final candidate = await _qualifyDatabase(
            database: opened,
            binding: binding,
            preflight: preflight,
          );
          if (candidate == null || candidate.identity.binding != binding) {
            throw const ProductionHeadlessCanonicalRecoveryRefused(
              'post_open_authority_refused',
            );
          }
          if (candidate.identity.authorityFingerprint !=
              preflight.authorityFingerprint) {
            throw const ProductionHeadlessCanonicalRecoveryRefused(
              'post_open_authority_changed',
            );
          }
          final current = await _loadAuthority();
          if (!current.isEligibleForAcquisition ||
              current.binding != binding ||
              current.authorityFingerprint !=
                  candidate.identity.authorityFingerprint ||
              current.authorityRevision != preflight.authorityRevision ||
              current.authorityMutationInProgress ||
              current.marker != preflight.marker) {
            throw const ProductionHeadlessCanonicalRecoveryRefused(
              'post_open_native_authority_changed',
            );
          }
          qualification = candidate;
          return opened;
        },
        closeAfterOpenFailure: _closeTrackedDatabase,
        closeDatabaseOnRuntimeAttachFailure: (database) {
          _database ??= database;
          return _closeTrackedDatabase();
        },
      );
      if (!identical(_database, database) || !_hasWritableOwnership()) {
        throw const ProductionHeadlessCanonicalRecoveryRefused(
          'writable_ownership_unavailable',
        );
      }
      _leaseReleased = false;

      _partialCompositionCleanupProof =
          const ProductionCanonicalRecoveryConstructionCleanupProof.unproven();
      late final ProductionHeadlessRecoverySessionDelegates built;
      try {
        built = await _buildSession(
          database: database,
          qualification: qualification,
          reason: reason,
        );
      } on ProductionCanonicalRecoveryCompositionConstructionFailure catch (
        failure
      ) {
        _partialCompositionCleanupProof = failure.cleanupProof;
        rethrow;
      }
      final delegates = _bindOwnedRuntimeQuiescence(built);
      _delegates = delegates;
      _partialCompositionCleanupProof = null;

      late final ProductionHeadlessCanonicalRecoverySession session;
      session = ProductionHeadlessCanonicalRecoverySession(
        delegates: delegates,
        closeDatabase: _closeTrackedDatabase,
        releaseOwnership: ({required databaseClosed}) async {
          final released = await _releaseOwnership(
            databaseClosed: databaseClosed,
          );
          _leaseReleased = released;
          if (released && identical(_activeSession, session)) {
            _activeSession = null;
            _database = null;
            _delegates = null;
            _partialCompositionCleanupProof = null;
          }
          return released;
        },
      );
      _activeSession = session;
      return session;
    } catch (error, stackTrace) {
      await _cleanupPartialGraph();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  ProductionHeadlessRecoverySessionDelegates _bindOwnedRuntimeQuiescence(
    ProductionHeadlessRecoverySessionDelegates built,
  ) => ProductionHeadlessRecoverySessionDelegates(
    ensureRuntimeReady: built.ensureRuntimeReady,
    ensureTransportHealthy: built.ensureTransportHealthy,
    drainDirectInbox: built.drainDirectInbox,
    drainGroupInbox: built.drainGroupInbox,
    settleNotificationProjection: built.settleNotificationProjection,
    sealExternalAdmission: built.sealExternalAdmission,
    awaitExternalInFlight: built.awaitExternalInFlight,
    stopGroupMessageListener: built.stopGroupMessageListener,
    disposeProjectionOwners: built.disposeProjectionOwners,
    quiesceRuntime: () async {
      if (!await _beginOwnershipDrain()) return false;
      if (!await _awaitOwnershipQuiescence()) return false;
      return built.disposeRuntimeOwnersAfterNativeQuiescence();
    },
    disposeRuntimeOwnersAfterNativeQuiescence:
        built.disposeRuntimeOwnersAfterNativeQuiescence,
    admissionBarrier: built.admissionBarrier,
    hasExternalPostSealRetryableWork: built.hasExternalPostSealRetryableWork,
  );

  Future<bool> _closeTrackedDatabase() async {
    final database = _database;
    if (database == null) {
      _databaseClosed = true;
      return true;
    }
    final closed = await _closeDatabase(database);
    _databaseClosed = closed;
    return closed;
  }

  @override
  Future<bool> acknowledgeHeadlessMarker(
    CanonicalRecoveryMarker marker, {
    int? authorityRevision,
  }) =>
      _acknowledgeHeadlessMarker(marker, authorityRevision: authorityRevision);

  @override
  Future<HeadlessCanonicalRecoveryCleanup> emergencyCleanup() {
    final current = _emergencyCleanupInFlight;
    if (current != null) return current;
    late final Future<HeadlessCanonicalRecoveryCleanup> operation;
    operation =
        () async {
          final acquisition = _acquisitionInFlight;
          if (acquisition != null) {
            try {
              await acquisition;
            } catch (_) {
              // The acquisition path owns cleanup of the exact partial graph.
            }
          }
          final active = _activeSession;
          if (active != null) return active.emergencyCleanup();
          return _cleanupPartialGraph();
        }().whenComplete(() async {
          // Keep this cleanup generation published through the release turn.
          // A release callback may concurrently request a successor and a
          // second cleanup; both must still observe the predecessor fence.
          await Future<void>.delayed(Duration.zero);
          if (identical(_emergencyCleanupInFlight, operation)) {
            _emergencyCleanupInFlight = null;
          }
        });
    _emergencyCleanupInFlight = operation;
    return operation;
  }

  Future<HeadlessCanonicalRecoveryCleanup> _cleanupPartialGraph() {
    final current = _cleanupInFlight;
    if (current != null) return current;
    late final Future<HeadlessCanonicalRecoveryCleanup> operation;
    operation =
        () async {
          final constructionProof = _partialCompositionCleanupProof;
          var dartOwnersQuiesced =
              _delegates == null &&
              (constructionProof == null ||
                  (constructionProof.admissionSealedAndDrained &&
                      constructionProof.dartOwnersQuiesced));
          try {
            final delegates = _delegates;
            if (delegates != null) {
              delegates.sealExternalAdmission();
              await Future.wait<void>([
                delegates.admissionBarrier.sealAndAwait(),
                delegates.awaitExternalInFlight(),
              ]);
              await delegates.stopGroupMessageListener();
              await delegates.disposeProjectionOwners();
              dartOwnersQuiesced = true;
            }
          } catch (_) {}
          var runtimeQuiesced =
              !_hasWritableOwnership() &&
              (constructionProof?.runtimeQuiesced ?? true);
          if (_hasWritableOwnership()) {
            try {
              final delegates = _delegates;
              if (delegates != null) {
                final quiesce = delegates.quiesceRuntime;
                runtimeQuiesced = quiesce != null && await quiesce();
              } else {
                final writableRuntimeQuiesced =
                    await _beginOwnershipDrain() &&
                    await _awaitOwnershipQuiescence();
                runtimeQuiesced =
                    writableRuntimeQuiesced &&
                    (constructionProof?.runtimeQuiesced ?? true);
              }
            } catch (_) {
              runtimeQuiesced = false;
            }
          }
          if (dartOwnersQuiesced && runtimeQuiesced) {
            try {
              await _closeTrackedDatabase();
            } catch (_) {
              _databaseClosed = false;
            }
          }
          if (_hasWritableOwnership()) {
            try {
              _leaseReleased = await _releaseOwnership(
                databaseClosed:
                    dartOwnersQuiesced && runtimeQuiesced && _databaseClosed,
              );
            } catch (_) {
              _leaseReleased = false;
            }
          } else {
            _leaseReleased = true;
          }
          if (_leaseReleased) {
            _activeSession = null;
            _database = null;
            _delegates = null;
            _partialCompositionCleanupProof = null;
          }
          return lifecycleFacts;
        }().whenComplete(() async {
          // Retire the exact partial generation only after callbacks triggered
          // by its ownership release have had a chance to observe the fence.
          await Future<void>.delayed(Duration.zero);
          if (identical(_cleanupInFlight, operation)) _cleanupInFlight = null;
        });
    _cleanupInFlight = operation;
    return operation;
  }
}

final class ProductionHeadlessCanonicalRecoveryRefused implements Exception {
  const ProductionHeadlessCanonicalRecoveryRefused(this.reason);

  final String reason;
}

final class ProductionHeadlessCanonicalRecoveryRunner {
  ProductionHeadlessCanonicalRecoveryRunner({
    required ProductionHeadlessCanonicalRecoveryBackend backend,
  }) : _backend = backend;

  final ProductionHeadlessCanonicalRecoveryBackend _backend;
  Future<HeadlessCanonicalRecoveryRunReport>? _inFlight;

  Future<HeadlessCanonicalRecoveryRunReport> run({
    required HeadlessCanonicalRecoveryInvocation invocation,
    required bool Function() isStopRequested,
  }) {
    final current = _inFlight;
    if (current != null) {
      return Future<HeadlessCanonicalRecoveryRunReport>.value(
        _report(
          CanonicalRecoveryResult(
            disposition: CanonicalRecoveryDisposition.retry,
            generation: invocation.generation,
            failureReason: 'headless_recovery_already_in_flight',
          ),
        ),
      );
    }
    late final Future<HeadlessCanonicalRecoveryRunReport> operation;
    operation = _run(invocation: invocation, isStopRequested: isStopRequested)
        .whenComplete(() {
          if (identical(_inFlight, operation)) _inFlight = null;
        });
    _inFlight = operation;
    return operation;
  }

  Future<HeadlessCanonicalRecoveryRunReport> _run({
    required HeadlessCanonicalRecoveryInvocation invocation,
    required bool Function() isStopRequested,
  }) async {
    late final ProductionHeadlessCanonicalAuthoritySnapshot preflight;
    try {
      preflight = await _backend.loadAuthority();
    } catch (error) {
      return _report(
        CanonicalRecoveryResult(
          disposition: CanonicalRecoveryDisposition.retry,
          generation: invocation.generation,
          failureReason: 'headless_authority_read_failed:${error.runtimeType}',
        ),
      );
    }

    final preflightFailure = _validateInvocation(invocation, preflight);
    if (preflightFailure != null) return _report(preflightFailure);

    final runtime = CanonicalRecoveryRuntime(
      loadCurrentBinding: () async => (await _backend.loadAuthority()).binding,
      loadPendingMarker: () async => (await _backend.loadAuthority()).marker,
      loadAuthorityFingerprint: () async =>
          (await _backend.loadAuthority()).authorityFingerprint,
      loadRecoveryWorkEnabled: () async =>
          (await _backend.loadAuthority()).recoveryWorkEnabled,
      loadAuthorityFence: () async {
        final authority = await _backend.loadAuthority();
        return CanonicalRecoveryAuthorityFence(
          binding: authority.binding,
          marker: authority.marker,
          authorityFingerprint: authority.isEligibleForAcquisition
              ? authority.authorityFingerprint
              : null,
          recoveryWorkEnabled:
              authority.recoveryWorkEnabled &&
              authority.migrationAllowsRecovery &&
              authority.roleAllowsRecovery,
          authorityRevision: authority.authorityRevision,
          authorityMutationInProgress: authority.authorityMutationInProgress,
        );
      },
      acquireSession: ({required binding, required reason}) =>
          _backend.acquireSession(
            binding: binding,
            reason: reason,
            expectedMarker:
                invocation.reason == CanonicalRecoveryReason.deletedBatch
                ? CanonicalRecoveryMarker(
                    generation: invocation.generation!,
                    binding: invocation.binding,
                  )
                : null,
          ),
      acknowledgeMarker: _backend.acknowledgeHeadlessMarker,
      isStopRequested: isStopRequested,
    );
    final result = await runtime.run(
      invocation.reason,
      expectedBinding: invocation.binding,
      expectedMarker: invocation.reason == CanonicalRecoveryReason.deletedBatch
          ? CanonicalRecoveryMarker(
              generation: invocation.generation!,
              binding: invocation.binding,
            )
          : null,
    );
    final facts = _backend.lifecycleFacts;
    if (!facts.databaseClosed || !facts.leaseReleased) {
      try {
        await _backend.emergencyCleanup();
      } catch (_) {
        // The final report below reads the same retained backend's exact facts.
        // Native keeps that engine whenever cleanup still cannot be proven.
      }
    }
    return _report(result);
  }

  CanonicalRecoveryResult? _validateInvocation(
    HeadlessCanonicalRecoveryInvocation invocation,
    ProductionHeadlessCanonicalAuthoritySnapshot authority,
  ) {
    if (!authority.isEligibleForAcquisition) {
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        generation: invocation.generation,
        failureReason: 'headless_authority_refused',
      );
    }
    if (authority.binding != invocation.binding) {
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.stale,
        generation: invocation.generation,
        failureReason: 'invocation_binding_is_not_current',
      );
    }
    switch (invocation.reason) {
      case CanonicalRecoveryReason.deletedBatch:
        final marker = authority.marker;
        if (marker == null ||
            marker.binding != invocation.binding ||
            marker.generation != invocation.generation) {
          return CanonicalRecoveryResult(
            disposition: CanonicalRecoveryDisposition.stale,
            generation: invocation.generation,
            currentGeneration: marker?.generation,
            failureReason: 'invocation_generation_is_not_current',
          );
        }
        break;
      case CanonicalRecoveryReason.periodicSweep:
        // Periodic work has no deletion generation. Authority, binding, and
        // the exact post-teardown fingerprint remain mandatory for both kinds.
        break;
    }
    return null;
  }

  HeadlessCanonicalRecoveryRunReport _report(CanonicalRecoveryResult result) {
    final facts = _backend.lifecycleFacts;
    return HeadlessCanonicalRecoveryRunReport(
      result: result,
      databaseClosed: facts.databaseClosed,
      leaseReleased: facts.leaseReleased,
    );
  }

  Future<HeadlessCanonicalRecoveryCleanup> emergencyCleanup() =>
      _backend.emergencyCleanup();
}

typedef ProductionCanonicalRecoveryCompositionBuilder =
    Future<ProductionHeadlessRecoverySessionDelegates> Function({
      required Database database,
      required SecureKeyStore secureKeyStore,
      required IdentityModel identity,
      required LinkedInstallationAuthoritySnapshot linkedAuthority,
      required ProductionHeadlessQualifiedIdentity qualifiedIdentity,
      required CanonicalRecoveryReason reason,
    });

final class ProductionCanonicalRecoveryConstructionCleanupProof {
  const ProductionCanonicalRecoveryConstructionCleanupProof({
    required this.admissionSealedAndDrained,
    required this.dartOwnersQuiesced,
    required this.runtimeQuiesced,
  });

  const ProductionCanonicalRecoveryConstructionCleanupProof.unproven()
    : admissionSealedAndDrained = false,
      dartOwnersQuiesced = false,
      runtimeQuiesced = false;

  final bool admissionSealedAndDrained;
  final bool dartOwnersQuiesced;
  final bool runtimeQuiesced;

  bool get isProven =>
      admissionSealedAndDrained && dartOwnersQuiesced && runtimeQuiesced;
}

final class ProductionCanonicalRecoveryCompositionConstructionFailure
    implements Exception {
  const ProductionCanonicalRecoveryCompositionConstructionFailure({
    required this.cause,
    required this.causeStackTrace,
    required this.cleanupProof,
  });

  final Object cause;
  final StackTrace causeStackTrace;
  final ProductionCanonicalRecoveryConstructionCleanupProof cleanupProof;

  @override
  String toString() =>
      'ProductionCanonicalRecoveryCompositionConstructionFailure('
      'causeType: ${cause.runtimeType}, cleanupProven: '
      '${cleanupProof.isProven})';
}

final class _AndroidProductionRecoveryQualificationContext {
  const _AndroidProductionRecoveryQualificationContext({
    required this.identity,
    required this.linkedAuthority,
  });

  final IdentityModel identity;
  final LinkedInstallationAuthoritySnapshot linkedAuthority;
}

/// Android production owner from native authority through the exact
/// SQLCipher/Go lease. Its injected composition builder is UI-neutral and owns
/// only canonical inbox replay and notification projection resources.
final class AndroidProductionHeadlessCanonicalRecoveryBackend
    implements ProductionHeadlessCanonicalRecoveryBackend {
  AndroidProductionHeadlessCanonicalRecoveryBackend({
    SecureKeyStore? secureKeyStore,
    DroppedPushRecoveryBridge? droppedPushRecoveryBridge,
    CanonicalRuntimeLeaseGateway? leaseGateway,
    ProductionCanonicalRecoveryCompositionBuilder? buildComposition,
  }) : _secureKeyStore = secureKeyStore ?? FlutterSecureKeyStore(),
       _droppedPushRecoveryBridge =
           droppedPushRecoveryBridge ?? DroppedPushRecoveryBridge(),
       _leaseGateway =
           leaseGateway ?? MethodChannelCanonicalRuntimeLeaseGateway(),
       _buildComposition =
           buildComposition ?? buildProductionCanonicalRecoveryComposition {
    _bindingCoordinator = CanonicalRuntimeBindingCoordinator(
      secureKeyStore: _secureKeyStore,
    );
    _linkedAuthority = LinkedInstallationAuthority(
      secureKeyStore: _secureKeyStore,
    );
    _migrationAuthority = SecureKeyStoreAccountMigrationAuthorityRepository(
      secureKeyStore: _secureKeyStore,
    );
    _writableSession = CanonicalWritableRuntimeSession(gateway: _leaseGateway);
    _acquisitionOwner =
        ProductionHeadlessCanonicalRecoveryAcquisitionOwner<
          Database,
          _AndroidProductionRecoveryQualificationContext
        >(
          loadAuthority: loadAuthority,
          hasWritableOwnership: () => _writableSession.hasWritableLease,
          acquireThenOpen: _acquireThenOpen,
          openExistingDatabase: _openExistingDatabase,
          qualifyDatabase: _qualifyDatabase,
          buildSession: _buildSession,
          closeDatabase: _closeDatabase,
          beginOwnershipDrain: _writableSession.beginDrain,
          awaitOwnershipQuiescence: _writableSession.awaitRuntimeQuiescence,
          releaseOwnership: ({required databaseClosed}) => _writableSession
              .releaseAfterDatabaseClose(databaseClosed: databaseClosed),
          acknowledgeHeadlessMarker: _acknowledgeHeadlessMarker,
        );
  }

  final SecureKeyStore _secureKeyStore;
  final DroppedPushRecoveryBridge _droppedPushRecoveryBridge;
  final CanonicalRuntimeLeaseGateway _leaseGateway;
  final ProductionCanonicalRecoveryCompositionBuilder _buildComposition;
  late final CanonicalRuntimeBindingCoordinator _bindingCoordinator;
  late final LinkedInstallationAuthority _linkedAuthority;
  late final SecureKeyStoreAccountMigrationAuthorityRepository
  _migrationAuthority;
  late final CanonicalWritableRuntimeSession _writableSession;
  late final ProductionHeadlessCanonicalRecoveryAcquisitionOwner<
    Database,
    _AndroidProductionRecoveryQualificationContext
  >
  _acquisitionOwner;

  @override
  HeadlessCanonicalRecoveryCleanup get lifecycleFacts =>
      _acquisitionOwner.lifecycleFacts;

  @override
  Future<ProductionHeadlessCanonicalAuthoritySnapshot> loadAuthority() async {
    final native = await _droppedPushRecoveryBridge.recoveryAuthority();
    if (native == null) {
      throw StateError('native recovery authority is unavailable');
    }
    final secureBinding = await _bindingCoordinator.readCurrentAccountBinding();
    final migration = await _migrationAuthority.loadAuthority();
    final linked = await _linkedAuthority.load();
    final binding = native.currentBinding == secureBinding
        ? native.currentBinding
        : null;
    var migrationAllowsRecovery =
        migration == null ||
        (!migration.isFailClosed &&
            migration.allowsNormalStartup &&
            migration.state != AccountMigrationAuthorityState.noAccount);
    final migrationAccount = migration?.accountPeerId?.trim();
    if (migrationAllowsRecovery &&
        migrationAccount != null &&
        migrationAccount.isNotEmpty) {
      migrationAllowsRecovery =
          binding != null &&
          await _bindingCoordinator.deriveExistingAccountBinding(
                migrationAccount,
              ) ==
              binding;
    }
    var roleAllowsRecovery =
        linked.isOrdinaryPrimary || linked.isActiveLinkedSecondary;
    if (roleAllowsRecovery && linked.isActiveLinkedSecondary) {
      final linkedAccount = linked.credential?.accountPeerId;
      roleAllowsRecovery =
          binding != null &&
          linkedAccount != null &&
          await _bindingCoordinator.deriveExistingAccountBinding(
                linkedAccount,
              ) ==
              binding;
    }
    return ProductionHeadlessCanonicalAuthoritySnapshot(
      binding: binding,
      marker: native.pendingMarker == null
          ? null
          : CanonicalRecoveryMarker(
              generation: native.pendingMarker!.generation,
              binding: native.pendingMarker!.binding,
            ),
      recoveryWorkEnabled: native.recoveryWorkEnabled,
      authorityRevision: native.authorityRevision,
      authorityMutationInProgress: native.authorityMutationInProgress,
      migrationAllowsRecovery: migrationAllowsRecovery,
      roleAllowsRecovery: roleAllowsRecovery,
      authorityFingerprint: binding == null
          ? null
          : _authorityFingerprint(
              binding: binding,
              migration: migration,
              linked: linked,
            ),
    );
  }

  @override
  Future<ProductionHeadlessOwnedRecoverySession?> acquireSession({
    required String binding,
    required CanonicalRecoveryReason reason,
    CanonicalRecoveryMarker? expectedMarker,
  }) => _acquisitionOwner.acquireSession(
    binding: binding,
    reason: reason,
    expectedMarker: expectedMarker,
  );

  Future<Database> _acquireThenOpen({
    required String binding,
    required Future<Database> Function() openDatabase,
    required Future<bool> Function() closeAfterOpenFailure,
    required Future<bool> Function(Database database)
    closeDatabaseOnRuntimeAttachFailure,
  }) => _writableSession.acquireThenOpen<Database>(
    binding: binding,
    openDatabase: openDatabase,
    closeAfterOpenFailure: closeAfterOpenFailure,
    closeDatabaseOnRuntimeAttachFailure: closeDatabaseOnRuntimeAttachFailure,
  );

  Future<Database> _openExistingDatabase({
    required void Function(Database database) onOpened,
  }) async {
    final database = await openEncryptedDatabase(
      secureKeyStore: _secureKeyStore,
      dbName: 'identity.db',
      version: currentIdentityDatabaseVersion,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
      requireExisting: true,
      onOpened: onOpened,
    );
    await repairDirectNotificationDurabilityDeleteTriggers(database);
    await migrateSecretsToSecureStorage(
      db: database,
      secureKeyStore: _secureKeyStore,
    );
    await runSecretNullChecksMigration(database);
    await scrubLegacyGroupSecretsToSecureStorage(
      db: database,
      secureKeyStore: _secureKeyStore,
    );
    return database;
  }

  Future<
    ProductionHeadlessCanonicalRecoveryQualification<
      _AndroidProductionRecoveryQualificationContext
    >?
  >
  _qualifyDatabase({
    required Database database,
    required String binding,
    required ProductionHeadlessCanonicalAuthoritySnapshot preflight,
  }) async {
    final identity = await loadPassiveIdentitySnapshot(
      dbLoadIdentityRow: () => dbLoadIdentityRow(database),
      secureKeyStore: _secureKeyStore,
    );
    if (identity == null) {
      throw const ProductionHeadlessCanonicalRecoveryRefused(
        'passive_identity_unavailable',
      );
    }
    final derivedBinding = await _bindingCoordinator
        .deriveExistingAccountBinding(identity.peerId);
    if (derivedBinding != binding) {
      throw const ProductionHeadlessCanonicalRecoveryRefused(
        'database_identity_binding_mismatch',
      );
    }
    final migration = await _migrationAuthority.loadAuthority();
    if (!_migrationAllowsIdentity(migration, identity.peerId)) {
      throw const ProductionHeadlessCanonicalRecoveryRefused(
        'migration_authority_refused',
      );
    }
    final linked = await _linkedAuthority.load(
      expectedAccountPeerId: identity.peerId,
    );
    final physicalPeerId = selectNotificationCompletedOutcomePhysicalPeerId(
      accountPeerId: identity.peerId,
      accountPublicKey: identity.publicKey,
      authority: linked,
    );
    if (physicalPeerId == null || linked.refusesStartup) {
      throw const ProductionHeadlessCanonicalRecoveryRefused(
        'linked_authority_refused',
      );
    }
    final physicalPrivateKey = linked.isActiveLinkedSecondary
        ? linked.credential!.transportPrivateKey
        : identity.privateKey;
    final fingerprint = _authorityFingerprint(
      binding: binding,
      migration: migration,
      linked: linked,
    );
    return ProductionHeadlessCanonicalRecoveryQualification(
      identity: ProductionHeadlessQualifiedIdentity(
        accountPeerId: identity.peerId,
        physicalPeerId: physicalPeerId,
        physicalPrivateKey: physicalPrivateKey,
        binding: binding,
        authorityFingerprint: fingerprint,
        isLinked: linked.isActiveLinkedSecondary,
      ),
      context: _AndroidProductionRecoveryQualificationContext(
        identity: identity,
        linkedAuthority: linked,
      ),
    );
  }

  Future<ProductionHeadlessRecoverySessionDelegates> _buildSession({
    required Database database,
    required ProductionHeadlessCanonicalRecoveryQualification<
      _AndroidProductionRecoveryQualificationContext
    >
    qualification,
    required CanonicalRecoveryReason reason,
  }) => _buildComposition(
    database: database,
    secureKeyStore: _secureKeyStore,
    identity: qualification.context.identity,
    linkedAuthority: qualification.context.linkedAuthority,
    qualifiedIdentity: qualification.identity,
    reason: reason,
  );

  Future<bool> _closeDatabase(Database database) async {
    if (database.isOpen) await database.close();
    return !database.isOpen;
  }

  @override
  Future<bool> acknowledgeHeadlessMarker(
    CanonicalRecoveryMarker marker, {
    int? authorityRevision,
  }) => _acquisitionOwner.acknowledgeHeadlessMarker(
    marker,
    authorityRevision: authorityRevision,
  );

  Future<bool> _acknowledgeHeadlessMarker(
    CanonicalRecoveryMarker marker, {
    int? authorityRevision,
  }) => authorityRevision == null
      ? Future<bool>.value(false)
      : _droppedPushRecoveryBridge.acknowledgeHeadlessRecovery(
          DroppedPushRecoveryMarker(
            generation: marker.generation,
            binding: marker.binding,
          ),
          authorityRevision: authorityRevision,
        );

  @override
  Future<HeadlessCanonicalRecoveryCleanup> emergencyCleanup() =>
      _acquisitionOwner.emergencyCleanup();

  bool _migrationAllowsIdentity(
    AccountMigrationAuthorityRecord? authority,
    String accountPeerId,
  ) {
    if (authority == null) return true;
    if (authority.isFailClosed || !authority.allowsNormalStartup) return false;
    if (authority.state == AccountMigrationAuthorityState.noAccount) {
      return false;
    }
    final expected = authority.accountPeerId?.trim();
    return expected == null || expected == accountPeerId;
  }

  String _authorityFingerprint({
    required String binding,
    required AccountMigrationAuthorityRecord? migration,
    required LinkedInstallationAuthoritySnapshot linked,
  }) {
    final credential = linked.credential;
    final payload = jsonEncode(<String, Object?>{
      'binding': binding,
      'migrationState': migration?.state.wireName,
      'migrationAccount': migration?.accountPeerId,
      'migrationFailClosed': migration?.isFailClosed ?? false,
      'linkedDisposition': linked.disposition.name,
      'linkedFailure': linked.failClosedReason,
      'linkedAccount': credential?.accountPeerId,
      'linkedAccountPublic': credential?.accountPublicKey,
      'linkedDevice': credential?.deviceId,
      'linkedTransportPeer': credential?.transportPeerId,
      'linkedTransportPublic': credential?.transportPublicKey,
      'linkedTransportPrivateDigest': credential == null
          ? null
          : sha256
                .convert(utf8.encode(credential.transportPrivateKey))
                .toString(),
      'linkedState': credential?.state.name,
      'linkedCreatedAt': credential?.createdAt,
      'linkedActivatedAt': credential?.activatedAt,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }
}

/// The UI-neutral production composition is implemented below this ownership
/// boundary so tests can inject deterministic repositories without invoking
/// plugins. The real implementation is shared with foreground bootstrap.
Future<ProductionHeadlessRecoverySessionDelegates>
buildProductionCanonicalRecoveryComposition({
  required Database database,
  required SecureKeyStore secureKeyStore,
  required IdentityModel identity,
  required LinkedInstallationAuthoritySnapshot linkedAuthority,
  required ProductionHeadlessQualifiedIdentity qualifiedIdentity,
  required CanonicalRecoveryReason reason,
}) {
  return buildProductionCanonicalInboxProjectionComposition(
    database: database,
    secureKeyStore: secureKeyStore,
    identity: identity,
    linkedAuthority: linkedAuthority,
    qualifiedIdentity: qualifiedIdentity,
    reason: reason,
  );
}

final AndroidProductionHeadlessCanonicalRecoveryBackend
_productionHeadlessCanonicalRecoveryBackend =
    AndroidProductionHeadlessCanonicalRecoveryBackend();
final ProductionHeadlessCanonicalRecoveryRunner
_productionHeadlessCanonicalRecoveryRunner =
    ProductionHeadlessCanonicalRecoveryRunner(
      backend: _productionHeadlessCanonicalRecoveryBackend,
    );

Future<HeadlessCanonicalRecoveryRunReport>
runProductionHeadlessCanonicalRecovery({
  required HeadlessCanonicalRecoveryInvocation invocation,
  required bool Function() isStopRequested,
}) => _productionHeadlessCanonicalRecoveryRunner.run(
  invocation: invocation,
  isStopRequested: isStopRequested,
);

Future<HeadlessCanonicalRecoveryCleanup>
cleanupProductionHeadlessCanonicalRecovery() =>
    _productionHeadlessCanonicalRecoveryRunner.emergencyCleanup();
