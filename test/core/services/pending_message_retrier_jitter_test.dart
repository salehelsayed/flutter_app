import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';

void main() {
  group('jitteredRetryInterval (Finding 05 Phase 4 / P1.6)', () {
    test('stays within ±20% of the base interval over many samples', () {
      const interval = Duration(seconds: 100);
      final random = Random(12345);
      final lo = (interval.inMicroseconds * 0.8).floor();
      final hi = (interval.inMicroseconds * 1.2).ceil();

      for (var i = 0; i < 2000; i++) {
        final jittered = jitteredRetryInterval(interval, random).inMicroseconds;
        expect(jittered, greaterThanOrEqualTo(lo));
        expect(jittered, lessThanOrEqualTo(hi));
      }
    });

    test('produces varied (non-constant) intervals across ticks', () {
      const interval = Duration(seconds: 100);
      final random = Random(1);
      final samples = <int>{
        for (var i = 0; i < 20; i++)
          jitteredRetryInterval(interval, random).inMicroseconds,
      };
      // Jitter must actually vary the cadence, not return a constant.
      expect(samples.length, greaterThan(1));
    });
  });
}
