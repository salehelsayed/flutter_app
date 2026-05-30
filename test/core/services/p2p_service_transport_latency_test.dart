import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';

/// U3 — per-transport latency bucketing.
///
/// Feeds known latency samples (modelling streamOpenMs/writeMs/ackWaitMs roll-up
/// into one end-to-end ms figure) and asserts EXACT median/p95 per transport.
/// The false-result risk is MISLABELING, so a slow sample must land in the
/// correct bucket and never blend into a different transport.
void main() {
  test('per-transport median is exact for fixed inputs', () {
    final metrics = TransportMetrics();
    for (var i = 0; i < 5; i++) {
      metrics.recordSendLatency(transport: 'direct', latencyMs: 40);
    }
    for (var i = 0; i < 5; i++) {
      metrics.recordSendLatency(transport: 'relay', latencyMs: 350);
    }

    expect(metrics.latencyByTransport()['direct']!.sampleCount, 5);
    expect(metrics.latencyByTransport()['direct']!.medianMs, 40);
    expect(metrics.latencyByTransport()['relay']!.sampleCount, 5);
    expect(metrics.latencyByTransport()['relay']!.medianMs, 350);
  });

  test('a slow sample lands in the correct bucket, not a neighbour', () {
    final metrics = TransportMetrics();
    // Many fast direct samples + a single slow relay sample.
    for (var i = 0; i < 10; i++) {
      metrics.recordSendLatency(transport: 'direct', latencyMs: 18);
    }
    metrics.recordSendLatency(transport: 'relay', latencyMs: 1200);

    final byTransport = metrics.latencyByTransport();
    // The slow sample is in relay only.
    expect(byTransport['relay']!.sampleCount, 1);
    expect(byTransport['relay']!.medianMs, 1200);
    // direct stays fast and is untouched by the slow relay sample.
    expect(byTransport['direct']!.sampleCount, 10);
    expect(byTransport['direct']!.medianMs, 18);
    // The slow value never bled into the direct bucket.
    expect(byTransport['direct']!.p95Ms, 18);
  });

  test('p95 reflects the tail for a mixed-latency bucket', () {
    final metrics = TransportMetrics();
    // streamOpen/write/ack roll-up modelled as end-to-end ms per send.
    for (final ms in [10, 20, 30, 40, 100]) {
      metrics.recordSendLatency(transport: 'direct', latencyMs: ms);
    }
    final stats = metrics.latencyByTransport()['direct']!;
    expect(stats.medianMs, 30); // lower median for n=5
    expect(stats.p95Ms, 100); // tail
  });

  test('null/negative latency samples are ignored; 0 is valid', () {
    final metrics = TransportMetrics();
    metrics.recordSendLatency(transport: 'direct', latencyMs: null);
    metrics.recordSendLatency(transport: 'direct', latencyMs: -1);
    metrics.recordSendLatency(transport: 'direct', latencyMs: 0); // 0 is valid
    final stats = metrics.latencyByTransport()['direct']!;
    expect(stats.sampleCount, 1);
    expect(stats.medianMs, 0);
  });

  test('canonical aliases bucket latency the same as the mix', () {
    final metrics = TransportMetrics();
    // 'reuse'→direct, 'local'→wifi (matching transport-mix canonicalization).
    metrics.recordSendLatency(transport: 'reuse', latencyMs: 42);
    metrics.recordSendLatency(transport: 'local', latencyMs: 18);
    expect(metrics.latencyByTransport()['direct']!.medianMs, 42);
    expect(metrics.latencyByTransport()['wifi']!.medianMs, 18);
    // Empty buckets surface as null, never 0.
    expect(metrics.latencyByTransport()['relay']!.medianMs, isNull);
    expect(metrics.latencyByTransport()['inbox']!.medianMs, isNull);
  });
}
