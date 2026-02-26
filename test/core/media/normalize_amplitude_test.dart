import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/normalize_amplitude.dart';

void main() {
  group('normalizeAmplitude', () {
    test('-60 dBFS maps to 0.0', () {
      expect(normalizeAmplitude(-60), 0.0);
    });

    test('0 dBFS maps to 1.0', () {
      expect(normalizeAmplitude(0), 1.0);
    });

    test('-30 dBFS maps to ~0.66 (power curve lifts midrange)', () {
      // Linear: (-30 + 60) / 60 = 0.5
      // Power: pow(0.5, 0.6) ≈ 0.6598
      final result = normalizeAmplitude(-30);
      expect(result, closeTo(pow(0.5, 0.6), 0.001));
      expect(result, greaterThan(0.6));
      expect(result, lessThan(0.7));
    });

    test('clamps positive values to 1.0', () {
      expect(normalizeAmplitude(10), 1.0);
    });

    test('clamps values below -60 to 0.0', () {
      expect(normalizeAmplitude(-100), 0.0);
      expect(normalizeAmplitude(-160), 0.0);
    });

    test('-15 dBFS maps to high value (loud speech)', () {
      // Linear: (-15 + 60) / 60 = 0.75
      // Power: pow(0.75, 0.6) ≈ 0.8457
      final result = normalizeAmplitude(-15);
      expect(result, closeTo(pow(0.75, 0.6), 0.001));
      expect(result, greaterThan(0.8));
    });

    test('-45 dBFS maps to low-mid value (quiet speech)', () {
      // Linear: (-45 + 60) / 60 = 0.25
      // Power: pow(0.25, 0.6) ≈ 0.3789
      final result = normalizeAmplitude(-45);
      expect(result, closeTo(pow(0.25, 0.6), 0.001));
      expect(result, greaterThan(0.35));
      expect(result, lessThan(0.5));
    });

    test('-5 dBFS maps to near-max (very loud)', () {
      final result = normalizeAmplitude(-5);
      expect(result, greaterThan(0.9));
      expect(result, lessThanOrEqualTo(1.0));
    });
  });
}
