import 'dart:async';

import '../domain/call_session_snapshot.dart';

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

/// Discovers stored invites while idle in the foreground, and drains
/// throughout the canonical call lifecycle. The relay suppresses iOS
/// wakes after the first acknowledgement, including for SDP, ICE and hang-up.
/// Keeping one non-overlapping poll alive preserves that fallback even when
/// direct signaling fails after ringing or the native call hides the app UI.
final class RingingCallMailboxPoller {
  RingingCallMailboxPoller({
    required Future<void> Function() drain,
    this.interval = const Duration(seconds: 2),
    this.foregroundIdleInterval = const Duration(seconds: 4),
    RingingCallMailboxPollSchedule? schedule,
  }) : _drain = drain,
       _schedule = schedule ?? _defaultSchedule;

  final Future<void> Function() _drain;
  final RingingCallMailboxPollSchedule _schedule;
  final Duration interval;
  final Duration foregroundIdleInterval;

  RingingCallMailboxPollHandle? _handle;
  Duration? _scheduledInterval;
  bool _draining = false;
  bool _disposed = false;

  /// Feed canonical snapshots independently of foreground presentation.
  void onSession(CallSessionSnapshot? snapshot, {bool foreground = false}) {
    if (_disposed) return;
    final live = snapshot != null && !snapshot.isIdle && !snapshot.isTerminal;
    final nextInterval = live
        ? interval
        : (foreground ? foregroundIdleInterval : null);
    // Unrelated snapshots must not reset the interval and starve retrieval.
    if (_scheduledInterval == nextInterval) return;
    _stop();
    if (nextInterval == null) return;
    _scheduledInterval = nextInterval;
    _handle = _schedule(nextInterval, _onTick);
  }

  void _onTick() {
    // A slow drain must never stack: the next tick is simply skipped.
    if (_handle == null || _draining) return;
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
    _scheduledInterval = null;
    handle?.cancel();
  }

  void dispose() {
    _disposed = true;
    _stop();
  }
}
