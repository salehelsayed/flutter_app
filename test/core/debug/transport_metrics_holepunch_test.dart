import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';

/// M1 (NET-REL-02 Option A) — forced-mix baseline with EXACT counts.
///
/// Drives a known forced mix into TransportMetrics and asserts the new
/// hole-punch / relay->direct getters and the baselineReport() line report the
/// EXACT counts (never '> 0'), plus that the existing transport mix is exact.
void main() {
  group('TransportMetrics hole-punch forced-mix (M1)', () {
    test('exact counts for transport mix, hole-punch getters, and report line',
        () {
      final metrics = TransportMetrics();

      // Known forced mix.
      const relayN = 7;
      const directM = 3;
      const attemptsA = 5;
      const successesS = 2;
      const failuresF = 4;
      const upgradesU = 2;

      for (var i = 0; i < relayN; i++) {
        metrics.recordTransport('relay');
      }
      for (var i = 0; i < directM; i++) {
        metrics.recordTransport('direct');
      }
      for (var i = 0; i < attemptsA; i++) {
        metrics.recordHolePunchAttempt();
      }
      for (var i = 0; i < successesS; i++) {
        metrics.recordHolePunchSuccess();
      }
      for (var i = 0; i < failuresF; i++) {
        metrics.recordHolePunchFailure();
      }
      for (var i = 0; i < upgradesU; i++) {
        metrics.recordRelayToDirectUpgrade();
      }

      // Transport mix EXACT (not '>0').
      final mix = metrics.transportMix();
      expect(mix['relay'], relayN);
      expect(mix['direct'], directM);
      expect(mix['wifi'], 0);
      expect(mix['inbox'], 0);
      expect(mix['unknown'], 0);
      expect(metrics.totalTransportSamples, relayN + directM);

      // New getters EXACT.
      expect(metrics.holePunchAttempts, attemptsA);
      expect(metrics.holePunchSuccesses, successesS);
      expect(metrics.holePunchFailures, failuresF);
      expect(metrics.relayToDirectUpgrades, upgradesU);

      // The exact baselineReport() hole-punch line must be present verbatim.
      final report = metrics.baselineReport();
      expect(
        report,
        contains(
          'Hole punch (attempt/success/fail): '
          '$attemptsA/$successesS/$failuresF, '
          'relay->direct upgrades: $upgradesU',
        ),
      );
    });

    test('reset() zeroes the hole-punch counters', () {
      final metrics = TransportMetrics();
      metrics.recordHolePunchAttempt();
      metrics.recordHolePunchSuccess();
      metrics.recordHolePunchFailure();
      metrics.recordRelayToDirectUpgrade();

      metrics.reset();

      expect(metrics.holePunchAttempts, 0);
      expect(metrics.holePunchSuccesses, 0);
      expect(metrics.holePunchFailures, 0);
      expect(metrics.relayToDirectUpgrades, 0);
      expect(
        metrics.baselineReport(),
        contains(
          'Hole punch (attempt/success/fail): 0/0/0, '
          'relay->direct upgrades: 0',
        ),
      );
    });
  });
}
