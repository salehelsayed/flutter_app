enum DirectNotificationDisplayRetryDisposition {
  completed,
  retired,
  retryLater,
}

typedef LoadDirectNotificationDisplayBatch<T> =
    Future<List<T>> Function({required int limit});
typedef ProjectDirectNotificationDisplay<T> =
    Future<DirectNotificationDisplayRetryDisposition> Function(T entry);

/// Bounded, single-flight retry engine shared by direct display and
/// reconciliation custody. Durable rows remain the authority across restarts.
final class DirectNotificationDisplayRetryCoordinator<T> {
  DirectNotificationDisplayRetryCoordinator({
    required this.loadReady,
    required this.project,
    required this.complete,
    Future<void> Function(T entry)? retire,
    required this.recordFailure,
    this.entryIdentity,
    this.loadEarliestNextAttemptAt,
    this.scheduleRetry,
    DateTime Function()? nowUtc,
    this.batchSize = 20,
    this.maxBatchesPerRun = 4,
  }) : retire = retire ?? complete,
       nowUtc = nowUtc ?? DateTime.now {
    if (batchSize <= 0 || maxBatchesPerRun <= 0) {
      throw ArgumentError('batch bounds must be positive');
    }
  }

  final LoadDirectNotificationDisplayBatch<T> loadReady;
  final ProjectDirectNotificationDisplay<T> project;
  final Future<void> Function(T entry) complete;
  final Future<void> Function(T entry) retire;
  final Future<void> Function(T entry, Object error) recordFailure;
  final Object? Function(T entry)? entryIdentity;
  final Future<DateTime?> Function()? loadEarliestNextAttemptAt;
  final void Function(Duration delay)? scheduleRetry;
  final DateTime Function() nowUtc;
  final int batchSize;
  final int maxBatchesPerRun;

  Future<void>? _running;
  bool _dirty = false;
  bool _disposed = false;

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
          try {
            final disposition = await project(entry);
            if (_disposed) return;
            if (disposition ==
                DirectNotificationDisplayRetryDisposition.completed) {
              await complete(entry);
              if (_disposed) return;
              continue;
            }
            if (disposition ==
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
          if (nextAttemptAt != null) {
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

  void dispose() {
    _disposed = true;
    _dirty = false;
  }
}

final class DirectNotificationDisplayRetryableException implements Exception {
  const DirectNotificationDisplayRetryableException();
}

final class DirectNotificationDisplayStateUnavailableException
    implements Exception {
  const DirectNotificationDisplayStateUnavailableException();
}
