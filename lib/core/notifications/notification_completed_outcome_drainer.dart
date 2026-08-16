import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../utils/flow_event_emitter.dart';
import 'notification_completed_outcome.dart';
import 'notification_completed_outcome_outbox_repository.dart';

typedef SendNotificationCompletedOutcome =
    Future<Map<String, dynamic>> Function({required String correlation});

typedef RunNotificationCompletedOutcomeNetworkAction =
    Future<void> Function(Future<void> Function() action);

/// Live platform consumer read-back consulted at each drain kick. It shares
/// the one `OpaqueWakePlatformConsumerReadiness` resolver with the outcome
/// producer and paired capability registration, so all three enable and
/// retire together on the same binding/role epoch.
typedef ReadNotificationOutcomePlatformConsumerReady = Future<bool> Function();

/// The single production composition boundary for v116 draining.
///
/// Tests use this same factory across database reopen, so admission, repository
/// ownership, in-flight coalescing, and the account/network wrapper cannot
/// silently diverge from bootstrap wiring.
final class NotificationCompletedOutcomeDrainComposition {
  NotificationCompletedOutcomeDrainComposition._({required this.drain});

  factory NotificationCompletedOutcomeDrainComposition({
    required Database database,
    required SendNotificationCompletedOutcome sendOutcome,
    required bool admissionEnabled,
    ReadNotificationOutcomePlatformConsumerReady? readPlatformConsumerReady,
    RunNotificationCompletedOutcomeNetworkAction? runNetworkAction,
    DateTime Function()? nowUtc,
  }) {
    final repository = NotificationCompletedOutcomeOutboxRepository(
      database: database,
      now: nowUtc,
    );
    final drainer = NotificationCompletedOutcomeDrainer(
      repository: repository,
      sendOutcome: sendOutcome,
      nowUtc: nowUtc,
    );
    final networkAction =
        runNetworkAction ??
        (Future<void> Function() action) {
          return action();
        };
    Future<void>? running;
    var followUpRequested = false;
    Future<void> drain() {
      final current = running;
      if (current != null) {
        // The outer owner spans the account/network wrapper, whose teardown can
        // outlive the inner drainer. Preserve a follow-up at both layers so a
        // post-commit kick cannot fall between those two lifetimes.
        followUpRequested = true;
        drainer._requestFollowUpIfRunning();
        return current;
      }

      late final Future<void> next;
      Future<void> run() async {
        var passes = 0;
        try {
          // The live epoch read happens once per coalesced drain owner: an
          // unready or rotated platform consumer retires draining together
          // with the producer and registration, and the rows stay durable
          // for the next ready kick. Joined kicks share this owner's read.
          if (readPlatformConsumerReady != null) {
            var consumerReady = false;
            try {
              consumerReady = await readPlatformConsumerReady();
            } on Object {
              consumerReady = false;
            }
            if (!consumerReady) return;
          }
          do {
            followUpRequested = false;
            passes++;
            await networkAction(drainer.drain);
          } while (followUpRequested && passes < 2);
        } finally {
          final needsAnotherOwner = followUpRequested;
          if (identical(running, next)) {
            running = null;
            if (needsAnotherOwner) {
              // Keep the joined Future finite. A kick during the second pass
              // transfers to a fresh, non-overlapping bounded owner instead
              // of extending this account/network action indefinitely.
              Future<void>.microtask(drain).ignore();
            }
          }
        }
      }

      next = run();
      running = next;
      return next;
    }

    return NotificationCompletedOutcomeDrainComposition._(
      drain: admissionEnabled ? drain : null,
    );
  }

  final Future<void> Function()? drain;
}

/// Bounded, process-local drain owner for the installation-local v116 outbox.
///
/// The repository remains the durable authority. Concurrent lifecycle kicks
/// join one in-flight pass, while a kick received during that pass requests one
/// more bounded read so an outcome committed mid-pass is not stranded.
final class NotificationCompletedOutcomeDrainer {
  NotificationCompletedOutcomeDrainer({
    required NotificationCompletedOutcomeOutboxRepository repository,
    required SendNotificationCompletedOutcome sendOutcome,
    DateTime Function()? nowUtc,
    this.batchSize = 8,
    this.maxBatchesPerRun = 4,
  }) : _repository = repository,
       _sendOutcome = sendOutcome,
       _nowUtc = nowUtc ?? DateTime.now {
    if (batchSize <= 0 || maxBatchesPerRun <= 0) {
      throw ArgumentError('drain bounds must be positive');
    }
  }

  final NotificationCompletedOutcomeOutboxRepository _repository;
  final SendNotificationCompletedOutcome _sendOutcome;
  final DateTime Function() _nowUtc;
  final int batchSize;
  final int maxBatchesPerRun;

  Future<void>? _running;
  bool _dirty = false;

  /// Sends ready outcomes without exposing category or event authority on wire.
  ///
  /// A row is removed only after every configured relay reports an accepted,
  /// idempotent, or legacy-unsupported terminal result. Every other response is
  /// retained with revision-exact bounded retry state.
  Future<void> drain() {
    final running = _running;
    if (running != null) {
      _dirty = true;
      return running;
    }

    late final Future<void> next;
    next = _drainBounded().whenComplete(() {
      if (identical(_running, next)) _running = null;
    });
    _running = next;
    return next;
  }

  void _requestFollowUpIfRunning() {
    if (_running != null) _dirty = true;
  }

  Future<void> _drainBounded() async {
    var completed = 0;
    var retained = 0;
    var batches = 0;
    final attempted = <String>{};
    var filledBatch = false;

    do {
      _dirty = false;
      final loaded = await _repository.loadReady(
        limit: batchSize + attempted.length,
      );
      final batch = loaded
          .where((entry) => !attempted.contains(entry.wakeCorrelation))
          .take(batchSize)
          .toList(growable: false);
      if (batch.isEmpty) {
        if (_dirty && batches < maxBatchesPerRun) continue;
        break;
      }
      batches++;
      filledBatch = batch.length == batchSize;

      attempted.addAll(batch.map((entry) => entry.wakeCorrelation));
      // One bounded batch enters the bridge concurrently. A slow or partial
      // relay participant for an older row must not head-of-line block a fresh
      // completed notification, while [batchSize] keeps native fanout bounded.
      final results = await Future.wait(batch.map(_drainEntry));
      for (final result in results) {
        completed += result.completed;
        retained += result.retained;
      }
    } while (batches < maxBatchesPerRun && (_dirty || filledBatch));

    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_COMPLETED_OUTCOME_DRAIN_RESULT',
      details: <String, Object?>{
        'completed': completed,
        'retained': retained,
        'batches': batches,
      },
    );
  }

  Future<({int completed, int retained})> _drainEntry(
    NotificationCompletedOutcomeOutboxEntry entry,
  ) async {
    var terminal = false;
    try {
      final response = await _sendOutcome(correlation: entry.wakeCorrelation);
      terminal = _isAllParticipantTerminal(response);
    } catch (_) {
      terminal = false;
    }

    if (terminal) {
      try {
        final removed = await _repository.completeIfExact(entry);
        return (completed: removed ? 1 : 0, retained: 0);
      } catch (_) {
        // Exact custody remains durable; a later shared trigger retries it.
        return (completed: 0, retained: 1);
      }
    }

    await _recordRetry(entry);
    return (completed: 0, retained: 1);
  }

  Future<void> _recordRetry(
    NotificationCompletedOutcomeOutboxEntry entry,
  ) async {
    final now = _nowUtc().toUtc();
    if (!entry.expiresAt.isAfter(now)) return;

    final exponent = math.min(entry.retryCount, 6);
    final delaySeconds = math.min(300, 5 * (1 << exponent));
    final latest = entry.expiresAt.subtract(const Duration(microseconds: 1));
    final proposed = now.add(Duration(seconds: delaySeconds));
    final nextAttemptAt = proposed.isBefore(latest) ? proposed : latest;
    if (!nextAttemptAt.isAfter(now)) return;

    try {
      await _repository.recordRetryIfExact(
        expected: entry,
        lastErrorCode: 'wake_outcome_retryable',
        nextAttemptAt: nextAttemptAt,
      );
    } catch (_) {
      // Durable custody is already retained. A later lifecycle trigger retries
      // the exact row; no private bridge or relay detail is logged here.
    }
  }
}

bool _isAllParticipantTerminal(Map<String, dynamic> response) {
  final participantCount = response['participantCount'];
  final acceptedCount = response['acceptedCount'];
  final unsupportedCount = response['unsupportedCount'];
  final retryableCount = response['retryableCount'];
  return response['ok'] == true &&
      response['allParticipantsTerminal'] == true &&
      participantCount is int &&
      participantCount > 0 &&
      acceptedCount is int &&
      acceptedCount >= 0 &&
      unsupportedCount is int &&
      unsupportedCount >= 0 &&
      retryableCount is int &&
      retryableCount == 0 &&
      acceptedCount + unsupportedCount == participantCount;
}
