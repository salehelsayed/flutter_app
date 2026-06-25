/// User-tuned Orbit3 "dimension" knobs: avatar size, inter-orbit/arch spacing,
/// arch curve, and avatars-per-arch.
///
/// The FIRST *numeric* preference in the app, so it owns its own codec —
/// mirroring [BackgroundPreference]'s `storageKey` / `toStorageString` /
/// `fromStorageString` shape, but it encodes three doubles + one int into one
/// delimited string and CLAMPS each field to its stepper range on decode, so a
/// corrupt or out-of-range stored value can never push the UI out of bounds.
class Orbit3DimensionPreferences {
  final double avatarScale;
  final double spacingScale;
  final double curveScale;
  final int perRow;

  const Orbit3DimensionPreferences({
    required this.avatarScale,
    required this.spacingScale,
    required this.curveScale,
    required this.perRow,
  });

  // Valid stepper ranges — mirror the orbit3_screen +/- clamps so a loaded
  // value is always reachable by the steppers.
  static const double minAvatarScale = 0.6;
  static const double maxAvatarScale = 1.4;
  static const double minSpacingScale = 0.7;
  static const double maxSpacingScale = 1.5;
  static const double minCurveScale = 0.5;
  static const double maxCurveScale = 2.5;
  static const int minPerRow = 4;
  static const int maxPerRow = 9;

  /// The shipped baseline (Orbit-parity) — the Reset target.
  static const Orbit3DimensionPreferences defaults = Orbit3DimensionPreferences(
    avatarScale: 1.0,
    spacingScale: 1.0,
    curveScale: 1.0,
    perRow: 7,
  );

  /// Key used in SecureKeyStore. Versioned so a future schema change can
  /// re-default rather than mis-parse an old encoding.
  static const String storageKey = 'orbit3_dimension_preferences_v1';

  String toStorageString() => '$avatarScale|$spacingScale|$curveScale|$perRow';

  /// Parses a storage string. Returns [defaults] for null / empty / wrong-arity
  /// / unparseable input, and clamps each parsed field to its valid range.
  static Orbit3DimensionPreferences fromStorageString(String? value) {
    if (value == null || value.isEmpty) return defaults;
    final parts = value.split('|');
    if (parts.length != 4) return defaults;
    final avatar = double.tryParse(parts[0]);
    final spacing = double.tryParse(parts[1]);
    final curve = double.tryParse(parts[2]);
    final perRow = int.tryParse(parts[3]);
    if (avatar == null || spacing == null || curve == null || perRow == null) {
      return defaults;
    }
    return Orbit3DimensionPreferences(
      avatarScale: avatar.clamp(minAvatarScale, maxAvatarScale).toDouble(),
      spacingScale: spacing.clamp(minSpacingScale, maxSpacingScale).toDouble(),
      curveScale: curve.clamp(minCurveScale, maxCurveScale).toDouble(),
      perRow: perRow.clamp(minPerRow, maxPerRow).toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Orbit3DimensionPreferences &&
      other.avatarScale == avatarScale &&
      other.spacingScale == spacingScale &&
      other.curveScale == curveScale &&
      other.perRow == perRow;

  @override
  int get hashCode =>
      Object.hash(avatarScale, spacingScale, curveScale, perRow);
}
