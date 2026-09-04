import 'dart:async';

import '../domain/call_engine.dart';
import '../domain/call_event.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';
import 'call_audio_controller.dart';

typedef CallAudioSessionSnapshotReader = CallSessionSnapshot? Function();
typedef CallAudioMediaSnapshotReader =
    Future<CallConnectionSnapshot> Function();
typedef CallAudioEventDispatcher = Future<void> Function(CallEvent event);

/// Converts coarse foreground audio-focus intents into canonical reducer
/// events. Recovery still requires the engine's full silence-safe readiness;
/// an audio-session or UI signal alone can never mark a call connected.
final class CallAudioInterruptionCoordinator {
  CallAudioInterruptionCoordinator({
    required Stream<CallAudioInterruptionIntent> intents,
    required CallAudioSessionSnapshotReader readActiveSession,
    required CallAudioMediaSnapshotReader readMediaSnapshot,
    required CallAudioEventDispatcher dispatchEvent,
    required DateTime Function() clock,
  }) : _readActiveSession = readActiveSession,
       _readMediaSnapshot = readMediaSnapshot,
       _dispatchEvent = dispatchEvent,
       _clock = clock {
    _subscription = intents.listen(_onIntent, onError: (_) {});
  }

  final CallAudioSessionSnapshotReader _readActiveSession;
  final CallAudioMediaSnapshotReader _readMediaSnapshot;
  final CallAudioEventDispatcher _dispatchEvent;
  final DateTime Function() _clock;

  late final StreamSubscription<CallAudioInterruptionIntent> _subscription;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  int _eventSequence = 0;
  bool _closed = false;

  void _onIntent(CallAudioInterruptionIntent intent) {
    if (_closed) return;
    _tail = _tail.then((_) => _handle(intent)).catchError((_) {});
  }

  Future<void> _handle(CallAudioInterruptionIntent intent) async {
    if (_closed) return;
    final session = _readActiveSession();
    final callId = session?.callId;
    if (session == null || callId == null || session.isTerminal) return;

    CallEventType? type;
    switch (intent) {
      case CallAudioInterruptionIntent.pausedReconnect:
        if (session.state == CallState.connected) {
          type = CallEventType.mediaLost;
        }
      case CallAudioInterruptionIntent.recover:
        CallConnectionSnapshot media;
        try {
          media = await _readMediaSnapshot();
        } catch (_) {
          return;
        }
        if (!media.isMediaReady) return;
        type = switch (session.state) {
          CallState.negotiating => CallEventType.mediaConnected,
          CallState.reconnecting => CallEventType.mediaRecovered,
          _ => null,
        };
    }
    if (_closed || type == null) return;
    await _dispatchEvent(
      CallEvent(
        type: type,
        eventId: 'audio-focus-${callId.value}-${_eventSequence++}',
        occurredAt: _clock().toUtc(),
        callId: callId,
        contactPeerId: session.contactPeerId,
      ),
    );
  }

  Future<void> close() {
    _closed = true;
    return _closeFuture ??= _closeOnce();
  }

  Future<void> _closeOnce() async {
    await _subscription.cancel();
    // An in-flight handler may be awaiting coordinator.dispatch while this
    // close runs inside terminal cleanup on that same serialized coordinator
    // lane. Fencing new work and canceling ingress is sufficient; awaiting the
    // handler here would form a cleanup cycle. Its guarded tail absorbs errors,
    // and any queued event is ignored by terminal dominance once cleanup exits.
  }

  @override
  String toString() => 'CallAudioInterruptionCoordinator(closed: $_closed)';
}
