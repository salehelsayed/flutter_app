import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// 182: OS connectivity source for [P2PServiceImpl.networkChangeSignal].
///
/// Maps the platform connectivity stream (iOS `NWPathMonitor` / Android
/// `ConnectivityManager`, surfaced by `connectivity_plus`) to a `Stream<void>`
/// that emits on connectivity restoration or a change of usable interfaces.
/// Wiring this into `P2PServiceImpl` reconnects the relay, drains its stored
/// inbox and re-warms the active peer without waiting for foreground polling.
///
/// A connectivity LOSS (`-> none`) and idempotent interface repeats are dropped, so the
/// downstream drain/re-warm is not triggered on going offline or on no-op churn.
/// The downstream `onNetworkChanged` handler additionally debounces (a 5s flap
/// floor) and coalesces drains, so an occasional spurious restored edge — or the
/// one emitted at startup when the device is already connected — is harmless.
Stream<void> connectivityRestoredSignal({Connectivity? connectivity}) =>
    restoredEdges((connectivity ?? Connectivity()).onConnectivityChanged);

/// Pure, host-testable detector of restoration and connected interface changes.
///
/// `connectivity_plus` >=5 emits `List<ConnectivityResult>`; the list is treated
/// as connected when it contains any result other than
/// [ConnectivityResult.none]. The detector seeds its prior state as
/// disconnected, so a cold device that is already online emits exactly one
/// restored edge at subscription (harmless — the startup path already drains and
/// the downstream coalesces).
Stream<void> restoredEdges(Stream<List<ConnectivityResult>> source) {
  var previousInterfaces = <ConnectivityResult>{};
  StreamSubscription<List<ConnectivityResult>>? sub;
  final controller = StreamController<void>(onCancel: () => sub?.cancel());
  sub = source.listen(
    (results) {
      final interfaces = results
          .where((result) => result != ConnectivityResult.none)
          .toSet();
      final changed =
          interfaces.length != previousInterfaces.length ||
          !interfaces.containsAll(previousInterfaces);
      if (interfaces.isNotEmpty && changed) {
        controller.add(null);
      }
      previousInterfaces = interfaces;
    },
    onError: (_) {
      // A connectivity-source error must never crash the app; treat it as no
      // signal (the ~30s health-check poll remains the backstop).
    },
    onDone: controller.close,
  );
  return controller.stream;
}
