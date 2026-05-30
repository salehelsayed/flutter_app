import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';

/// Unit tests for [TransportMetrics] — the pure, aggregate-only diagnostics
/// service. Every assertion checks EXACT counts/values (never `> 0`) because the
/// false-result risk for this feature is MISLABELING.
void main() {
  group('transportMix canonicalization (exact counts)', () {
    test('zero-fills all canonical buckets before any recording', () {
      final metrics = TransportMetrics();
      expect(metrics.transportMix(), {
        'direct': 0,
        'relay': 0,
        'wifi': 0,
        'inbox': 0,
        'unknown': 0,
      });
      expect(metrics.totalTransportSamples, 0);
    });

    test('canonical aliases collapse: local→wifi, reuse→direct', () {
      final metrics = TransportMetrics();
      metrics.recordTransport('local');
      metrics.recordTransport('reuse');
      expect(metrics.transportMix(), {
        'direct': 1,
        'relay': 0,
        'wifi': 1,
        'inbox': 0,
        'unknown': 0,
      });
      expect(metrics.totalTransportSamples, 2);
    });

    test('null and unrecognized transports increment unknown only', () {
      final metrics = TransportMetrics();
      metrics.recordTransport(null);
      metrics.recordTransport('weird');
      metrics.recordTransport('');
      expect(metrics.transportMix(), {
        'direct': 0,
        'relay': 0,
        'wifi': 0,
        'inbox': 0,
        'unknown': 3,
      });
      expect(metrics.totalTransportSamples, 3);
    });

    test('case/whitespace is normalized', () {
      final metrics = TransportMetrics();
      metrics.recordTransport('DIRECT');
      metrics.recordTransport('  relay ');
      metrics.recordTransport('Inbox');
      expect(metrics.transportMix()['direct'], 1);
      expect(metrics.transportMix()['relay'], 1);
      expect(metrics.transportMix()['inbox'], 1);
    });

    test('a known mix produces the exact census', () {
      final metrics = TransportMetrics();
      metrics.recordTransport('direct');
      metrics.recordTransport('direct');
      metrics.recordTransport('relay');
      metrics.recordTransport('inbox');
      expect(metrics.transportMix(), {
        'direct': 2,
        'relay': 1,
        'wifi': 0,
        'inbox': 1,
        'unknown': 0,
      });
    });
  });

  group('rungDistribution canonicalization (exact counts)', () {
    test('zero-fills all canonical rungs', () {
      final metrics = TransportMetrics();
      expect(metrics.rungDistribution(), {
        'reuse': 0,
        'local_race': 0,
        'direct_race': 0,
        'relay_probe': 0,
        'inbox_fallback': 0,
        'failed': 0,
      });
    });

    test('sendPath labels map to canonical rungs', () {
      final metrics = TransportMetrics();
      metrics.recordRung('reuse');
      metrics.recordRung('local');
      metrics.recordRung('direct');
      metrics.recordRung('relay');
      metrics.recordRung('inbox');
      metrics.recordRung('unknown-sendpath');
      expect(metrics.rungDistribution(), {
        'reuse': 1,
        'local_race': 1,
        'direct_race': 1,
        'relay_probe': 1,
        'inbox_fallback': 1,
        'failed': 1,
      });
    });
  });

  group('send-attempt legs (exact counts)', () {
    test('zero-fills all canonical legs before any recording', () {
      final metrics = TransportMetrics();
      expect(metrics.attemptCounts(), {
        'reuse': 0,
        'local': 0,
        'direct': 0,
        'relay_probe': 0,
        'inbox': 0,
      });
      expect(metrics.attemptFailureCounts(), {
        'reuse': 0,
        'local': 0,
        'direct': 0,
        'relay_probe': 0,
        'inbox': 0,
      });
    });

    test('records attempts and failures independently per leg', () {
      final metrics = TransportMetrics();
      // direct tried 3 times, failed 2; relay_probe tried once, succeeded.
      metrics.recordAttempt(leg: 'direct', succeeded: false);
      metrics.recordAttempt(leg: 'direct', succeeded: false);
      metrics.recordAttempt(leg: 'direct', succeeded: true);
      metrics.recordAttempt(leg: 'relay_probe', succeeded: true);
      expect(metrics.attemptCounts()['direct'], 3);
      expect(metrics.attemptFailureCounts()['direct'], 2);
      expect(metrics.attemptCounts()['relay_probe'], 1);
      expect(metrics.attemptFailureCounts()['relay_probe'], 0);
    });

    test(
      'a leg attempted and failed is visible even when no transport delivered '
      'via it (the direct-failed-but-relay-won signal)',
      () {
        final metrics = TransportMetrics();
        // direct failed, relay probe delivered: delivered mix shows only relay,
        // but the attempt counts reveal direct WAS tried and failed.
        metrics.recordAttempt(leg: 'direct', succeeded: false);
        metrics.recordAttempt(leg: 'relay_probe', succeeded: true);
        metrics.recordTransport('relay');
        expect(metrics.transportMix()['direct'], 0); // delivered-only is blind
        expect(metrics.attemptCounts()['direct'], 1); // but the attempt is not
        expect(metrics.attemptFailureCounts()['direct'], 1);
      },
    );

    test('unrecognized leg is ignored (no bucket invented)', () {
      final metrics = TransportMetrics();
      metrics.recordAttempt(leg: 'teleport', succeeded: false);
      expect(metrics.attemptCounts(), {
        'reuse': 0,
        'local': 0,
        'direct': 0,
        'relay_probe': 0,
        'inbox': 0,
      });
      expect(metrics.attemptCounts().containsKey('teleport'), isFalse);
    });
  });

  group('latency stats (exact median/p95)', () {
    test('empty bucket yields null median/p95 and zero count', () {
      final metrics = TransportMetrics();
      final stats = metrics.latencyByTransport()['direct']!;
      expect(stats.sampleCount, 0);
      expect(stats.medianMs, isNull);
      expect(stats.p95Ms, isNull);
    });

    test('known sequence yields exact median and p95', () {
      final metrics = TransportMetrics();
      for (final ms in [10, 20, 30, 40, 100]) {
        metrics.recordSendLatency(transport: 'direct', latencyMs: ms);
      }
      final stats = metrics.latencyByTransport()['direct']!;
      expect(stats.sampleCount, 5);
      // lower median for odd n=5 → index (5-1)~/2 = 2 → 30
      expect(stats.medianMs, 30);
      // p95 index = ((5-1)*95/100).ceil() = ceil(3.8) = 4 → 100
      expect(stats.p95Ms, 100);
    });

    test('single sample is its own median and p95', () {
      final metrics = TransportMetrics();
      metrics.recordSendLatency(transport: 'relay', latencyMs: 350);
      final stats = metrics.latencyByTransport()['relay']!;
      expect(stats.sampleCount, 1);
      expect(stats.medianMs, 350);
      expect(stats.p95Ms, 350);
    });

    test('null and negative latency samples are ignored', () {
      final metrics = TransportMetrics();
      metrics.recordSendLatency(transport: 'direct', latencyMs: null);
      metrics.recordSendLatency(transport: 'direct', latencyMs: -5);
      expect(metrics.latencyByTransport()['direct']!.sampleCount, 0);
    });

    test('latency is bucketed by transport, not blended', () {
      final metrics = TransportMetrics();
      metrics.recordSendLatency(transport: 'direct', latencyMs: 40);
      metrics.recordSendLatency(transport: 'relay', latencyMs: 350);
      expect(metrics.latencyByTransport()['direct']!.medianMs, 40);
      expect(metrics.latencyByTransport()['relay']!.medianMs, 350);
    });

    test('reservoir is capped at maxSamplesPerTransport and stays computable', () {
      final metrics = TransportMetrics(maxSamplesPerTransport: 256);
      for (var i = 0; i < 300; i++) {
        metrics.recordSendLatency(transport: 'direct', latencyMs: 100);
      }
      final stats = metrics.latencyByTransport()['direct']!;
      expect(stats.sampleCount, 256);
      // All samples identical → median/p95 computed without throwing.
      expect(stats.medianMs, 100);
      expect(stats.p95Ms, 100);
    });
  });

  group('LAN availability snapshot', () {
    test('defaults to empty (inactive, 0 peers)', () {
      final metrics = TransportMetrics();
      expect(metrics.lanAvailability.discoveryActive, isFalse);
      expect(metrics.lanAvailability.discoveredPeerCount, 0);
    });

    test('updateLanAvailability replaces the snapshot', () {
      final metrics = TransportMetrics();
      metrics.updateLanAvailability(
        const LanAvailabilitySnapshot(
          discoveryActive: true,
          discoveredPeerCount: 2,
        ),
      );
      expect(metrics.lanAvailability.discoveryActive, isTrue);
      expect(metrics.lanAvailability.discoveredPeerCount, 2);
    });

    test('suspectedPermissionDenied defaults to false (P4)', () {
      final metrics = TransportMetrics();
      expect(metrics.lanAvailability.suspectedPermissionDenied, isFalse);
      // Existing 2-arg construction (no third field) stays valid and defaults
      // the heuristic flag to false.
      metrics.updateLanAvailability(
        const LanAvailabilitySnapshot(
          discoveryActive: true,
          discoveredPeerCount: 0,
        ),
      );
      expect(metrics.lanAvailability.suspectedPermissionDenied, isFalse);
    });

    test('const empty carries suspectedPermissionDenied false (P4)', () {
      expect(
        LanAvailabilitySnapshot.empty.suspectedPermissionDenied,
        isFalse,
      );
    });

    test('updateLanAvailability surfaces suspectedPermissionDenied (P4)', () {
      final metrics = TransportMetrics();
      metrics.updateLanAvailability(
        const LanAvailabilitySnapshot(
          discoveryActive: true,
          discoveredPeerCount: 0,
          suspectedPermissionDenied: true,
        ),
      );
      expect(metrics.lanAvailability.discoveryActive, isTrue);
      expect(metrics.lanAvailability.discoveredPeerCount, 0);
      expect(metrics.lanAvailability.suspectedPermissionDenied, isTrue);
    });
  });

  group('baselineReport', () {
    test('emits exact percentages that sum to 100 for a known mix', () {
      final metrics = TransportMetrics();
      // {direct:5, relay:3, wifi:1, inbox:0, unknown:1} → N=10
      for (var i = 0; i < 5; i++) {
        metrics.recordTransport('direct');
      }
      for (var i = 0; i < 3; i++) {
        metrics.recordTransport('relay');
      }
      metrics.recordTransport('wifi');
      metrics.recordTransport('unknown');

      final report = metrics.baselineReport();
      expect(report, contains('Transport mix (N=10)'));
      expect(report, contains('50% direct'));
      expect(report, contains('30% relay'));
      expect(report, contains('10% wifi'));
      expect(report, contains('0% inbox'));
      expect(report, contains('10% unknown'));

      // Percentages must sum to exactly 100.
      final pctMatches = RegExp(r'(\d+)% ').allMatches(report).toList();
      final sumPercent = pctMatches.fold<int>(
        0,
        (acc, m) => acc + int.parse(m.group(1)!),
      );
      expect(sumPercent, 100);
    });

    test('N=0 reports no data', () {
      final metrics = TransportMetrics();
      expect(metrics.baselineReport(), contains('Transport mix (N=0): no data'));
    });

    test('includes rung counts and LAN line', () {
      final metrics = TransportMetrics();
      metrics.recordTransport('direct');
      metrics.recordRung('reuse');
      metrics.updateLanAvailability(
        const LanAvailabilitySnapshot(
          discoveryActive: true,
          discoveredPeerCount: 2,
        ),
      );
      final report = metrics.baselineReport();
      expect(report, contains('Fallback rungs:'));
      expect(report, contains('reuse 1'));
      expect(report, contains('LAN: discovery active, 2 peers'));
      // P4: heuristic absent → no perm suffix on the LAN line.
      expect(report, isNot(contains('suspected-denied')));
    });

    test('appends perm: suspected-denied only when flag is true (P4)', () {
      final metrics = TransportMetrics();
      metrics.recordTransport('direct');
      metrics.updateLanAvailability(
        const LanAvailabilitySnapshot(
          discoveryActive: true,
          discoveredPeerCount: 0,
          suspectedPermissionDenied: true,
        ),
      );
      final report = metrics.baselineReport();
      expect(
        report,
        contains('LAN: discovery active, 0 peers, perm: suspected-denied'),
      );
    });

    test('omits perm suffix when suspectedPermissionDenied is false (P4)', () {
      final metrics = TransportMetrics();
      metrics.recordTransport('direct');
      metrics.updateLanAvailability(
        const LanAvailabilitySnapshot(
          discoveryActive: true,
          discoveredPeerCount: 0,
        ),
      );
      final report = metrics.baselineReport();
      expect(report, contains('LAN: discovery active, 0 peers'));
      expect(report, isNot(contains('suspected-denied')));
    });

    test('includes the send-attempt (tried/failed) line', () {
      final metrics = TransportMetrics();
      metrics.recordAttempt(leg: 'direct', succeeded: false);
      metrics.recordAttempt(leg: 'direct', succeeded: false);
      metrics.recordAttempt(leg: 'relay_probe', succeeded: true);
      final report = metrics.baselineReport();
      expect(report, contains('Send attempts (tried/failed):'));
      expect(report, contains('direct 2/2'));
      expect(report, contains('relay_probe 1/0'));
    });
  });

  group('reset', () {
    test('clears all counters, samples, and the LAN snapshot', () {
      final metrics = TransportMetrics();
      metrics.recordTransport('direct');
      metrics.recordRung('relay');
      metrics.recordSendLatency(transport: 'direct', latencyMs: 40);
      metrics.recordAttempt(leg: 'direct', succeeded: false);
      metrics.updateLanAvailability(
        const LanAvailabilitySnapshot(
          discoveryActive: true,
          discoveredPeerCount: 3,
        ),
      );

      metrics.reset();

      expect(metrics.totalTransportSamples, 0);
      expect(metrics.transportMix().values.every((v) => v == 0), isTrue);
      expect(metrics.rungDistribution().values.every((v) => v == 0), isTrue);
      expect(metrics.latencyByTransport()['direct']!.sampleCount, 0);
      expect(metrics.attemptCounts().values.every((v) => v == 0), isTrue);
      expect(
        metrics.attemptFailureCounts().values.every((v) => v == 0),
        isTrue,
      );
      expect(metrics.lanAvailability.discoveryActive, isFalse);
      expect(metrics.lanAvailability.discoveredPeerCount, 0);
    });
  });
}
