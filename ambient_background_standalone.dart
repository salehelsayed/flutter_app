// Standalone, dependency-free copy of the Feed screen's animated background.
// Drop this file into any Flutter project and wrap your screen body with
// `AmbientBackground(child: ...)`.
//
// Example:
//   Scaffold(
//     body: AmbientBackground(
//       child: Center(child: Text('Hello')),
//     ),
//   )

import 'dart:math' as math;
import 'package:flutter/material.dart';

class AmbientBackground extends StatefulWidget {
  final Widget child;

  // Tweak these to play with look-and-feel.
  final Color backgroundColor;
  final Color greenGlow;
  final Color redGlow;
  final Duration period;

  const AmbientBackground({
    super.key,
    required this.child,
    this.backgroundColor = const Color(0xFF000000),
    this.greenGlow = const Color(0xFF1DB954),
    this.redGlow = const Color(0xFFFF3232),
    this.period = const Duration(seconds: 8),
  });

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.period,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.backgroundColor,
      child: Stack(
        children: [
          // Green glow - top left
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = _controller.value;
              final xOffset = math.sin(value * 2 * math.pi) * 30;
              final yOffset = math.cos(value * 2 * math.pi) * 20;
              return Positioned(
                top: -100 + yOffset,
                left: -100 + xOffset,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.greenGlow.withValues(alpha: 0.3),
                        widget.greenGlow.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // Red glow - bottom right
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = _controller.value;
              final xOffset = math.cos(value * 2 * math.pi) * 25;
              final yOffset = math.sin(value * 2 * math.pi) * 30;
              return Positioned(
                bottom: -100 + yOffset,
                right: -100 + xOffset,
                child: Container(
                  width: 350,
                  height: 350,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.redGlow.withValues(alpha: 0.25),
                        widget.redGlow.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          widget.child,
        ],
      ),
    );
  }
}
