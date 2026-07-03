import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';

void main() {
  group('OrbitGeometryPrefs codec (198 F2)', () {
    // TC-198-34 / round-trip
    test('arity-5 pipe codec round-trips a sculpted value', () {
      const p = OrbitGeometryPrefs(
        avatarScale: 0.8,
        spacingScale: 1.2,
        arcWrap: 1.3,
        maxPerArc: 5,
        orbitGap: 1.5,
      );
      expect(p.toStorageString(), '0.8|1.2|1.3|5|1.5');
      expect(OrbitGeometryPrefs.fromStorageString(p.toStorageString()), p);
    });

    // TC-198-34
    test('defaults on null / empty / wrong-arity / unparseable', () {
      expect(OrbitGeometryPrefs.fromStorageString(null),
          OrbitGeometryPrefs.defaults);
      expect(OrbitGeometryPrefs.fromStorageString(''),
          OrbitGeometryPrefs.defaults);
      // arity 4 (an orbit3-shaped string) must NOT parse into the arity-5 model.
      expect(OrbitGeometryPrefs.fromStorageString('1.0|1.0|1.0|7'),
          OrbitGeometryPrefs.defaults);
      expect(OrbitGeometryPrefs.fromStorageString('1.0|1.0|1.0|7|1.0|extra'),
          OrbitGeometryPrefs.defaults);
      expect(OrbitGeometryPrefs.fromStorageString('a|b|c|d|e'),
          OrbitGeometryPrefs.defaults);
    });

    // TC-198-35
    test('per-field clamp on decode (av 9.0→1.4, pr 99→9, mins saturate)', () {
      final hi = OrbitGeometryPrefs.fromStorageString('9.0|9.0|9.0|99|9.0');
      expect(hi.avatarScale, closeTo(OrbitGeometryPrefs.maxAvatarScale, 1e-9));
      expect(hi.spacingScale, closeTo(OrbitGeometryPrefs.maxSpacingScale, 1e-9));
      expect(hi.arcWrap, closeTo(OrbitGeometryPrefs.maxArcWrap, 1e-9));
      expect(hi.maxPerArc, OrbitGeometryPrefs.maxMaxPerArc);
      expect(hi.orbitGap, closeTo(OrbitGeometryPrefs.maxOrbitGap, 1e-9));

      final lo = OrbitGeometryPrefs.fromStorageString('0.1|0.1|0.1|1|0.1');
      expect(lo.avatarScale, closeTo(OrbitGeometryPrefs.minAvatarScale, 1e-9));
      expect(lo.spacingScale, closeTo(OrbitGeometryPrefs.minSpacingScale, 1e-9));
      expect(lo.arcWrap, closeTo(OrbitGeometryPrefs.minArcWrap, 1e-9));
      expect(lo.maxPerArc, OrbitGeometryPrefs.minMaxPerArc);
      expect(lo.orbitGap, closeTo(OrbitGeometryPrefs.minOrbitGap, 1e-9));
    });

    // TC-198-21 math (defaults + coarse steps are the documented consts)
    test('defaults are 1.0/1.0/1.0/9/1.0 with the documented coarse steps', () {
      const d = OrbitGeometryPrefs.defaults;
      expect(d.avatarScale, 1.0);
      expect(d.spacingScale, 1.0);
      expect(d.arcWrap, 1.0);
      expect(d.maxPerArc, 9);
      expect(d.orbitGap, 1.0);

      expect(OrbitGeometryPrefs.avatarScaleStep, 0.2);
      expect(OrbitGeometryPrefs.spacingScaleStep, 0.1);
      expect(OrbitGeometryPrefs.arcWrapStep, 0.1);
      expect(OrbitGeometryPrefs.maxPerArcStep, 1);
      expect(OrbitGeometryPrefs.orbitGapStep, 0.1);
    });

    // TC-198-21 math — step-and-clamp saturates at both bounds, never throws.
    test('stepped() moves by the coarse step and saturates at bounds', () {
      const d = OrbitGeometryPrefs.defaults;
      expect(d.stepped(OrbitKnob.avatarScale, 1).avatarScale, closeTo(1.2, 1e-9));
      expect(d.stepped(OrbitKnob.avatarScale, -1).avatarScale, closeTo(0.8, 1e-9));
      // Overshoot saturates, does not throw.
      expect(d.stepped(OrbitKnob.avatarScale, 100).avatarScale,
          closeTo(OrbitGeometryPrefs.maxAvatarScale, 1e-9));
      expect(d.stepped(OrbitKnob.avatarScale, -100).avatarScale,
          closeTo(OrbitGeometryPrefs.minAvatarScale, 1e-9));
      // Int knob saturates at 9 / 4.
      expect(d.stepped(OrbitKnob.maxPerArc, 1).maxPerArc, 9);
      expect(d.stepped(OrbitKnob.maxPerArc, -100).maxPerArc, 4);
      // Only the addressed knob changes.
      final s = d.stepped(OrbitKnob.orbitGap, 2);
      expect(s.orbitGap, closeTo(1.2, 1e-9));
      expect(s.avatarScale, d.avatarScale);
      expect(s.maxPerArc, d.maxPerArc);
    });

    // valueOf reads the addressed knob (drives the edit value bubble).
    test('valueOf returns each knob value', () {
      const p = OrbitGeometryPrefs(
        avatarScale: 0.8,
        spacingScale: 1.2,
        arcWrap: 1.3,
        maxPerArc: 5,
        orbitGap: 1.5,
      );
      expect(p.valueOf(OrbitKnob.avatarScale), 0.8);
      expect(p.valueOf(OrbitKnob.spacingScale), 1.2);
      expect(p.valueOf(OrbitKnob.arcWrap), 1.3);
      expect(p.valueOf(OrbitKnob.maxPerArc), 5);
      expect(p.valueOf(OrbitKnob.orbitGap), 1.5);
    });
  });
}
