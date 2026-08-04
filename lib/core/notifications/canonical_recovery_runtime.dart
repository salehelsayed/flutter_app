import 'dart:async';

/// Why one canonical recovery pass was requested.
enum CanonicalRecoveryReason { deletedBatch, periodicSweep }

enum CanonicalRecoveryDisposition { succeeded, retry, stale }

/// Account/install-bound native recovery authority.
final class CanonicalRecoveryMarker {
  const CanonicalRecoveryMarker({
    required this.generation,
    required this.binding,
  }) : assert(generation > 0);

  final int generation;
  final String binding;

  @override
  bool operator ==(Object other) =>
      other is CanonicalRecoveryMarker &&
      other.generation == generation &&
      other.binding == binding;

  @override
  int get hashCode => Object.hash(generation, binding);
}

final class CanonicalRecoveryDrainOutcome {
  const CanonicalRecoveryDrainOutcome({
    required this.isSuccessful,
    required this.hasMore,
    this.failureReason,
  });

  final bool isSuccessful;
  final bool hasMore;
  final String? failureReason;

  bool get converged => isSuccessful && !hasMore;
}

/// Truthful settlement state for durable notification display and
/// reconciliation custody. A completed coordinator invocation is insufficient
/// when eligible rows remain pending for a later retry.
final class CanonicalRecoveryProjectionOutcome {
  const CanonicalRecoveryProjectionOutcome({
    required this.isSuccessful,
    required this.hasPendingWork,
    this.failureReason,
  });

  final bool isSuccessful;
  final bool hasPendingWork;
  final String? failureReason;

  bool get converged => isSuccessful && !hasPendingWork;
}

final class CanonicalRecoveryResult {
  const CanonicalRecoveryResult({
    required this.disposition,
    this.generation,
    this.currentGeneration,
    this.failureReason,
  });

  final CanonicalRecoveryDisposition disposition;
  final int? generation;
  final int? currentGeneration;
  final String? failureReason;
}

/// One lease-owned, writable canonical runtime.
///
/// [closeDatabase] must explicitly close the SQLCipher handle. The runtime
/// passes that exact acknowledgement to [releaseOwnership]; a false close can
/// therefore never transfer the writable lease to another Flutter engine.
abstract interface class CanonicalRecoverySession {
  Future<void> ensureRuntimeReady();

  Future<void> ensureTransportHealthy();

  Future<CanonicalRecoveryDrainOutcome> drainDirectInbox();

  Future<CanonicalRecoveryDrainOutcome> drainGroupInbox();

  Future<CanonicalRecoveryProjectionOutcome> settleNotificationProjection();

  /// Rejects new Go calls and waits for admitted JNI work, results, callbacks,
  /// and StopNode to settle. False retains this session as the old owner.
  Future<bool> quiesceRuntime();

  Future<bool> closeDatabase();

  Future<bool> releaseOwnership({required bool databaseClosed});
}

typedef LoadCanonicalRecoveryBinding = Future<String?> Function();
typedef LoadCanonicalRecoveryMarker =
    Future<CanonicalRecoveryMarker?> Function();
typedef AcquireCanonicalRecoverySession =
    Future<CanonicalRecoverySession?> Function({
      required String binding,
      required CanonicalRecoveryReason reason,
    });
typedef AcknowledgeCanonicalRecoveryMarker =
    Future<bool> Function(CanonicalRecoveryMarker marker);

/// Reason-typed orchestration shared by a future WorkManager entry point and
/// host tests.
///
/// This class does not create an engine or database itself. Production must
/// supply a session factory that acquires the native lease *before* opening
/// SQLCipher. A marker is acknowledged only after both inboxes and notification
/// custody converge, the database closes, the lease releases, and a final
/// account/generation resnapshot still matches.
final class CanonicalRecoveryRuntime {
  CanonicalRecoveryRuntime({
    required LoadCanonicalRecoveryBinding loadCurrentBinding,
    required LoadCanonicalRecoveryMarker loadPendingMarker,
    required AcquireCanonicalRecoverySession acquireSession,
    required AcknowledgeCanonicalRecoveryMarker acknowledgeMarker,
    bool Function()? isStopRequested,
    int maxDrainPassesPerLane = 64,
  }) : _loadCurrentBinding = loadCurrentBinding,
       _loadPendingMarker = loadPendingMarker,
       _acquireSession = acquireSession,
       _acknowledgeMarker = acknowledgeMarker,
       _isStopRequested = isStopRequested ?? _neverStopped,
       _maxDrainPassesPerLane = maxDrainPassesPerLane {
    if (maxDrainPassesPerLane <= 0) {
      throw ArgumentError.value(
        maxDrainPassesPerLane,
        'maxDrainPassesPerLane',
        'must be positive',
      );
    }
  }

  final LoadCanonicalRecoveryBinding _loadCurrentBinding;
  final LoadCanonicalRecoveryMarker _loadPendingMarker;
  final AcquireCanonicalRecoverySession _acquireSession;
  final AcknowledgeCanonicalRecoveryMarker _acknowledgeMarker;
  final bool Function() _isStopRequested;
  final int _maxDrainPassesPerLane;

  Future<CanonicalRecoveryResult>? _inFlight;

  Future<CanonicalRecoveryResult> run(CanonicalRecoveryReason reason) {
    final current = _inFlight;
    if (current != null) return current;
    final work = _run(reason);
    _inFlight = work;
    unawaited(
      work.whenComplete(() {
        if (identical(_inFlight, work)) _inFlight = null;
      }),
    );
    return work;
  }

  Future<CanonicalRecoveryResult> _run(CanonicalRecoveryReason reason) async {
    CanonicalRecoveryMarker? startingMarker;
    String? binding;
    try {
      binding = _normalizeBinding(await _loadCurrentBinding());
      if (binding == null) {
        return const CanonicalRecoveryResult(
          disposition: CanonicalRecoveryDisposition.stale,
          failureReason: 'no_current_binding',
        );
      }
      // Periodic work never adopts or consumes a deleted-batch marker. It
      // performs the same canonical drain, then the final resnapshot below
      // retries while any marker is present so the serial immediate work owns
      // that exact compare-and-acknowledgement.
      if (reason == CanonicalRecoveryReason.deletedBatch) {
        startingMarker = await _loadPendingMarker();
      }
    } catch (error) {
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        failureReason: 'authority_read_failed:${error.runtimeType}',
      );
    }

    if (startingMarker != null &&
        (startingMarker.generation <= 0 ||
            _normalizeBinding(startingMarker.binding) == null)) {
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        generation: startingMarker.generation,
        failureReason: 'invalid_pending_marker',
      );
    }

    if (reason == CanonicalRecoveryReason.deletedBatch &&
        startingMarker == null) {
      return const CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.stale,
        failureReason: 'no_pending_marker',
      );
    }
    if (startingMarker != null && startingMarker.binding != binding) {
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.stale,
        generation: startingMarker.generation,
        failureReason: 'marker_binding_is_not_current',
      );
    }

    CanonicalRecoverySession? session;
    try {
      session = await _acquireSession(binding: binding, reason: reason);
    } catch (error) {
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        generation: startingMarker?.generation,
        failureReason: 'session_acquire_failed:${error.runtimeType}',
      );
    }
    if (session == null) {
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        generation: startingMarker?.generation,
        failureReason: 'canonical_runtime_owned',
      );
    }

    CanonicalRecoveryResult workResult;
    var converged = false;
    try {
      _throwIfStopRequested();
      await session.ensureRuntimeReady();
      _throwIfStopRequested();
      await session.ensureTransportHealthy();
      _throwIfStopRequested();
      final direct = await _drainLane(
        lane: 'direct',
        drainOnePass: session.drainDirectInbox,
      );
      if (!direct.converged) {
        workResult = CanonicalRecoveryResult(
          disposition: CanonicalRecoveryDisposition.retry,
          generation: startingMarker?.generation,
          failureReason: direct.failureReason ?? 'direct_not_converged',
        );
      } else {
        final group = await _drainLane(
          lane: 'group',
          drainOnePass: session.drainGroupInbox,
        );
        if (!group.converged) {
          workResult = CanonicalRecoveryResult(
            disposition: CanonicalRecoveryDisposition.retry,
            generation: startingMarker?.generation,
            failureReason: group.failureReason ?? 'group_not_converged',
          );
        } else {
          final projection = await session.settleNotificationProjection();
          _throwIfStopRequested();
          if (!projection.converged) {
            workResult = CanonicalRecoveryResult(
              disposition: CanonicalRecoveryDisposition.retry,
              generation: startingMarker?.generation,
              failureReason:
                  projection.failureReason ?? 'projection_not_converged',
            );
          } else {
            converged = true;
            workResult = CanonicalRecoveryResult(
              disposition: CanonicalRecoveryDisposition.succeeded,
              generation: startingMarker?.generation,
            );
          }
        }
      }
    } on _CanonicalRecoveryStopped {
      workResult = CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        generation: startingMarker?.generation,
        failureReason: 'worker_stopped',
      );
    } catch (error) {
      workResult = CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        generation: startingMarker?.generation,
        failureReason: 'canonical_recovery_failed:${error.runtimeType}',
      );
    }

    var runtimeQuiesced = false;
    try {
      runtimeQuiesced = await session.quiesceRuntime();
    } catch (_) {
      runtimeQuiesced = false;
    }
    if (!runtimeQuiesced) {
      try {
        await session.releaseOwnership(databaseClosed: false);
      } catch (_) {}
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        generation: startingMarker?.generation,
        failureReason: 'runtime_quiesce_database_close_or_lease_release_failed',
      );
    }

    var databaseClosed = false;
    try {
      databaseClosed = await session.closeDatabase();
    } catch (_) {
      databaseClosed = false;
    }
    var ownershipReleased = false;
    try {
      ownershipReleased = await session.releaseOwnership(
        databaseClosed: databaseClosed,
      );
    } catch (_) {
      ownershipReleased = false;
    }
    if (!databaseClosed || !ownershipReleased) {
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        generation: startingMarker?.generation,
        failureReason: 'database_close_or_lease_release_failed',
      );
    }
    if (!converged) return workResult;

    String? finalBinding;
    CanonicalRecoveryMarker? finalMarker;
    try {
      finalBinding = _normalizeBinding(await _loadCurrentBinding());
      finalMarker = await _loadPendingMarker();
    } catch (error) {
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        generation: startingMarker?.generation,
        failureReason: 'pre_ack_authority_read_failed:${error.runtimeType}',
      );
    }
    if (finalMarker != null &&
        (finalMarker.generation <= 0 ||
            _normalizeBinding(finalMarker.binding) == null)) {
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        generation: startingMarker?.generation,
        currentGeneration: finalMarker.generation,
        failureReason: 'invalid_pre_ack_marker',
      );
    }
    if (finalBinding != binding) {
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.stale,
        generation: startingMarker?.generation,
        failureReason: 'binding_changed_before_ack',
      );
    }

    if (startingMarker == null) {
      if (finalMarker != null) {
        return CanonicalRecoveryResult(
          disposition: CanonicalRecoveryDisposition.retry,
          currentGeneration: finalMarker.generation,
          failureReason: 'generation_arrived_during_periodic_sweep',
        );
      }
      return workResult;
    }
    if (finalMarker != startingMarker) {
      return CanonicalRecoveryResult(
        disposition: finalMarker == null
            ? CanonicalRecoveryDisposition.stale
            : CanonicalRecoveryDisposition.retry,
        generation: startingMarker.generation,
        currentGeneration: finalMarker?.generation,
        failureReason: finalMarker == null
            ? 'marker_cleared_before_ack'
            : 'generation_superseded',
      );
    }

    bool acknowledged;
    try {
      acknowledged = await _acknowledgeMarker(startingMarker);
    } catch (_) {
      acknowledged = false;
    }
    if (!acknowledged) {
      return CanonicalRecoveryResult(
        disposition: CanonicalRecoveryDisposition.retry,
        generation: startingMarker.generation,
        failureReason: 'exact_ack_failed',
      );
    }
    return workResult;
  }

  Future<CanonicalRecoveryDrainOutcome> _drainLane({
    required String lane,
    required Future<CanonicalRecoveryDrainOutcome> Function() drainOnePass,
  }) async {
    for (var pass = 0; pass < _maxDrainPassesPerLane; pass++) {
      _throwIfStopRequested();
      final outcome = await drainOnePass();
      _throwIfStopRequested();
      if (!outcome.isSuccessful || !outcome.hasMore) return outcome;
    }
    return CanonicalRecoveryDrainOutcome(
      isSuccessful: true,
      hasMore: true,
      failureReason: '${lane}_page_budget_exhausted',
    );
  }

  String? _normalizeBinding(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void _throwIfStopRequested() {
    if (_isStopRequested()) throw const _CanonicalRecoveryStopped();
  }
}

bool _neverStopped() => false;

final class _CanonicalRecoveryStopped implements Exception {
  const _CanonicalRecoveryStopped();
}
