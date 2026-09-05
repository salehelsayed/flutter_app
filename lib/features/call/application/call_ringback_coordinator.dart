import 'dart:async';

import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';

/// Ringback is the tone a caller hears while the far end rings.
///
/// The platform plays it; this port only starts and stops it. Both calls are
/// best effort: the call itself never waits on them.
abstract interface class CallRingbackPort {
  /// Returns false when the platform refused or has no tone player.
  Future<bool> start(CallId callId);

  /// Returns false when nothing was playing for [callId].
  Future<bool> stop(CallId callId);
}

enum CallRingbackAction { start, stop }

/// Outcome wire names: `ok`, `refused`, `failed`.
typedef CallRingbackResultObserver =
    void Function(CallRingbackAction action, String outcome);

/// Only the caller hears ringback, and only once the far end reported that it
/// rings (`remoteRinging`). `inviting` stays silent, like a phone whose call
/// has not reached the network yet.
bool ringbackWanted(CallSessionSnapshot session) =>
    !session.isTerminal &&
    session.callId != null &&
    session.direction == CallDirection.outgoing &&
    session.state == CallState.ringing;

/// Turns call snapshots into exactly one start and one stop per ringing
/// outgoing call. Port calls run one at a time, in order, so a stop can never
/// overtake the start it belongs to.
///
/// Fail-closed toward silence: a refused or failing start is not retried per
/// snapshot (the next call rings back again), while a failing stop keeps the
/// coordinator armed so the next snapshot and [dispose] try again. The
/// platforms also stop the tone on their own terminal paths.
final class CallRingbackCoordinator {
  CallRingbackCoordinator({
    required CallRingbackPort port,
    CallRingbackResultObserver? onResult,
  }) : _port = port,
       _onResult = onResult;

  final CallRingbackPort _port;
  final CallRingbackResultObserver? _onResult;
  Future<void> _tail = Future<void>.value();
  CallId? _armedCallId;
  CallId? _stopQueuedFor;
  bool _disposed = false;

  /// True from an issued start until a stop for that call has settled.
  bool get isArmed => _armedCallId != null;

  /// Completes once every issued port call has settled.
  Future<void> get settled => _tail;

  void onSession(CallSessionSnapshot session) {
    if (_disposed) return;
    final armed = _armedCallId;
    if (ringbackWanted(session)) {
      final callId = session.callId!;
      if (armed == callId) return;
      if (armed != null) _enqueueStop(armed);
      _armedCallId = callId;
      _enqueue(CallRingbackAction.start, callId);
      return;
    }
    if (armed != null) _enqueueStop(armed);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final armed = _armedCallId;
    if (armed != null) _enqueueStop(armed);
    await _tail;
  }

  void _enqueueStop(CallId callId) {
    if (_stopQueuedFor == callId) return;
    _stopQueuedFor = callId;
    _enqueue(CallRingbackAction.stop, callId);
  }

  void _enqueue(CallRingbackAction action, CallId callId) {
    _tail = _tail.then<void>((_) => _run(action, callId));
  }

  Future<void> _run(CallRingbackAction action, CallId callId) async {
    String outcome;
    try {
      final accepted = switch (action) {
        CallRingbackAction.start => await _port.start(callId),
        CallRingbackAction.stop => await _port.stop(callId),
      };
      outcome = accepted ? 'ok' : 'refused';
      // A stop that found nothing playing still means silence.
      if (action == CallRingbackAction.stop && _armedCallId == callId) {
        _armedCallId = null;
      }
    } catch (_) {
      outcome = 'failed';
    } finally {
      if (action == CallRingbackAction.stop && _stopQueuedFor == callId) {
        _stopQueuedFor = null;
      }
    }
    _onResult?.call(action, outcome);
  }
}
