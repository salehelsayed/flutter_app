import 'dart:async';

import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';

/// 407: drains the call mailbox while a call is ringing.
///
/// The relay deliberately sends no wake push to a recipient it considers
/// attached — one that acked an earlier event of the same call, so its live
/// connection is assumed to carry the rest (`recipientAttached`,
/// `go-relay-server/call_control_redis.go:736`). That rule exists to stop a
/// caller's offer/ICE burst re-presenting the call once per event, and it is
/// right for the common case.
///
/// It has no fallback when the live path does not land. Device 2026-09-05
/// 21:21:05Z: the caller cancelled, the terminate stored with `wake: "none"`,
/// and all three direct legs failed, so the ringing iPhone never learned the
/// call was over and rang for nine more seconds until the user declined by
/// hand. Polling during the ring closes that hole wherever the live path
/// fails, not only for this one cause, and costs one mailbox read every
/// [interval] for the ring's bounded lifetime.

/// Cancels one scheduled poll. Kept as a value so tests can drive ticks
/// without a real timer.
final class RingingCallMailboxPollHandle {
  const RingingCallMailboxPollHandle(this.cancel);

  final void Function() cancel;
}

typedef RingingCallMailboxPollSchedule =
    RingingCallMailboxPollHandle Function(
      Duration interval,
      void Function() onTick,
    );

RingingCallMailboxPollHandle _defaultSchedule(
  Duration interval,
  void Function() onTick,
) {
  final timer = Timer.periodic(interval, (_) => onTick());
  return RingingCallMailboxPollHandle(timer.cancel);
}

final class RingingCallMailboxPoller {
  RingingCallMailboxPoller({
    required Future<void> Function() drain,
    this.interval = const Duration(seconds: 2),
    RingingCallMailboxPollSchedule? schedule,
  }) : _drain = drain,
       _schedule = schedule ?? _defaultSchedule;

  final Future<void> Function() _drain;
  final RingingCallMailboxPollSchedule _schedule;
  final Duration interval;

  RingingCallMailboxPollHandle? _handle;
  bool _draining = false;

  /// Feed every session snapshot. Polling runs only while the call rings, in
  /// either direction: a callee's `reject` can be skipped for an attached
  /// caller exactly as a caller's `terminate` was skipped here.
  void onSession(CallSessionSnapshot? snapshot) {
    final ringing = snapshot != null && snapshot.state == CallState.ringing;
    if (ringing) {
      // Already polling this ring: restarting would reset the interval on
      // every unrelated snapshot and could starve the drain entirely.
      _handle ??= _schedule(interval, _onTick);
      return;
    }
    _stop();
  }

  void _onTick() {
    // A slow drain must never stack: the next tick is simply skipped.
    if (_draining) return;
    _draining = true;
    unawaited(
      _drain()
          .catchError((Object _) {
            // Best effort. The next tick tries again, and the wake path and
            // resume drain remain untouched.
          })
          .whenComplete(() => _draining = false),
    );
  }

  void _stop() {
    final handle = _handle;
    _handle = null;
    handle?.cancel();
  }

  void dispose() => _stop();
}
