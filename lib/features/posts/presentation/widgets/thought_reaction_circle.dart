import 'package:flutter/material.dart';

const thoughtReactionGreen = Color(0xFF1DB954);

class ThoughtReactionCircle extends StatelessWidget {
  const ThoughtReactionCircle({
    super.key,
    required this.glyph,
    required this.label,
    required this.size,
    required this.pressed,
    required this.onTap,
    required this.onActivate,
    this.foregroundColor,
  });

  final String glyph;
  final String label;
  final double size;
  final bool pressed;
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
            child: Center(
              child: Text(glyph, style: TextStyle(fontSize: size * .46)),
            ),
          ),
        ),
      ),
    );
  }
}
