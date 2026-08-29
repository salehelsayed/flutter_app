import 'package:flutter/material.dart';

/// Circular FAB with a blue glowing ring border and dark center.
class GlowFab extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget icon;
  final double size;
  final Color backgroundColor;
  final Color ringColor;
  final bool glowEnabled;
  final double ringWidth;
  final bool refinedNeutral;

  const GlowFab({
    super.key,
    required this.onPressed,
    this.icon = const Icon(Icons.add, color: Colors.white, size: 28),
    this.size = 56,
    this.backgroundColor = const Color(0xFF1A1A2E),
    this.ringColor = const Color(0xFF64B5F6),
    this.glowEnabled = true,
    this.ringWidth = 2,
    this.refinedNeutral = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor,
          border: Border.all(color: ringColor, width: ringWidth),
          boxShadow: glowEnabled
              ? [BoxShadow(color: ringColor, blurRadius: 12, spreadRadius: 1)]
              : null,
        ),
        child: Center(child: icon),
      ),
    );
  }
}
