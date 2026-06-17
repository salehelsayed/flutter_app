import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// G-D regression lock: every test file under `test/` and `integration_test/`
/// must be classified by `scripts/run_test_gates.sh classify_path`, so the
/// `completeness-check` gate stays GREEN. This guards against:
///   * a newly-added device proof / simulator under integration_test/ slipping
///     past the manual-proof + simulator branches, and
///   * a feature-root / core-root test landing in a location no gate sweeps.
///
/// It shells out to the gate script (the single source of truth) rather than
/// re-implementing the classification, so the lock cannot drift from the gate.
void main() {
  test(
    'run_test_gates.sh completeness-check classifies every test file (PASS)',
    () {
      final scriptFile = File('scripts/run_test_gates.sh');
      expect(
        scriptFile.existsSync(),
        isTrue,
        reason:
            'completeness gate script must exist at scripts/run_test_gates.sh '
            '(test must run from the package root)',
      );

      final result = Process.runSync('bash', [
        'scripts/run_test_gates.sh',
        'completeness-check',
      ]);

      final stdout = result.stdout.toString();
      final stderr = result.stderr.toString();

      expect(
        result.exitCode,
        0,
        reason:
            'completeness-check must exit 0 — unclassified test files were '
            'reported:\n$stdout$stderr',
      );
      expect(
        stdout,
        contains('Completeness check PASS.'),
        reason: 'expected the PASS sentinel in:\n$stdout',
      );
      expect(
        stdout,
        isNot(contains('Unmatched test files:')),
        reason:
            'classify_path left test files unclassified — add a branch (proof / '
            'simulator / feature-root / core-root) or register them in a gate '
            'array:\n$stdout',
      );
    },
  );
}
