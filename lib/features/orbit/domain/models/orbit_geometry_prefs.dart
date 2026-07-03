/// 198 "Sculpt & Summon" — the five user-tuned Orbit inner-circle geometry
/// knobs, persisted as one pipe-delimited string in [SecureKeyStore].
///
/// Shape donor: `orbit3_dimension_preferences.dart` (arity-4). REBUILT for 198
/// with a fresh arity-5 codec and its own [storageKey]; the orbit3 arity-4 key
/// is unusable here and stays orphaned. Each field CLAMPS to its stepper range
/// on decode so a corrupt or out-of-range stored value can never push the UI
/// out of bounds, and the codec re-defaults on null / empty / wrong-arity /
/// unparseable input.
///
/// Knob → mockup symbol: [avatarScale]=av, [spacingScale]=sp, [arcWrap]=cv,
/// [maxPerArc]=pr, [orbitGap]=og.
library;

/// The five sculpt knobs, each with its own range, coarse step and default.
enum OrbitKnob {
  avatarScale,
  spacingScale,
  arcWrap,
  maxPerArc,
  orbitGap,
}

class OrbitGeometryPrefs {
  final double avatarScale;
  final double spacingScale;
  final double arcWrap;
  final int maxPerArc;
  final double orbitGap;

  const OrbitGeometryPrefs({
    required this.avatarScale,
    required this.spacingScale,
    required this.arcWrap,
    required this.maxPerArc,
    required this.orbitGap,
  });

  // Ranges — mirror the mockup stepper clamps so any loaded value is reachable.
  static const double minAvatarScale = 0.6;
  static const double maxAvatarScale = 1.4;
  static const double avatarScaleStep = 0.2;

  static const double minSpacingScale = 0.7;
  static const double maxSpacingScale = 1.5;
  static const double spacingScaleStep = 0.1;

  static const double minArcWrap = 0.5;
  static const double maxArcWrap = 2.5;
  static const double arcWrapStep = 0.1;

  static const int minMaxPerArc = 4;
  static const int maxMaxPerArc = 9;
  static const int maxPerArcStep = 1;

  static const double minOrbitGap = 0.5;
  static const double maxOrbitGap = 2.5;
  static const double orbitGapStep = 0.1;

  /// The shipped baseline — geometry byte-identical to pre-198 production
  /// (INV-6). Also the Reset target.
  static const OrbitGeometryPrefs defaults = OrbitGeometryPrefs(
    avatarScale: 1.0,
    spacingScale: 1.0,
    arcWrap: 1.0,
    maxPerArc: 9,
    orbitGap: 1.0,
  );

  /// NEW key (the orbit3 arity-4 key is unusable and stays orphaned).
  static const String storageKey = 'orbit_geometry_prefs_v1';

  OrbitGeometryPrefs copyWith({
    double? avatarScale,
    double? spacingScale,
    double? arcWrap,
    int? maxPerArc,
    double? orbitGap,
  }) =>
      OrbitGeometryPrefs(
        avatarScale: avatarScale ?? this.avatarScale,
        spacingScale: spacingScale ?? this.spacingScale,
        arcWrap: arcWrap ?? this.arcWrap,
        maxPerArc: maxPerArc ?? this.maxPerArc,
        orbitGap: orbitGap ?? this.orbitGap,
      );

  /// Arity-5 pipe codec. Mirrors [toStorageString] exactly.
  String toStorageString() =>
      '$avatarScale|$spacingScale|$arcWrap|$maxPerArc|$orbitGap';

  /// Returns [defaults] for null / empty / wrong-arity / unparseable input, and
  /// clamps each parsed field to its valid range so a corrupt stored value can
  /// never push the UI out of bounds.
  static OrbitGeometryPrefs fromStorageString(String? value) {
    if (value == null || value.isEmpty) return defaults;
    final parts = value.split('|');
    if (parts.length != 5) return defaults;
    final av = double.tryParse(parts[0]);
    final sp = double.tryParse(parts[1]);
    final cv = double.tryParse(parts[2]);
    final pr = int.tryParse(parts[3]);
    final og = double.tryParse(parts[4]);
    if (av == null || sp == null || cv == null || pr == null || og == null) {
      return defaults;
    }
    return OrbitGeometryPrefs(
      avatarScale: av.clamp(minAvatarScale, maxAvatarScale).toDouble(),
      spacingScale: sp.clamp(minSpacingScale, maxSpacingScale).toDouble(),
      arcWrap: cv.clamp(minArcWrap, maxArcWrap).toDouble(),
      maxPerArc: pr.clamp(minMaxPerArc, maxMaxPerArc).toInt(),
      orbitGap: og.clamp(minOrbitGap, maxOrbitGap).toDouble(),
    );
  }

  /// The current value of [knob] (drives the edit value bubble).
  num valueOf(OrbitKnob knob) => switch (knob) {
        OrbitKnob.avatarScale => avatarScale,
        OrbitKnob.spacingScale => spacingScale,
        OrbitKnob.arcWrap => arcWrap,
        OrbitKnob.maxPerArc => maxPerArc,
        OrbitKnob.orbitGap => orbitGap,
      };

  /// Steps [knob] by [steps] coarse increments, saturating at its bounds
  /// (never throws). Only the addressed knob changes.
  OrbitGeometryPrefs stepped(OrbitKnob knob, int steps) => switch (knob) {
        OrbitKnob.avatarScale => copyWith(
            avatarScale: (avatarScale + steps * avatarScaleStep)
                .clamp(minAvatarScale, maxAvatarScale)
                .toDouble()),
        OrbitKnob.spacingScale => copyWith(
            spacingScale: (spacingScale + steps * spacingScaleStep)
                .clamp(minSpacingScale, maxSpacingScale)
                .toDouble()),
        OrbitKnob.arcWrap => copyWith(
            arcWrap: (arcWrap + steps * arcWrapStep)
                .clamp(minArcWrap, maxArcWrap)
                .toDouble()),
        OrbitKnob.maxPerArc => copyWith(
            maxPerArc: (maxPerArc + steps * maxPerArcStep)
                .clamp(minMaxPerArc, maxMaxPerArc)
                .toInt()),
        OrbitKnob.orbitGap => copyWith(
            orbitGap: (orbitGap + steps * orbitGapStep)
                .clamp(minOrbitGap, maxOrbitGap)
                .toDouble()),
      };

  @override
  bool operator ==(Object other) =>
      other is OrbitGeometryPrefs &&
      other.avatarScale == avatarScale &&
      other.spacingScale == spacingScale &&
      other.arcWrap == arcWrap &&
      other.maxPerArc == maxPerArc &&
      other.orbitGap == orbitGap;

  @override
  int get hashCode =>
      Object.hash(avatarScale, spacingScale, arcWrap, maxPerArc, orbitGap);

  @override
  String toString() =>
      'OrbitGeometryPrefs(av:$avatarScale sp:$spacingScale cv:$arcWrap '
      'pr:$maxPerArc og:$orbitGap)';
}
