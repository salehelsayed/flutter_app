import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/bridge/fake_bridge.dart';
import 'benchmark_harness.dart';
import 'timing_test_bridge.dart';

void main() {
  late BenchmarkHarness harness;

  setUp(() {
    harness = BenchmarkHarness();
  });

  tearDown(() {
    harness.dispose();
  });

  group('Benchmark: Bridge Crossing', () {
    test('F1: Single bridge call completes and is trackable', () async {
      final bridge = FakeBridge();
      final sw = Stopwatch()..start();
      final response =
          await bridge.send(jsonEncode({'cmd': 'node:status'}));
      sw.stop();

      final parsed = jsonDecode(response) as Map<String, dynamic>;
      expect(parsed['ok'], isTrue);
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(0));
    });

    test('F2: 100 sequential bridge calls produce timing distribution',
        () async {
      final bridge = FakeBridge();
      final timings = <int>[];

      for (var i = 0; i < 100; i++) {
        final sw = Stopwatch()..start();
        await bridge.send(jsonEncode({'cmd': 'node:status'}));
        sw.stop();
        timings.add(sw.elapsedMilliseconds);
      }

      expect(timings, hasLength(100));
      timings.sort();

      final p50 = harness.percentile(timings, 50);
      final p95 = harness.percentile(timings, 95);
      final p99 = harness.percentile(timings, 99);

      // FakeBridge should be near-instant
      expect(p99, lessThan(50));

      // ignore: avoid_print
      print('[BENCHMARK] bridge_crossing_fake_ms '
          'p50=${p50}ms p95=${p95}ms p99=${p99}ms (n=100)');
    });

    test('F3: Bridge crossing under concurrent load', () async {
      final bridge = TimingTestBridge(
        commandDelays: {'node:status': const Duration(milliseconds: 1)},
      );

      final futures = List.generate(
        10,
        (_) => bridge.send(jsonEncode({'cmd': 'node:status'})),
      );

      final results = await Future.wait(futures);
      expect(results, hasLength(10));

      for (final r in results) {
        final parsed = jsonDecode(r) as Map<String, dynamic>;
        expect(parsed['ok'], isTrue);
      }
    });
  });
}
