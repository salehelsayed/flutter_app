import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';

typedef ConsumeDirectRemotePresentationProof = Future<bool> Function();

/// The exact authenticated authority captured before a durable direct effect.
///
/// Raw peer and event identifiers live only in memory. The durable ledger sees
/// their canonical digests, while the existing optional v116 writer receives
/// the original authenticated tuple after the effect becomes terminal. An
/// optional in-memory proof cleanup token is carried with the same attempt so
/// it cannot consume an unrelated ambient iOS announcement after settlement.
final class DirectNotificationDurableEffectAuthority {
  const DirectNotificationDurableEffectAuthority({
    required this.currentOpaqueBinding,
    required this.physicalPeerId,
    required this.outcomeProducerKind,
    required this.eventKey,
    required this.receipt,
    this.sqlReadyRevision,
    this.consumeRemotePresentationProof,
  });

  final String currentOpaqueBinding;
  final String physicalPeerId;
  final NotificationCompletedOutcomeProducerKind outcomeProducerKind;
  final String eventKey;
  final DurableLocalNotificationEffectReceipt receipt;
  final int? sqlReadyRevision;
  final ConsumeDirectRemotePresentationProof? consumeRemotePresentationProof;

  bool get remotePresentationAdopted => consumeRemotePresentationProof != null;

  DirectNotificationDurableEffectAuthority withSqlReadyRevision(
    int revision, {
    ConsumeDirectRemotePresentationProof? consumeRemotePresentationProof,
  }) => DirectNotificationDurableEffectAuthority(
    currentOpaqueBinding: currentOpaqueBinding,
    physicalPeerId: physicalPeerId,
    outcomeProducerKind: outcomeProducerKind,
    eventKey: eventKey,
    receipt: receipt,
    sqlReadyRevision: revision,
    consumeRemotePresentationProof:
        consumeRemotePresentationProof ?? this.consumeRemotePresentationProof,
  );
}

enum DirectNotificationDisplayRetryDisposition {
  completed,
  retired,
  retryLater,
}

/// Projection result carried intact from the canonical effect decision to the
/// exact SQL completion callback. The candidate is never side-mapped by event
/// id, so a retry cannot accidentally attach an earlier generation's outcome.
final class DirectNotificationDisplayProjectionResult {
  const DirectNotificationDisplayProjectionResult._({
    required this.disposition,
    this.outcomeCandidate,
    this.durableEffectAuthority,
  });

  const DirectNotificationDisplayProjectionResult.completed({
    NotificationCompletedOutcomeCandidate? outcomeCandidate,
    DirectNotificationDurableEffectAuthority? durableEffectAuthority,
  }) : this._(
         disposition: DirectNotificationDisplayRetryDisposition.completed,
         outcomeCandidate: outcomeCandidate,
         durableEffectAuthority: durableEffectAuthority,
       );

  const DirectNotificationDisplayProjectionResult.retired()
    : this._(disposition: DirectNotificationDisplayRetryDisposition.retired);

  const DirectNotificationDisplayProjectionResult.retryLater()
    : this._(disposition: DirectNotificationDisplayRetryDisposition.retryLater);

  final DirectNotificationDisplayRetryDisposition disposition;
  final NotificationCompletedOutcomeCandidate? outcomeCandidate;
  final DirectNotificationDurableEffectAuthority? durableEffectAuthority;
}

typedef LoadDirectNotificationDisplayBatch<T> =
    Future<List<T>> Function({required int limit});
typedef ProjectDirectNotificationDisplay<T> =
    Future<DirectNotificationDisplayProjectionResult> Function(T entry);
typedef CompleteDirectNotificationDisplayWithOutcome<T> =
    Future<void> Function(
      T entry,
      NotificationCompletedOutcomeCandidate? outcome,
    );
typedef SettleDirectNotificationDurableEffect<T> =
    Future<void> Function(
      T entry,
      DirectNotificationDurableEffectAuthority authority,
    );
typedef NotifyDirectNotificationDurablePostSettlement<T> =
    Future<void> Function(
      T entry,
      DirectNotificationDurableEffectAuthority authority,
    );
typedef CompleteDirectNotificationDurableSqlHandoff<T> =
    Future<DurableLocalNotificationSqlHandoffResult> Function(
      T entry,
      NotificationCompletedOutcomeCandidate? outcome,
      DirectNotificationDurableEffectAuthority authority,
    );

/// Bounded, single-flight retry engine shared by direct display and
/// reconciliation custody. Durable rows remain the authority across restarts.
final class DirectNotificationDisplayRetryCoordinator<T> {
  DirectNotificationDisplayRetryCoordinator({
    required this.loadReady,
    required this.project,
    required this.completeWithOutcome,
    this.completeDurableSqlHandoff,
    this.settleDurableEffect,
    this.afterDurableSettlement,
    required this.retire,
    required this.recordFailure,
    this.entryIdentity,
    this.loadEarliestNextAttemptAt,
    this.scheduleRetry,
    DateTime Function()? nowUtc,
    this.batchSize = 20,
    this.maxBatchesPerRun = 4,
    this.durableSettlementRetryDelay = const Duration(seconds: 65),
  }) : nowUtc = nowUtc ?? DateTime.now {
    if (batchSize <= 0 ||
        maxBatchesPerRun <= 0 ||
        durableSettlementRetryDelay.isNegative) {
      throw ArgumentError('batch bounds must be positive');
    }
  }

  final LoadDirectNotificationDisplayBatch<T> loadReady;
  final ProjectDirectNotificationDisplay<T> project;
  final CompleteDirectNotificationDisplayWithOutcome<T> completeWithOutcome;
  final CompleteDirectNotificationDurableSqlHandoff<T>?
  completeDurableSqlHandoff;
  final SettleDirectNotificationDurableEffect<T>? settleDurableEffect;
  final NotifyDirectNotificationDurablePostSettlement<T>?
  afterDurableSettlement;
  final Future<void> Function(T entry) retire;
  final Future<void> Function(T entry, Object error) recordFailure;
  final Object? Function(T entry)? entryIdentity;
  final Future<DateTime?> Function()? loadEarliestNextAttemptAt;
  final void Function(Duration delay)? scheduleRetry;
  final DateTime Function() nowUtc;
  final int batchSize;
  final int maxBatchesPerRun;
  final Duration durableSettlementRetryDelay;

  Future<void>? _running;
  bool _dirty = false;
  bool _disposed = false;
  final List<_PendingDirectNotificationDurableSettlement<T>>
  _pendingDurableSettlements =
      <_PendingDirectNotificationDurableSettlement<T>>[];

  Future<void> retryNow() {
    if (_disposed) return Future<void>.value();
    final running = _running;
    if (running != null) {
      _dirty = true;
      return running;
    }
    final next = _drain();
    _running = next;
    return next;
  }

  Future<void> _drain() async {
    var needsLaterRetry = false;
    var inspectDeferred = false;
    var needsImmediateRetry = false;
    var batches = 0;
    final failedIdentities = <Object?>{};
    try {
      if (_pendingDurableSettlements.isNotEmpty) {
        final pending = List<_PendingDirectNotificationDurableSettlement<T>>.of(
          _pendingDurableSettlements,
        );
        for (final completion in pending) {
          if (_disposed) return;
          try {
            final completeDurable = completeDurableSqlHandoff;
            final settle = settleDurableEffect;
            if (completeDurable == null || settle == null) {
              throw const DirectNotificationDisplayRetryableException();
            }
            // Re-prove the typed SQL terminal (normally `alreadyCommitted`)
            // before every receipt-only settlement retry. Projection and its
            // native callback are deliberately not re-entered here.
            final handoff = await completeDurable(
              completion.entry,
              completion.outcomeCandidate,
              completion.authority,
            );
            if (handoff ==
                DurableLocalNotificationSqlHandoffResult.retryableMismatch) {
              throw const DirectNotificationDisplayRetryableException();
            }
            await settle(completion.entry, completion.authority);
            await afterDurableSettlement?.call(
              completion.entry,
              completion.authority,
            );
            _pendingDurableSettlements.remove(completion);
          } catch (_) {
            needsLaterRetry = true;
            inspectDeferred = true;
            failedIdentities.add(_identityOf(completion.entry));
          }
        }
      }
      while (!_disposed && batches < maxBatchesPerRun) {
        _dirty = false;
        final loaded = await loadReady(
          limit: batchSize + failedIdentities.length,
        );
        if (loaded.isEmpty) {
          if (_dirty) continue;
          inspectDeferred = true;
          return;
        }
        batches++;
        final batch = loaded
            .where((entry) => !failedIdentities.contains(_identityOf(entry)))
            .take(batchSize)
            .toList(growable: false);
        if (batch.isEmpty) {
          if (_dirty) continue;
          inspectDeferred = true;
          return;
        }

        for (final entry in batch) {
          if (_disposed) return;
          late Object failure;
          var durableSettlementPending = false;
          try {
            final projection = await project(entry);
            if (_disposed) return;
            if (projection.disposition ==
                DirectNotificationDisplayRetryDisposition.completed) {
              final authority = projection.durableEffectAuthority;
              if (authority != null) {
                final completeDurable = completeDurableSqlHandoff;
                if (completeDurable == null) {
                  throw const DirectNotificationDisplayRetryableException();
                }
                final handoff = await completeDurable(
                  entry,
                  projection.outcomeCandidate,
                  authority,
                );
                if (handoff ==
                    DurableLocalNotificationSqlHandoffResult
                        .retryableMismatch) {
                  throw const DirectNotificationDisplayRetryableException();
                }
                if (_disposed) return;
                final settle = settleDurableEffect;
                if (settle == null) {
                  throw const DirectNotificationDisplayRetryableException();
                }
                // SQL custody and the optional v116 outcome are exact and
                // committed before the file-ledger terminal becomes SETTLED.
                try {
                  await settle(entry, authority);
                  await afterDurableSettlement?.call(entry, authority);
                } catch (_) {
                  _rememberPendingDurableSettlement(
                    entry: entry,
                    outcomeCandidate: projection.outcomeCandidate,
                    authority: authority,
                  );
                  durableSettlementPending = true;
                  rethrow;
                }
                if (_disposed) return;
              } else {
                await completeWithOutcome(entry, projection.outcomeCandidate);
                if (_disposed) return;
              }
              continue;
            }
            if (projection.disposition ==
                DirectNotificationDisplayRetryDisposition.retired) {
              await retire(entry);
              if (_disposed) return;
              continue;
            }
            failure = const DirectNotificationDisplayRetryableException();
          } catch (error) {
            if (_disposed) return;
            failure = error;
          }
          needsLaterRetry = true;
          inspectDeferred = true;
          failedIdentities.add(_identityOf(entry));
          if (durableSettlementPending) {
            // Transaction A already committed and the file-ledger terminal may
            // already be SETTLED. Advancing the raw READY revision here would
            // invalidate the exact revision retained for transaction B and
            // strand crash recovery. The receipt-only queue owns this retry.
            continue;
          }
          await recordFailure(entry, failure);
          if (_disposed) return;
        }

        if (failedIdentities.isNotEmpty) continue;
        if (batch.length < batchSize && !_dirty) {
          inspectDeferred = true;
          return;
        }
      }
      if (!_disposed && batches >= maxBatchesPerRun) {
        needsLaterRetry = true;
        needsImmediateRetry = true;
      }
    } finally {
      Duration? retryDelay;
      try {
        if (!_disposed && inspectDeferred) {
          final nextAttemptAt = await loadEarliestNextAttemptAt?.call();
          if (_pendingDurableSettlements.isNotEmpty) {
            retryDelay = durableSettlementRetryDelay;
          } else if (nextAttemptAt != null) {
            final untilDue = nextAttemptAt.toUtc().difference(nowUtc().toUtc());
            retryDelay = untilDue.isNegative ? Duration.zero : untilDue;
          } else if (needsLaterRetry) {
            retryDelay = Duration.zero;
          }
        }
      } finally {
        if (_dirty || needsImmediateRetry) retryDelay = Duration.zero;
        _running = null;
        if (!_disposed && retryDelay != null) scheduleRetry?.call(retryDelay);
      }
    }
  }

  Object? _identityOf(T entry) => entryIdentity?.call(entry) ?? entry;

  void _rememberPendingDurableSettlement({
    required T entry,
    required NotificationCompletedOutcomeCandidate? outcomeCandidate,
    required DirectNotificationDurableEffectAuthority authority,
  }) {
    _pendingDurableSettlements.removeWhere(
      (pending) =>
          _identityOf(pending.entry) == _identityOf(entry) &&
          pending.authority.receipt.eventCorrelation ==
              authority.receipt.eventCorrelation &&
          pending.authority.receipt.recordRevision ==
              authority.receipt.recordRevision,
    );
    _pendingDurableSettlements.add(
      _PendingDirectNotificationDurableSettlement<T>(
        entry: entry,
        outcomeCandidate: outcomeCandidate,
        authority: authority,
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _dirty = false;
    _pendingDurableSettlements.clear();
  }
}

final class _PendingDirectNotificationDurableSettlement<T> {
  const _PendingDirectNotificationDurableSettlement({
    required this.entry,
    required this.outcomeCandidate,
    required this.authority,
  });

  final T entry;
  final NotificationCompletedOutcomeCandidate? outcomeCandidate;
  final DirectNotificationDurableEffectAuthority authority;
}

final class DirectNotificationDisplayRetryableException implements Exception {
  const DirectNotificationDisplayRetryableException();
}

final class DirectNotificationDisplayStateUnavailableException
    implements Exception {
  const DirectNotificationDisplayStateUnavailableException();
}
