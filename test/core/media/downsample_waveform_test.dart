import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/downsample_waveform.dart';

void main() {
  group('downsampleWaveform', () {
    test('empty input returns empty output', () {
      expect(downsampleWaveform([], 0), isEmpty);
    });

    test('empty input with positive target returns zeros', () {
      final result = downsampleWaveform([], 5);
      expect(result, hasLength(5));
      expect(result, everyElement(0.0));
    });

    test('input shorter than target pads with zeros on the left', () {
      final result = downsampleWaveform([0.5, 0.8], 5);
      expect(result, hasLength(5));
      // Left-padded with zeros, original values on the right
      expect(result[0], 0.0);
      expect(result[1], 0.0);
      expect(result[2], 0.0);
      expect(result[3], 0.5);
      expect(result[4], 0.8);
    });

    test('input exactly target size returns a copy', () {
      final input = [0.1, 0.2, 0.3, 0.4, 0.5];
      final result = downsampleWaveform(input, 5);
      expect(result, hasLength(5));
      expect(result, orderedEquals([0.1, 0.2, 0.3, 0.4, 0.5]));
      // Should be a copy, not the same list
      expect(identical(result, input), isFalse);
    });

    test('input longer than target averages buckets evenly', () {
      // 10 samples → 5 buckets → average pairs
      final input = [0.0, 1.0, 0.2, 0.8, 0.4, 0.6, 0.1, 0.9, 0.3, 0.7];
      final result = downsampleWaveform(input, 5);
      expect(result, hasLength(5));
      expect(result[0], closeTo(0.5, 0.001)); // (0.0+1.0)/2
      expect(result[1], closeTo(0.5, 0.001)); // (0.2+0.8)/2
      expect(result[2], closeTo(0.5, 0.001)); // (0.4+0.6)/2
      expect(result[3], closeTo(0.5, 0.001)); // (0.1+0.9)/2
      expect(result[4], closeTo(0.5, 0.001)); // (0.3+0.7)/2
    });

    test('always returns exactly targetSize values', () {
      for (final inputLen in [0, 1, 3, 7, 50, 100, 200]) {
        final input = List.generate(inputLen, (i) => i / (inputLen + 1));
        final result = downsampleWaveform(input, 50);
        expect(result, hasLength(50), reason: 'inputLen=$inputLen');
      }
    });

    test('values stay in [0.0, 1.0] range', () {
      final input = List.generate(100, (i) => (i % 2 == 0) ? 0.0 : 1.0);
      final result = downsampleWaveform(input, 25);
      for (final v in result) {
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v, lessThanOrEqualTo(1.0));
      }
    });

    test('uneven bucket sizes are handled correctly', () {
      // 7 samples → 3 buckets: sizes 3, 2, 2 (or similar distribution)
      final input = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7];
      final result = downsampleWaveform(input, 3);
      expect(result, hasLength(3));
      // Each bucket should be a reasonable average
      for (final v in result) {
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v, lessThanOrEqualTo(1.0));
      }
    });

    test('single sample input with target 1 returns that sample', () {
      final result = downsampleWaveform([0.75], 1);
      expect(result, [0.75]);
    });
  });
}
