import 'dart:async';

/// Runs the all-pending group-key-repair sweep and returns how many repairs
/// were repaired this pass.
typedef GroupPendingKeyRepairSweep = Future<int> Function();

/// Injectable timer factory (the test seam). Defaults to [Timer.new].
typedef GroupPendingKeyRepairTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// Drives [runSweep] on a backoff schedule so persisted pending repairs keep
/// re-firing without a fresh key-update/invite event.
///
/// Behaviour:
/// - `start()` schedules the first sweep at `schedule[0]`.
/// - While a sweep repairs nothing (returns 0), the timer advances through
///   `schedule` and then clamps at the final (longest) interval, firing
///   indefinitely as a cheap safety net (the sweep is a no-op when nothing is
///   pending).
/// - As soon as a sweep repairs at least one message (returns > 0) the timer
///   stops — the backoff has done its job and live triggers take over.
/// - A throwing sweep is treated as "repaired 0" and keeps backing off.
///
/// There is no clock-injection precedent in this stack, so the test hook is the
/// injectable [createTimer] factory + the `fakeAsync` zone.
class GroupPendingKeyRepairBackoffTimer {
  final GroupPendingKeyRepairSweep runSweep;
  final List<Duration> schedule;
  final GroupPendingKeyRepairTimerFactory createTimer;

  Timer? _timer;
  int _scheduleIndex = 0;
  bool _running = false;
  bool _sweepInFlight = false;

  GroupPendingKeyRepairBackoffTimer({
    required this.runSweep,
    List<Duration>? schedule,
    GroupPendingKeyRepairTimerFactory? createTimer,
  }) : schedule =
           schedule ??
           const [
             Duration(seconds: 5),
             Duration(seconds: 30),
             Duration(minutes: 2),
           ],
       createTimer = createTimer ?? Timer.new {
    assert(this.schedule.isNotEmpty, 'backoff schedule must not be empty');
  }

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    _scheduleIndex = 0;
    _scheduleNext();
  }

  void _scheduleNext() {
    if (!_running) return;
    final delay = schedule[_scheduleIndex.clamp(0, schedule.length - 1)];
    _timer = createTimer(delay, _onTick);
  }

  Future<void> _onTick() async {
    if (!_running || _sweepInFlight) return;
    _sweepInFlight = true;
    var repaired = 0;
    try {
      repaired = await runSweep();
    } catch (_) {
      // A failed sweep is non-fatal — keep backing off and try again later.
      repaired = 0;
    } finally {
      _sweepInFlight = false;
    }
    if (!_running) return;
    if (repaired > 0) {
      stop();
      return;
    }
    if (_scheduleIndex < schedule.length - 1) {
      _scheduleIndex++;
    }
    _scheduleNext();
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();
}
