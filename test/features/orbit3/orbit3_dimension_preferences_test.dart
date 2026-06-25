import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_dimension_preferences.dart';

void main() {
  group('Orbit3DimensionPreferences', () {
    // TC-01
    test('toStorageString/fromStorageString round-trips all four knobs', () {
      const p = Orbit3DimensionPreferences(
        avatarScale: 1.2,
        spacingScale: 0.8,
        curveScale: 2.0,
        perRow: 5,
      );
      final decoded =
          Orbit3DimensionPreferences.fromStorageString(p.toStorageString());
      expect(decoded, p);
      expect(decoded.avatarScale, 1.2);
      expect(decoded.spacingScale, 0.8);
      expect(decoded.curveScale, 2.0);
      expect(decoded.perRow, 5);
    });

    // TC-02
    test('fromStorageString returns defaults for null/empty/malformed input', () {
      const d = Orbit3DimensionPreferences.defaults;
      expect(Orbit3DimensionPreferences.fromStorageString(null), d);
      expect(Orbit3DimensionPreferences.fromStorageString(''), d);
      expect(Orbit3DimensionPreferences.fromStorageString('garbage|x'), d);
      expect(Orbit3DimensionPreferences.fromStorageString('1.0|1.0|1.0'), d,
          reason: 'only 3 parts → defaults');
      expect(Orbit3DimensionPreferences.fromStorageString('1.0|x|1.0|7'), d,
          reason: 'one unparseable field → defaults');
      // Defaults are the documented baseline.
      expect(d.avatarScale, 1.0);
      expect(d.spacingScale, 1.0);
      expect(d.curveScale, 1.0);
      expect(d.perRow, 7);
    });

    // TC-03
    test('fromStorageString clamps out-of-range fields to valid bounds', () {
      final hi = Orbit3DimensionPreferences.fromStorageString('5.0|9.0|9.0|99');
      expect(hi.avatarScale, 1.4, reason: 'avatar clamps to max 1.4');
      expect(hi.spacingScale, 1.5, reason: 'spacing clamps to max 1.5');
      expect(hi.curveScale, 2.5, reason: 'curve clamps to max 2.5');
      expect(hi.perRow, 9, reason: 'perRow clamps to max 9');

      final lo = Orbit3DimensionPreferences.fromStorageString('0.1|0.1|0.1|1');
      expect(lo.avatarScale, 0.6, reason: 'avatar clamps to min 0.6');
      expect(lo.spacingScale, 0.7, reason: 'spacing clamps to min 0.7');
      expect(lo.curveScale, 0.5, reason: 'curve clamps to min 0.5');
      expect(lo.perRow, 4, reason: 'perRow clamps to min 4');
    });
  });
}
