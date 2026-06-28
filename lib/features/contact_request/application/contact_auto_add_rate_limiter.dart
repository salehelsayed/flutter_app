/// In-memory rate limiter for tap-free contact auto-adds (171).
///
/// A flood of distinct-peer v2 contact requests could otherwise silently
/// auto-add an unbounded number of contacts. This caps the number of auto-adds
/// within a sliding [window]; over the cap the listener falls back to the
/// manual dialog (NOT a silent drop), so nothing is lost — the user just taps.
///
/// Scope is intentionally GLOBAL (not per-peer): same-peer / same-message
/// duplicates are already deduped upstream by the listener's msgId replay
/// cache (and a peer that auto-adds once becomes a contact, so step-8
/// short-circuits all of their later requests). The only thing left to bound
/// is many DISTINCT peers flooding at once — a global window does exactly that.
///
/// In-memory by design: a fresh process resets the window. The spam window is
/// per-session, so persistence would add a DB migration for no real benefit.
class ContactAutoAddRateLimiter {
  ContactAutoAddRateLimiter({
    this.maxPerWindow = 20,
    this.window = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  /// Maximum number of auto-adds permitted within [window].
  final int maxPerWindow;

  /// Sliding window over which [maxPerWindow] is enforced.
  final Duration window;

  final DateTime Function() _clock;
  final List<DateTime> _recent = <DateTime>[];

  /// Returns true if an auto-add is allowed right now, recording it against the
  /// window. Returns false once [maxPerWindow] is reached within [window];
  /// callers must then fall back to the manual dialog.
  bool tryAcquire() {
    final now = _clock();
    _recent.removeWhere((t) => now.difference(t) > window);
    if (_recent.length >= maxPerWindow) {
      return false;
    }
    _recent.add(now);
    return true;
  }
}
