import '../domain/call_engine.dart';

/// Tracks sustained audio quality changes for one connected call episode.
final class WeakCallConnection {
  static const _transitionWindow = Duration(seconds: 4);
  static const _staleAfter = Duration(seconds: 15);

  bool _isWeak = false;
  int? _lastObservation;
  Duration? _lastFreshAt;
  Duration? _transitionStartedAt;

  bool get isWeak => _isWeak;

  void reset() {
    _isWeak = false;
    _lastObservation = null;
    _lastFreshAt = null;
    _transitionStartedAt = null;
  }

  /// Returns whether the visible warning changed. A repeated report never
  /// advances a transition or extends the life of the displayed warning.
  bool observe({
    required CallQualityBand quality,
    required int? observation,
    required Duration elapsed,
  }) {
    final wasWeak = _isWeak;
    final lastFreshAt = _lastFreshAt;
    if (lastFreshAt != null && elapsed - lastFreshAt >= _staleAfter) {
      _isWeak = false;
      _lastFreshAt = null;
      _transitionStartedAt = null;
    }
    if (quality == CallQualityBand.unknown || observation == null) {
      _transitionStartedAt = null;
      return wasWeak != _isWeak;
    }
    final previous = _lastObservation;
    if (observation <= (previous ?? 0)) return wasWeak != _isWeak;
    _lastObservation = observation;
    _lastFreshAt = elapsed;
    if (previous == null) return wasWeak != _isWeak;
    final transitionBand = _isWeak
        ? CallQualityBand.good
        : CallQualityBand.poor;
    if (quality != transitionBand) {
      _transitionStartedAt = null;
      return wasWeak != _isWeak;
    }

    final startedAt = _transitionStartedAt ??= elapsed;
    if (elapsed - startedAt >= _transitionWindow) {
      _isWeak = !_isWeak;
      _transitionStartedAt = null;
    }
    return wasWeak != _isWeak;
  }
}
