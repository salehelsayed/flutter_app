/// 191 (Fix D1): a retryable Firebase-readiness latch.
///
/// The pre-191 `ensureFirebaseReady` in `main.dart` latched
/// `firebaseInitialized = true` BEFORE calling `Firebase.initializeApp()`, so a
/// single thrown init — a transient failure at cold start — permanently marked
/// Firebase "ready" and no later call ever retried. The process then stayed
/// deaf to push for its whole lifetime (foreground drain never armed, token
/// coordinator never built). This unit latches ONLY after a successful
/// [initialize], so a failed attempt leaves the latch clear and the next
/// [ensureReady] retries.
///
/// On the first success it notifies every registered on-ready listener exactly
/// once. Firebase becoming ready is the ONLY event that flips
/// `Firebase.apps.isEmpty` false, so that event is what the push-listener arm
/// rides (the "third arm point" — see [addOnReadyListener] and PushListenerArmer).
class FirebaseReadiness {
  FirebaseReadiness({
    required Future<void> Function() initialize,
    void Function()? onFirstSuccess,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _initialize = initialize,
       _onError = onError {
    if (onFirstSuccess != null) {
      _onReadyListeners.add(onFirstSuccess);
    }
  }

  final Future<void> Function() _initialize;
  final void Function(Object error, StackTrace stackTrace)? _onError;
  final List<void Function()> _onReadyListeners = <void Function()>[];

  bool _ready = false;

  /// Whether a successful [initialize] has latched.
  bool get isReady => _ready;

  /// Registers [listener] to run once Firebase is (or becomes) ready. If
  /// readiness has already latched, [listener] runs synchronously now — so a
  /// late registration (the third arm point wiring itself up after a race)
  /// still fires.
  void addOnReadyListener(void Function() listener) {
    if (_ready) {
      listener();
      return;
    }
    _onReadyListeners.add(listener);
  }

  /// Runs [initialize]; on success latches ready and notifies every registered
  /// on-ready listener exactly once. If [initialize] throws, the failure is
  /// reported to [onError] and the latch stays CLEAR so the next call retries
  /// (the error is swallowed so callers on the startup path are not broken).
  Future<void> ensureReady() async {
    if (_ready) {
      return;
    }
    try {
      await _initialize();
    } catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
      // Latch stays clear → the next ensureReady() retries.
      return;
    }
    _ready = true;
    final listeners = List<void Function()>.of(_onReadyListeners);
    _onReadyListeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}
