import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

/// The one round control of the Orbit screen: a 44 px circle with a hairline
/// border and a faint fill. The create (+) control is the only filled one and
/// lives in [GlowFab].
class OrbitControlCircle extends StatelessWidget {
  static const double size = 44;

  final IconData? icon;
  final double iconSize;
  final Widget? child;

  const OrbitControlCircle({
    super.key,
    required IconData this.icon,
    this.iconSize = 24,
  }) : child = null;

  /// For a control that draws its own glyph or brings its own button.
  const OrbitControlCircle.custom({super.key, required Widget this.child})
    : icon = null,
      iconSize = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.chromeFaintFill,
        shape: BoxShape.circle,
        border: Border.all(color: colors.chromeHairline),
      ),
      child: Center(
        child: child ?? Icon(icon, size: iconSize, color: colors.chromeInk),
      ),
    );
  }
}
