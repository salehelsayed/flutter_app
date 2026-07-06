@Tags(['host'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// FDC-09 §12 / CV-14 (217 §B4 / A18) — a thin host wrapper so the wake-token
// binary-freshness gate auto-globs into core-host-all. It shells out to
// scripts/check_wake_token_binary_freshness.sh, which asserts the checked-in
// gomobile binaries (iOS xcframework device+sim, macOS mirror, Android AAR)
// carry `InboxStoreDetailedWithWakeToken` + `RegisterWakeTokens`. `params.WakeToken`
// changes no exported header symbol, so a stale rebuild would silently drop the
// attached token with zero failing functional test — this converts that into a
// real gate. Skips gracefully off a POSIX host (the CI/host command is the
// source of truth).
void main() {
  test('shipped gomobile binaries carry the CV-14 wake-token symbols', () async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      markTestSkipped('binary-freshness gate runs on a POSIX host / CI only');
      return;
    }
    final script = File('scripts/check_wake_token_binary_freshness.sh');
    if (!script.existsSync()) {
      markTestSkipped('freshness script not found from cwd ${Directory.current.path}');
      return;
    }

    final result = await Process.run('bash', [script.path]);
    expect(
      result.exitCode,
      0,
      reason:
          'wake-token binary-freshness gate failed — shipped binaries are stale.\n'
          'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
  });
}
