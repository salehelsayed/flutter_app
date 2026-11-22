import 'package:flutter/material.dart';

const thoughtReactionGreen = Color(0xFF1DB954);

class ThoughtReactionCircle extends StatelessWidget {
  const ThoughtReactionCircle({
    super.key,
    required this.glyph,
    required this.label,
    required this.size,
    required this.pressed,
    this.confirmed = false,
    required this.onTap,
    required this.onActivate,
    this.foregroundColor,
  });

  final String glyph;
  final String label;
  final double size;
  final bool pressed;
  final bool confirmed;
  final Color? foregroundColor;
  final VoidCallback onTap;

  /// The screen reader's tap.
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final onSurface =
        foregroundColor ?? Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: pressed,
      label: label,
      excludeSemantics: true,
      onTap: onActivate,
      child: Material(
        color: pressed
            ? thoughtReactionGreen.withValues(alpha: .18)
            : onSurface.withValues(alpha: .08),
        shape: CircleBorder(
          side: pressed
              ? const BorderSide(color: thoughtReactionGreen, width: 2)
              : BorderSide(color: onSurface.withValues(alpha: .10)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Text(glyph, style: TextStyle(fontSize: size * .46)),
                ),
                if (confirmed)
                  const PositionedDirectional(
                    end: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: thoughtReactionGreen,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(
                        dimension: 16,
                        child: Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Color(0xff04130a),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
