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
  DateTime? _lastNonZeroRetryAt;
  int _lastNonZeroRetryCount = 0;

  Future<int> retryNow({required String trigger}) {
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

    final future = _run(trigger);
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
    } finally {
      _inFlight = null;
    }
  }
}
