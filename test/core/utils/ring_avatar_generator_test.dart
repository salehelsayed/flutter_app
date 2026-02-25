import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
import 'package:flutter_app/core/utils/ring_avatar_spec.dart';

void main() {
  // ---------------------------------------------------------------------------
  // djb2Hash
  // ---------------------------------------------------------------------------
  group('djb2Hash', () {
    test('returns consistent hash for same input', () {
      final hash1 = RingAvatarGenerator.djb2Hash('12D3KooWTestPeerId');
      final hash2 = RingAvatarGenerator.djb2Hash('12D3KooWTestPeerId');
      expect(hash1, equals(hash2));
    });

    test('returns different hash for different inputs', () {
      final hash1 = RingAvatarGenerator.djb2Hash('peerA');
      final hash2 = RingAvatarGenerator.djb2Hash('peerB');
      expect(hash1, isNot(equals(hash2)));
    });

    test('handles empty string (returns 5381)', () {
      final hash = RingAvatarGenerator.djb2Hash('');
      expect(hash, equals(5381));
    });

    test('handles single character', () {
      final hash = RingAvatarGenerator.djb2Hash('A');
      // djb2: ((5381 << 5) + 5381) + 65 = 177638 + 65 = 177703
      // But with 32-bit masking: same value since it fits
      expect(hash, isA<int>());
      expect(hash, isNot(equals(5381))); // not same as empty
    });

    test('result stays 32-bit bounded', () {
      // Use a long string to force large intermediate values
      final longStr = 'A' * 1000;
      final hash = RingAvatarGenerator.djb2Hash(longStr);
      expect(hash, lessThanOrEqualTo(0xFFFFFFFF));
      expect(hash, greaterThanOrEqualTo(0));
    });
  });

  // ---------------------------------------------------------------------------
  // generate
  // ---------------------------------------------------------------------------
  group('generate', () {
    test('always produces exactly 4 rings', () {
      final data = RingAvatarGenerator.generate('12D3KooWTestPeerId', 80.0);
      expect(data.rings.length, equals(4));
    });

    test('same peerId produces identical RingAvatarData (determinism)', () {
      const peerId = '12D3KooWABCDEFGH';
      final data1 = RingAvatarGenerator.generate(peerId, 80.0);
      final data2 = RingAvatarGenerator.generate(peerId, 80.0);

      for (int i = 0; i < 4; i++) {
        expect(data1.rings[i].radius, equals(data2.rings[i].radius));
        expect(data1.rings[i].strokeWidth, equals(data2.rings[i].strokeWidth));
        expect(data1.rings[i].color, equals(data2.rings[i].color));
        expect(data1.rings[i].opacity, equals(data2.rings[i].opacity));
        expect(data1.rings[i].isDashed, equals(data2.rings[i].isDashed));
        expect(
            data1.rings[i].rotationDegrees, equals(data2.rings[i].rotationDegrees));
      }

      expect(data1.glow.color, equals(data2.glow.color));
      expect(data1.glow.outerRadius, equals(data2.glow.outerRadius));
      expect(data1.glow.middleRadius, equals(data2.glow.middleRadius));
      expect(data1.glow.innerRadius, equals(data2.glow.innerRadius));
    });

    test('different peerIds produce different ring data', () {
      final data1 = RingAvatarGenerator.generate('12D3KooWPeerAAAAA', 80.0);
      final data2 = RingAvatarGenerator.generate('12D3KooWPeerBBBBB', 80.0);

      // At least one ring property should differ
      bool anyDifference = false;
      for (int i = 0; i < 4; i++) {
        if (data1.rings[i].color != data2.rings[i].color ||
            data1.rings[i].strokeWidth != data2.rings[i].strokeWidth ||
            data1.rings[i].opacity != data2.rings[i].opacity) {
          anyDifference = true;
          break;
        }
      }
      expect(anyDifference, isTrue);
    });

    test('all 4 brand colors appear in ring set', () {
      final data = RingAvatarGenerator.generate('12D3KooWTestPeerId', 80.0);
      final ringColors = data.rings.map((r) => r.color).toSet();
      final brandColors = RingAvatarColors.palette.toSet();
      expect(ringColors, equals(brandColors));
    });

    test('ring radii decrease from outer to inner', () {
      final data = RingAvatarGenerator.generate('12D3KooWTestPeerId', 80.0);
      // Rings are stored inner-to-outer (index 0 = innermost)
      for (int i = 0; i < data.rings.length - 1; i++) {
        expect(data.rings[i].radius, lessThan(data.rings[i + 1].radius));
      }
    });

    test('stroke widths in range [2, 5]', () {
      // Test with several peer IDs to cover more hash space
      for (final peerId in ['peerA_1234567890', 'peerB_1234567890', 'peerC_1234567890']) {
        final data = RingAvatarGenerator.generate(peerId, 80.0);
        for (final ring in data.rings) {
          expect(ring.strokeWidth,
              greaterThanOrEqualTo(RingAvatarConstants.minStrokeWidth));
          expect(ring.strokeWidth,
              lessThanOrEqualTo(RingAvatarConstants.maxStrokeWidth));
        }
      }
    });

    test('opacity values in range [0.75, 1.0]', () {
      for (final peerId in ['peerX_1234567890', 'peerY_1234567890', 'peerZ_1234567890']) {
        final data = RingAvatarGenerator.generate(peerId, 80.0);
        for (final ring in data.rings) {
          expect(ring.opacity,
              greaterThanOrEqualTo(RingAvatarConstants.minOpacity));
          expect(ring.opacity,
              lessThanOrEqualTo(RingAvatarConstants.maxOpacity));
        }
      }
    });

    test('odd-indexed rings are dashed, even are solid', () {
      final data = RingAvatarGenerator.generate('12D3KooWTestPeerId', 80.0);
      for (int i = 0; i < data.rings.length; i++) {
        if (i % 2 == 1) {
          expect(data.rings[i].isDashed, isTrue, reason: 'Ring $i should be dashed');
        } else {
          expect(data.rings[i].isDashed, isFalse, reason: 'Ring $i should be solid');
        }
      }
    });

    test('glow radii are proportional to size', () {
      const size = 100.0;
      final data = RingAvatarGenerator.generate('12D3KooWTestPeerId', size);

      expect(data.glow.outerRadius,
          closeTo(size * RingAvatarConstants.glowOuterRadiusRatio, 0.001));
      expect(data.glow.middleRadius,
          closeTo(size * RingAvatarConstants.glowMiddleRadiusRatio, 0.001));
      expect(data.glow.innerRadius,
          closeTo(size * RingAvatarConstants.glowInnerRadiusRatio, 0.001));
    });

    test('glow color hue derived from hash', () {
      final data = RingAvatarGenerator.generate('12D3KooWTestPeerId', 80.0);
      final glowHSL = HSLColor.fromColor(data.glow.color);
      // Hue should be in range [0, 360)
      expect(glowHSL.hue, greaterThanOrEqualTo(0.0));
      expect(glowHSL.hue, lessThan(360.0));
      // Saturation should be the spec value
      expect(glowHSL.saturation,
          closeTo(RingAvatarConstants.glowSaturation / 100.0, 0.02));
      // Luminance should be the spec value
      expect(glowHSL.lightness,
          closeTo(RingAvatarConstants.glowLuminance / 100.0, 0.02));
    });
  });
}
