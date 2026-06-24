import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // QW-13 (navigation-hangs-5 / animations-repaint-3): the experimental Orbit2
  // tab ships a heavy-blur prototype that must NOT appear in release builds. The
  // flag is gated on `kDebugMode` so it is `true` only under debug/test and
  // `false` in release.
  //
  // HONEST LIMITATION: `kDebugMode` is `true` under `flutter test`, so the
  // runtime release-absence is NOT host-observable. This is a SOURCE-TEXT guard
  // that locks the gating expression; release-absence is verified manually
  // (`flutter run --release` → no Orbit2 tab).
  test('orbit2 prototype flag is gated on kDebugMode (not hard-coded true)', () {
    final source =
        File('lib/features/orbit2/orbit2_prototype.dart').readAsStringSync();

    expect(
      source,
      contains("import 'package:flutter/foundation.dart';"),
      reason: 'kDebugMode requires the foundation import',
    );
    expect(source, contains('kOrbit2PrototypeEnabled = kDebugMode'));
    expect(
      source,
      isNot(contains('kOrbit2PrototypeEnabled = true')),
      reason: 'the flag must not be hard-coded true (ships the tab in release)',
    );
  });
}
