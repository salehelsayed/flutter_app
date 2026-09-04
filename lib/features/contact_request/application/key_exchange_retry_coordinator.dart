import 'package:flutter_app/core/utils/flow_event_emitter.dart';

typedef PerformKeyExchangeRetry = Future<int> Function();

/// Coalesces key-exchange repair retries triggered by multiple recovery paths.
///
/// The app can legitimately ask for the same repair burst from app resume and
/// from reconnect handling a few seconds later. This coordinator prevents a
/// recent non-zero repair run from being repeated immediately, while still
/// allowing later retries if the earlier attempt found nothing to send.
class KeyExchangeRetryCoordinator {
  KeyExchangeRetryCoordinator({
    required PerformKeyExchangeRetry performRetry,
    this.cooldown = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _performRetry = performRetry,
       _now = now ?? DateTime.now;

  final PerformKeyExchangeRetry _performRetry;
  final Duration cooldown;
  final DateTime Function() _now;

  Future<int>? _inFlight;
  Future<int>? _freshAfterInFlight;
  DateTime? _lastNonZeroRetryAt;
  int _lastNonZeroRetryCount = 0;

  Future<int> retryNow({required String trigger, bool requireFresh = false}) {
    if (requireFresh) return _retryFresh(trigger);

    final inFlight = _inFlight;
    if (inFlight != null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'KEY_EXCHANGE_RETRY_COORDINATOR_JOIN_IN_FLIGHT',
        details: {'trigger': trigger},
      );
      return inFlight;
    }

    final lastNonZeroRetryAt = _lastNonZeroRetryAt;
    if (lastNonZeroRetryAt != null) {
      final elapsed = _now().difference(lastNonZeroRetryAt);
      if (elapsed < cooldown) {
        emitFlowEvent(
          layer: 'FL',
          event: 'KEY_EXCHANGE_RETRY_COORDINATOR_SUPPRESSED',
          details: {
            'trigger': trigger,
            'cooldownMs': cooldown.inMilliseconds,
            'elapsedMs': elapsed.inMilliseconds,
            'lastCount': _lastNonZeroRetryCount,
          },
        );
        return Future.value(0);
      }
    }

    return _startRun(trigger);
  }

  /// Starts after any attempt that was already running when this request was
  /// made. Multiple fresh requests waiting on that same older attempt share
  /// one follow-up run. Cooldown never suppresses the follow-up because the
  /// caller has just durably created new repair work.
  Future<int> _retryFresh(String trigger) {
    final inFlight = _inFlight;
    if (inFlight == null) return _startRun(trigger);

    final queued = _freshAfterInFlight;
    if (queued != null) return queued;

    late final Future<int> followUp;
    followUp = () async {
      try {
        await inFlight;
      } catch (_) {
        // A fresh repair still owns a post-failure attempt.
      }
      if (identical(_freshAfterInFlight, followUp)) {
        _freshAfterInFlight = null;
      }

      final newerInFlight = _inFlight;
      if (newerInFlight != null && !identical(newerInFlight, inFlight)) {
        return newerInFlight;
      }
      return _startRun(trigger);
    }();
    _freshAfterInFlight = followUp;
    return followUp;
  }

  Future<int> _startRun(String trigger) {
    late final Future<int> future;
    future = _run(trigger).whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  Future<int> _run(String trigger) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'KEY_EXCHANGE_RETRY_COORDINATOR_START',
      details: {'trigger': trigger},
    );

    try {
      final count = await _performRetry();
      if (count > 0) {
        _lastNonZeroRetryAt = _now();
        _lastNonZeroRetryCount = count;
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'KEY_EXCHANGE_RETRY_COORDINATOR_COMPLETE',
        details: {'trigger': trigger, 'count': count},
      );
      return count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'KEY_EXCHANGE_RETRY_COORDINATOR_ERROR',
        details: {'trigger': trigger, 'error': e.toString()},
      );
      rethrow;
    }
  }
}
