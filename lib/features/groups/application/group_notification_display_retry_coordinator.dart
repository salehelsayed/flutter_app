import 'dart:async';

import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';

enum GroupNotificationDisplayRetryDisposition { completed, retired, retryLater }

/// One canonical projection decision plus its immutable completed-effect
/// candidate. Keeping both in one value prevents retry-generation side maps.
final class GroupNotificationDisplayProjectionResult {
  const GroupNotificationDisplayProjectionResult._({
    required this.disposition,
    this.outcomeCandidate,
  });

  const GroupNotificationDisplayProjectionResult.completed({
    NotificationCompletedOutcomeCandidate? outcomeCandidate,
  }) : this._(
         disposition: GroupNotificationDisplayRetryDisposition.completed,
         outcomeCandidate: outcomeCandidate,
       );

  const GroupNotificationDisplayProjectionResult.retired()
    : this._(disposition: GroupNotificationDisplayRetryDisposition.retired);

  const GroupNotificationDisplayProjectionResult.retryLater()
    : this._(disposition: GroupNotificationDisplayRetryDisposition.retryLater);

  final GroupNotificationDisplayRetryDisposition disposition;
  final NotificationCompletedOutcomeCandidate? outcomeCandidate;
}

typedef LoadGroupNotificationDisplayBatch<T> =
    Future<List<T>> Function({required int limit});
typedef LoadEarliestGroupNotificationDisplayNextAttemptAt =
    Future<DateTime?> Function();
typedef ProjectGroupNotificationDisplay<T> =
    Future<GroupNotificationDisplayProjectionResult> Function(T entry);
typedef CompleteGroupNotificationDisplayWithOutcome<T> =
    Future<void> Function(
      T entry,
      NotificationCompletedOutcomeCandidate? outcome,
    );
typedef RecordGroupNotificationDisplayFailure<T> =
    Future<void> Function(T entry, Object error);
typedef ScheduleGroupNotificationDisplayRetry = void Function(Duration delay);
typedef GroupNotificationDisplayEntryIdentity<T> = Object? Function(T entry);

/// Runs bounded, single-flight canonical notification re-projection.
///
/// A trigger arriving during a pass sets a dirty generation and joins the same
/// future. Each trigger performs at most [maxBatchesPerRun] batches. A failure
/// or retryable ownership contention defers that entry and excludes its
/// logical identity from the rest of the pass. Subsequent loads overscan those
/// excluded identities so an oldest failing row cannot spin or starve later
/// ready custody. Remaining custody is retained by the repository and a
/// delayed/lifecycle trigger is requested through [scheduleRetry].
final class GroupNotificationDisplayRetryCoordinator<T> {
  GroupNotificationDisplayRetryCoordinator({
    required this.loadReady,
    required this.project,
    required this.completeWithOutcome,
    required this.retire,
    required this.recordFailure,
    this.entryIdentity,
    this.loadEarliestNextAttemptAt,
    this.scheduleRetry,
    DateTime Function()? nowUtc,
    this.batchSize = 20,
    this.maxBatchesPerRun = 4,
  }) : nowUtc = nowUtc ?? DateTime.now {
    if (batchSize <= 0) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be positive');
    }
    if (maxBatchesPerRun <= 0) {
      throw ArgumentError.value(
        maxBatchesPerRun,
        'maxBatchesPerRun',
        'must be positive',
      );
    }
  }

  final LoadGroupNotificationDisplayBatch<T> loadReady;
  final ProjectGroupNotificationDisplay<T> project;
  final CompleteGroupNotificationDisplayWithOutcome<T> completeWithOutcome;
  final Future<void> Function(T entry) retire;
  final RecordGroupNotificationDisplayFailure<T> recordFailure;
  final GroupNotificationDisplayEntryIdentity<T>? entryIdentity;
  final LoadEarliestGroupNotificationDisplayNextAttemptAt?
  loadEarliestNextAttemptAt;
  final ScheduleGroupNotificationDisplayRetry? scheduleRetry;
  final DateTime Function() nowUtc;
  final int batchSize;
  final int maxBatchesPerRun;

  Future<void>? _running;
  bool _dirty = false;
  bool _disposed = false;

  bool get isRunning => _running != null;

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
    var inspectDeferredCustody = false;
    var needsImmediateRetry = false;
    var batches = 0;
    final failedEntryIdentities = <Object?>{};
    try {
      while (!_disposed && batches < maxBatchesPerRun) {
        // Consume the generation that requested this batch. A new trigger that
        // arrives while load/project is in flight will set it again.
        _dirty = false;
        final loadedBatch = await loadReady(
          limit: batchSize + failedEntryIdentities.length,
        );
        if (loadedBatch.isEmpty) {
          if (_dirty) continue;
          inspectDeferredCustody = true;
          return;
        }
        batches++;

        final batch = loadedBatch
            .where(
              (entry) => !failedEntryIdentities.contains(_identityOf(entry)),
            )
            .take(batchSize)
            .toList(growable: false);
        if (batch.isEmpty) {
          if (_dirty) continue;
          inspectDeferredCustody = true;
          return;
        }

        for (final entry in batch) {
          if (_disposed) return;
          if (failedEntryIdentities.contains(_identityOf(entry))) continue;
          late Object failure;
          try {
            final projection = await project(entry);
            // Disposal is a hard mutation fence. A projection that was already
            // in flight may finish its read/native call, but it cannot retire
            // or rewrite durable custody after its owner has been torn down.
            if (_disposed) return;
            if (projection.disposition ==
                GroupNotificationDisplayRetryDisposition.completed) {
              await completeWithOutcome(entry, projection.outcomeCandidate);
              if (_disposed) return;
              continue;
            }
            if (projection.disposition ==
                GroupNotificationDisplayRetryDisposition.retired) {
              await retire(entry);
              if (_disposed) return;
              continue;
            }
            failure = const GroupNotificationDisplayRetryableException();
          } catch (error) {
            if (_disposed) return;
            failure = error;
          }
          if (_disposed) return;
          needsLaterRetry = true;
          inspectDeferredCustody = true;
          failedEntryIdentities.add(_identityOf(entry));
          await recordFailure(entry, failure);
          if (_disposed) return;
        }

        // A failed oldest row may still be returned when its retry CAS lost.
        // Keep loading with bounded overscan until later ready custody has had
        // a chance to progress, or this run reaches its batch bound.
        if (failedEntryIdentities.isNotEmpty) continue;
        if (batch.length < batchSize && !_dirty) {
          inspectDeferredCustody = true;
          return;
        }
      }

      // A full final batch may have successors even when no concurrent trigger
      // arrived. Leave them durable and request another bounded pass.
      if (!_disposed && batches >= maxBatchesPerRun) {
        needsLaterRetry = true;
        needsImmediateRetry = true;
      }
    } finally {
      Duration? retryDelay;
      try {
        if (!_disposed && inspectDeferredCustody) {
          final nextAttemptAt = await loadEarliestNextAttemptAt?.call();
          if (nextAttemptAt != null) {
            final untilDue = nextAttemptAt.toUtc().difference(nowUtc().toUtc());
            retryDelay = untilDue.isNegative ? Duration.zero : untilDue;
          } else if (needsLaterRetry) {
            // A failed CAS can remove the deferred row between record/query.
            // Keep one immediate bounded follow-up for other ready custody; an
            // actually empty follow-up observes no deadline and arms no timer.
            retryDelay = Duration.zero;
          }
        }
      } finally {
        if (_dirty || needsImmediateRetry) retryDelay = Duration.zero;
        _running = null;
        if (!_disposed && retryDelay != null) {
          scheduleRetry?.call(retryDelay);
        }
      }
    }
  }

  Object? _identityOf(T entry) {
    final identity = entryIdentity;
    return identity == null ? entry : identity(entry);
  }

  void dispose() {
    _disposed = true;
    _dirty = false;
  }
}

final class GroupNotificationDisplayRetryableException implements Exception {
  const GroupNotificationDisplayRetryableException();

  @override
  String toString() => 'group notification display remains retryable';
}

final class GroupNotificationDisplayStateUnavailableException
    implements Exception {
  const GroupNotificationDisplayStateUnavailableException();

  @override
  String toString() =>
      'canonical group notification state is not available yet';
}
