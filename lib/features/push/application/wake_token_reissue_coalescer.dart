import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// FDC-09 §12 / CV-14 (217 §A2 / A15) — coalesces stream-triggered wake-token
/// re-issue into AT MOST ONE mint+register per short window.
///
/// A new contact (autoAddedStream) or a key rotation (contactKeyUpdatedStream)
/// means the recipient set changed and must be re-minted + re-registered. Firing
/// [issueForContacts] per event would N²-register the full set with the relay on
/// a burst; instead each trigger sets a dirty flag and (re)arms a single timer,
/// so N events within [window] collapse into one re-issue (INV-5: register
/// once-per-cycle, never per-event).
class WakeTokenReissueCoalescer {
  WakeTokenReissueCoalescer({
    required Future<void> Function() reissue,
    this.window = const Duration(milliseconds: 400),
  }) : _reissue = reissue;

  final Future<void> Function() _reissue;
  final Duration window;

  Timer? _timer;
  bool _pending = false;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Coalesce a re-issue: (re)arm a single timer; further triggers within
  /// [window] collapse into the same pending run.
  void trigger() {
    _pending = true;
    _timer?.cancel();
    _timer = Timer(window, _fire);
  }

  void _fire() {
    if (!_pending) return;
    _pending = false;
    // Fire-and-forget: a re-issue failure degrades gracefully (NET-REL-07); the
    // next trigger re-arms.
    unawaited(
      Future<void>.sync(_reissue).catchError((Object error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'WAKE_TOKEN_REISSUE_ERROR',
          details: {'errorType': error.runtimeType.toString()},
        );
      }),
    );
  }

  /// Coalesce a re-issue on every event of [stream].
  void bind<T>(Stream<T> stream) {
    _subscriptions.add(stream.listen((_) => trigger()));
  }

  void dispose() {
    _timer?.cancel();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
  }
}
