import 'dart:async';

import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

enum DroppedPushRecoveryDisposition {
  noPending,
  recovered,
  retained,
  superseded,
}

class DroppedPushRecoveryResult {
  const DroppedPushRecoveryResult({
    required this.disposition,
    this.generation,
    this.failureReason,
  });

  final DroppedPushRecoveryDisposition disposition;
  final int? generation;
  final String? failureReason;
}

typedef DirectDroppedPushDrain = Future<DirectInboxDrainOutcome> Function();

/// Feature-neutral projection of a canonical group inbox drain.
///
/// The application composition root maps the groups feature result into this
/// shape so core recovery ownership does not depend on a feature layer.
class DroppedPushGroupDrainOutcome {
  const DroppedPushGroupDrainOutcome({
    required this.isSuccessful,
    required this.hasMorePages,
  });

  final bool isSuccessful;
  final bool hasMorePages;
}

typedef GroupDroppedPushDrain = Future<DroppedPushGroupDrainOutcome> Function();
typedef DroppedPushRecoveryTrigger = Future<void> Function();

/// Retains a trailing recovery poll requested while the broad resume pipeline
/// is already in flight. Requests that arrive during a poll are consumed by a
/// subsequent loop iteration, so a second resume or native signal is not lost.
class DroppedPushRecoveryRepollLatch {
  bool _requested = false;

  void request() {
    _requested = true;
  }

  Future<void> drain({
    required Future<bool> Function() hasPendingRecovery,
    required Future<void> Function() recoverIfPending,
  }) async {
    while (_requested) {
      _requested = false;
      if (await hasPendingRecovery()) {
        await recoverIfPending();
      }
    }
  }
}

/// Re-enters the canonical direct and group inbox pipelines after Android
/// reports that FCM deleted queued wakes.
///
/// The native generation is deliberately acknowledged only when both full
/// drains report truthful exhaustion. The coordinator is single-flight so a
/// notification tap, cold-start poll, and lifecycle resume can safely race.
class DroppedPushRecoveryCoordinator {
  DroppedPushRecoveryCoordinator({
    required DroppedPushRecoveryGateway gateway,
    required Future<void> Function() ensureRuntimeReady,
    required Future<void> Function() ensureTransportHealthy,
    required DirectDroppedPushDrain drainDirectInboxFully,
    required GroupDroppedPushDrain drainGroupInboxFully,
  }) : _gateway = gateway,
       _ensureRuntimeReady = ensureRuntimeReady,
       _ensureTransportHealthy = ensureTransportHealthy,
       _drainDirectInboxFully = drainDirectInboxFully,
       _drainGroupInboxFully = drainGroupInboxFully;

  final DroppedPushRecoveryGateway _gateway;
  final Future<void> Function() _ensureRuntimeReady;
  final Future<void> Function() _ensureTransportHealthy;
  final DirectDroppedPushDrain _drainDirectInboxFully;
  final GroupDroppedPushDrain _drainGroupInboxFully;

  static const int _maxDirectLocalConvergencePasses = 10;
  static const Duration _directLocalConvergenceDelay = Duration(
    milliseconds: 250,
  );

  Future<DroppedPushRecoveryResult>? _inFlight;

  Future<bool> hasPendingRecovery() async {
    try {
      return await _gateway.pendingGeneration() != null;
    } catch (_) {
      // A failed ownership read must not allow an ordinary drain to race an
      // authoritative recovery pass. The subsequent recovery stays fail-closed.
      return true;
    }
  }

  void registerNativeAcceleration([
    DroppedPushRecoveryTrigger? triggerRecovery,
  ]) {
    _gateway.register((_) async {
      final trigger = triggerRecovery;
      if (trigger != null) {
        await trigger();
      } else {
        await recoverIfPending();
      }
    });
  }

  Future<DroppedPushRecoveryResult> recoverIfPending() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final recovery = _recoverIfPending();
    _inFlight = recovery;
    unawaited(
      recovery.whenComplete(() {
        if (identical(_inFlight, recovery)) {
          _inFlight = null;
        }
      }),
    );
    return recovery;
  }

  void dispose() {
    _gateway.dispose();
  }

  Future<DroppedPushRecoveryResult> _recoverIfPending() async {
    int? generation;
    try {
      generation = await _gateway.pendingGeneration();
      if (generation == null) {
        return const DroppedPushRecoveryResult(
          disposition: DroppedPushRecoveryDisposition.noPending,
        );
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'DROPPED_PUSH_RECOVERY_BEGIN',
        details: {'generation': generation},
      );

      try {
        await _ensureRuntimeReady();
        await _ensureTransportHealthy();
      } catch (error) {
        return _retained(
          generation,
          'bootstrap_or_health_failed:${error.runtimeType}',
        );
      }

      DirectInboxDrainOutcome directOutcome;
      try {
        directOutcome = await _drainDirectInboxFully();
        for (
          var pass = 1;
          pass < _maxDirectLocalConvergencePasses &&
              _isTrailingStagedReplayPending(directOutcome);
          pass++
        ) {
          emitFlowEvent(
            layer: 'FL',
            event: 'DROPPED_PUSH_RECOVERY_DIRECT_REPOLL',
            details: {'generation': generation, 'pass': pass + 1},
          );
          await Future<void>.delayed(_directLocalConvergenceDelay);
          directOutcome = await _drainDirectInboxFully();
        }
      } catch (error) {
        directOutcome = DirectInboxDrainOutcome(
          isSuccessful: false,
          hasMore: true,
          failureReason: 'direct_exception:${error.runtimeType}',
        );
      }

      DroppedPushGroupDrainOutcome? groupOutcome;
      Object? groupError;
      try {
        groupOutcome = await _drainGroupInboxFully();
      } catch (error) {
        groupError = error;
      }

      if (!directOutcome.isSuccessful || directOutcome.hasMore) {
        return _retained(
          generation,
          'direct_not_converged:${directOutcome.failureReason ?? 'remaining_pages'}',
        );
      }
      if (groupError != null) {
        return _retained(
          generation,
          'group_exception:${groupError.runtimeType}',
        );
      }
      if (groupOutcome == null ||
          !groupOutcome.isSuccessful ||
          groupOutcome.hasMorePages) {
        return _retained(generation, 'group_not_converged');
      }

      final acknowledged = await _gateway.acknowledgeGeneration(generation);
      if (!acknowledged) {
        int? currentGeneration;
        try {
          currentGeneration = await _gateway.pendingGeneration();
        } catch (_) {
          return _retained(generation, 'generation_ack_failed');
        }
        if (currentGeneration != null && currentGeneration != generation) {
          emitFlowEvent(
            layer: 'FL',
            event: 'DROPPED_PUSH_RECOVERY_SUPERSEDED',
            details: {
              'generation': generation,
              'currentGeneration': currentGeneration,
            },
          );
          return DroppedPushRecoveryResult(
            disposition: DroppedPushRecoveryDisposition.superseded,
            generation: generation,
            failureReason: 'generation_changed_before_ack',
          );
        }
        return _retained(generation, 'generation_ack_failed');
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'DROPPED_PUSH_RECOVERY_COMPLETE',
        details: {'generation': generation},
      );
      return DroppedPushRecoveryResult(
        disposition: DroppedPushRecoveryDisposition.recovered,
        generation: generation,
      );
    } catch (error) {
      if (generation == null) {
        return DroppedPushRecoveryResult(
          disposition: DroppedPushRecoveryDisposition.retained,
          failureReason: 'pending_read_failed:${error.runtimeType}',
        );
      }
      return _retained(generation, 'recovery_exception:${error.runtimeType}');
    }
  }

  bool _isTrailingStagedReplayPending(DirectInboxDrainOutcome outcome) =>
      !outcome.isSuccessful &&
      outcome.hasMore &&
      outcome.failureReason == 'staged_replay_pending';

  DroppedPushRecoveryResult _retained(int generation, String reason) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DROPPED_PUSH_RECOVERY_RETAINED',
      details: {'generation': generation, 'reason': reason},
    );
    return DroppedPushRecoveryResult(
      disposition: DroppedPushRecoveryDisposition.retained,
      generation: generation,
      failureReason: reason,
    );
  }
}
