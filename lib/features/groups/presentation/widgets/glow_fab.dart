import 'package:flutter/material.dart';

/// Circular FAB with a blue glowing ring border and dark center.
class GlowFab extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget icon;
  final double size;

  const GlowFab({
    super.key,
    required this.onPressed,
    this.icon = const Icon(Icons.add, color: Colors.white, size: 28),
    this.size = 56,
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
          color: const Color(0xFF1A1A2E),
          border: Border.all(
            color: const Color(0xFF64B5F6),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0xFF64B5F6),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(child: icon),
      ),
    );
  }
}
