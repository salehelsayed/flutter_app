/// Message-count threshold once used to size friends; retained only to classify
/// a friend's arrangement bias (e.g. Gravity clustering), not their visual size.
const int kSizeAThreshold = 20;

/// All floating avatars now render at ONE size, matching the Inner-Circle avatars.
const double kFloatingAvatarDiameter = 40;

/// Arrangement bias for a floating friend. (Avatars are a single uniform size;
/// the tier no longer changes how big an avatar is — only where templates like
/// "Gravity" tend to place it.)
enum AvatarTier {
  sizeA,
  sizeB;

  static AvatarTier fromMessageCount(int messageCount) =>
      messageCount >= kSizeAThreshold ? AvatarTier.sizeA : AvatarTier.sizeB;

  bool get isHigh => this == AvatarTier.sizeA;

  /// Uniform avatar diameter (same for every friend, matching the Inner Circle).
  double get diameter => kFloatingAvatarDiameter;

  double get radius => diameter / 2;

  double get idleGlowBlur => 13;

  double get idleGlowAlpha => 0.18;

  /// Max width of the name label pill under the avatar (kept under
  /// [kNamedSpacing] so adjacent labels don't collide).
  double get labelMaxWidth => 72;
}
