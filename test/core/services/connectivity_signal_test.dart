import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/connectivity_signal.dart';

void main() {
  group('182 connectivity restored-edge detector', () {
    // TC-182-07: emits on restored edges only — never on loss or no-op repeats.
    test(
      'TC-182-07: emits on restored edges only, never on loss/no-op',
      () async {
        final source = StreamController<List<ConnectivityResult>>();
        final emissions = <void>[];
        final sub = restoredEdges(source.stream).listen(emissions.add);

        source.add([ConnectivityResult.none]); //   start offline → no emit
        source.add([ConnectivityResult.wifi]); //   none→wifi    → RESTORED (1)
        source.add([ConnectivityResult.wifi]); //   wifi→wifi    → no-op
        source.add([ConnectivityResult.none]); //   wifi→none    → loss
        source.add([ConnectivityResult.mobile]); // none→mobile  → RESTORED (2)
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          emissions.length,
          2,
          reason:
              'exactly two restored edges (none->wifi, none->mobile); a loss '
              '(->none) and a no-op repeat must NOT emit',
        );

        await sub.cancel();
        await source.close();
      },
    );

    // Corroborating: an already-connected first event emits one startup edge,
    // and a subsequent restore after a real loss emits again (the detector is
    // not stuck-on after the first emit).
    test(
      'TC-182-07b: already-connected start emits once; re-restore after loss '
      'emits again',
      () async {
        final source = StreamController<List<ConnectivityResult>>();
        final emissions = <void>[];
        final sub = restoredEdges(source.stream).listen(emissions.add);

        source.add([ConnectivityResult.wifi]); //   start online → RESTORED (1)
        source.add([ConnectivityResult.none]); //   loss
        source.add([ConnectivityResult.wifi]); //   restore again → RESTORED (2)
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, 2);

        await sub.cancel();
        await source.close();
      },
    );

    // The detector cancels its upstream subscription when the consumer cancels
    // (no leak): closing the consumer's subscription stops the source listen.
    test('TC-182-07c: cancelling the signal cancels the upstream', () async {
      final source = StreamController<List<ConnectivityResult>>();
      final sub = restoredEdges(source.stream).listen((_) {});
      await sub.cancel();
      expect(source.hasListener, isFalse);
      await source.close();
    });
  });
}
