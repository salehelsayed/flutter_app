import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// 182: OS connectivity source for [P2PServiceImpl.networkChangeSignal].
///
/// Maps the platform connectivity stream (iOS `NWPathMonitor` / Android
/// `ConnectivityManager`, surfaced by `connectivity_plus`) to a `Stream<void>`
/// that emits ONCE on each **network-restored** edge — a transition from "no
/// connectivity" into having at least one usable interface. Wiring this into
/// `P2PServiceImpl` makes a foreground connectivity restore immediately drain
/// the relay's stored offline inbox (and re-warm the active peer) instead of
/// waiting for the next ~30s health-check poll or an app resume.
///
/// Only restored edges are surfaced: a connectivity LOSS (`-> none`) and
/// idempotent repeats (still-connected `->` still-connected) are dropped, so the
/// downstream drain/re-warm is not triggered on going offline or on no-op churn.
/// The downstream `onNetworkChanged` handler additionally debounces (a 5s flap
/// floor) and coalesces drains, so an occasional spurious restored edge — or the
/// one emitted at startup when the device is already connected — is harmless.
Stream<void> connectivityRestoredSignal({Connectivity? connectivity}) =>
    restoredEdges((connectivity ?? Connectivity()).onConnectivityChanged);

/// Pure, host-testable edge detector: emits `void` on each transition INTO a
/// connected state from a disconnected (or initial-unknown) state.
///
/// `connectivity_plus` >=5 emits `List<ConnectivityResult>`; the list is treated
/// as connected when it contains any result other than
/// [ConnectivityResult.none]. The detector seeds its prior state as
/// disconnected, so a cold device that is already online emits exactly one
/// restored edge at subscription (harmless — the startup path already drains and
/// the downstream coalesces).
Stream<void> restoredEdges(Stream<List<ConnectivityResult>> source) {
  var wasConnected = false;
  StreamSubscription<List<ConnectivityResult>>? sub;
  final controller = StreamController<void>(
    onCancel: () => sub?.cancel(),
  );
  sub = source.listen(
    (results) {
      final isConnected = results.any((r) => r != ConnectivityResult.none);
      if (isConnected && !wasConnected) {
        controller.add(null);
      }
      wasConnected = isConnected;
    },
    onError: (_) {
      // A connectivity-source error must never crash the app; treat it as no
      // signal (the ~30s health-check poll remains the backstop).
    },
    onDone: controller.close,
  );
  return controller.stream;
}
