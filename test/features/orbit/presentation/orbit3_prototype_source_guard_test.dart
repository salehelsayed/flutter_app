import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // QW-13 (navigation-hangs-5 / animations-repaint-3): the experimental Orbit3
  // "One Circle" tab must NOT appear in release builds. The flag is gated on
  // `kDebugMode` so it is `true` only under debug/test and `false` in release.
  //
  // HONEST LIMITATION: `kDebugMode` is `true` under `flutter test`, so the
  // runtime release-absence is NOT host-observable. This is a SOURCE-TEXT guard
  // that locks the gating expression; release-absence is verified manually
  // (`flutter run --release` → no Orbit3 tab).
  test('orbit3 prototype flag is gated on kDebugMode (not hard-coded true)', () {
    final source =
        File('lib/features/orbit3/orbit3_prototype.dart').readAsStringSync();

    expect(
      source,
      contains("import 'package:flutter/foundation.dart';"),
      reason: 'kDebugMode requires the foundation import',
    );
    expect(source, contains('kOrbit3PrototypeEnabled = kDebugMode'));
    expect(
      source,
      isNot(contains('kOrbit3PrototypeEnabled = true')),
      reason: 'the flag must not be hard-coded true (ships the tab in release)',
    );
  });
}
