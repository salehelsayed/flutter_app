import 'dart:async';

import '../../../core/services/network_path_source.dart';
import '../domain/call_event.dart';
import 'call_coordinator.dart';

/// Feeds default-network path epochs into the active call as reducer events.
///
/// No active call means no event: a path change with no call to recover is
/// not a call concern, and a late outcome never reaches a call that ended.
/// The wait for relay readiness lives in the call snapshot
/// (`pendingPathEpoch`), so hang-up, remote terminate, replacement, shutdown
/// and the reconnect timeout reduce at once; nothing here awaits readiness.
final class CallNetworkPathBinding {
  CallNetworkPathBinding({
    required Stream<NetworkPathOutcome> outcomes,
    required this.coordinator,
    required this.clock,
  }) {
    _subscription = outcomes.listen(
      _onOutcome,
      onError: (Object _) {
        // The source already drops malformed pushes; nothing to recover here.
      },
    );
  }

  final CallCoordinator coordinator;
  final DateTime Function() clock;
  late final StreamSubscription<NetworkPathOutcome> _subscription;

  /// Makes each delivered outcome its own reducer event: a replayed attempt
  /// repeats an earlier attempt's stage, generation and epoch.
  int _sequence = 0;

  void _onOutcome(NetworkPathOutcome outcome) {
    final active = coordinator.activeSession;
    final callId = active?.callId;
    if (active == null || callId == null || active.isTerminal) return;
    final type = switch (outcome.stage) {
      NetworkPathStage.changing => CallEventType.networkPathChanged,
      NetworkPathStage.ready => CallEventType.networkPathReady,
      NetworkPathStage.failed => CallEventType.networkPathFailed,
      NetworkPathStage.previousLost => CallEventType.networkPreviousPathLost,
    };
    unawaited(
      coordinator
          .dispatch(
            CallEvent(
              type: type,
              eventId:
                  'network-path-${outcome.stage.name}-'
                  '${outcome.generation}-${outcome.epoch}-${_sequence++}',
              occurredAt: clock(),
              callId: callId,
              pathEpoch: outcome.epoch,
            ),
          )
          .then<void>(
            (_) {},
            onError: (Object _) {
              // A full queue or a disposed coordinator drops the hint; the
              // reconnect deadline and the next epoch remain authoritative.
            },
          ),
    );
  }

  Future<void> dispose() => _subscription.cancel();
}
