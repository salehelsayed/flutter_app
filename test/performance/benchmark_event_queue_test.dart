import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../shared/fakes/lifecycle_bridge.dart';
import 'benchmark_harness.dart';

void main() {
  late BenchmarkHarness harness;
  late LifecycleBridge bridge;
  late P2PServiceImpl service;

  setUp(() {
    harness = BenchmarkHarness();
    bridge = LifecycleBridge();
    service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
  });

  tearDown(() {
    service.dispose();
    harness.dispose();
  });

  group('Benchmark: Event Queue / Delivery', () {
    test('I-Dart-1: Push events arrive at Dart within idle budget', () async {
      bridge.phase = 'startup';
      await service.startNodeCore(testBase64Key, testPeerId);

      final deliveryLags = <int>[];

      for (var i = 0; i < 10; i++) {
        final sw = Stopwatch()..start();
        bridge.onRelayStateChanged?.call({
          'relayState': 'online',
          'healthyRelayCount': 1,
          'watchdogRestartCount': 0,
          'needsGroupRecovery': false,
          'reason': 'heartbeat_$i',
        });
        await Future<void>.delayed(Duration.zero);
        sw.stop();
        deliveryLags.add(sw.elapsedMilliseconds);
      }

      deliveryLags.sort();
      final p95 = harness.percentile(deliveryLags, 95);

      // In fake environment, delivery should be near-instant
      expect(
        p95,
        lessThan(100),
        reason: 'Idle event delivery should be fast',
      );

      // ignore: avoid_print
      print('[BENCHMARK] event_delivery_idle_ms '
          'p50=${harness.percentile(deliveryLags, 50)}ms '
          'p95=${p95}ms (n=${deliveryLags.length})');
    });
  });
}
