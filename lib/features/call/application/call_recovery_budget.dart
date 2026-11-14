/// Read-only remaining time from the canonical reconnect timer's origin.
/// No signaling operation can renew this budget or change its episode owner.
final class CallRecoveryBudget {
  CallRecoveryBudget({
    required Duration duration,
    required Duration Function() monotonicNow,
    required bool Function() isCurrent,
  }) : _duration = duration,
       _monotonicNow = monotonicNow,
       _startedAt = monotonicNow(),
       _isCurrent = isCurrent;

  final Duration _duration;
  final Duration Function() _monotonicNow;
  final Duration _startedAt;
  final bool Function() _isCurrent;

  Duration get remaining {
    if (!_isCurrent()) return Duration.zero;
    final elapsed = _monotonicNow() - _startedAt;
    final remaining = _duration - elapsed;
    if (remaining <= Duration.zero) return Duration.zero;
    // A broken/injected clock must not extend the original timer budget.
    return remaining > _duration ? _duration : remaining;
  }
}
