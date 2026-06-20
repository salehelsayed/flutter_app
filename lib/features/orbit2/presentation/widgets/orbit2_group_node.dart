import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

import '../../domain/models/orbit2_group.dart';

/// A group ("orbit") node — a MINI inner-circle: members orbit a small group
/// hub on a dotted ring. Distinct from a single-friend avatar; created when two
/// friends are dropped onto each other.
class Orbit2GroupNode extends StatelessWidget {
  final Orbit2Group group;
  final double size;
  final bool dimmed;
  final bool lifted;

  const Orbit2GroupNode({
    super.key,
    required this.group,
    this.size = 52,
    this.dimmed = false,
    this.lifted = false,
  });

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    const accent = AppColors.tealAccent;
    final c = size / 2;
    final ringR = size * 0.34;
    final memberSize = size * 0.30;
    final hub = size * 0.30;
    final members = group.members.take(4).toList();

    Offset pos(int i, int count) {
      final a = (i * 360 / count - 90) * (pi / 180);
      return Offset(cos(a) * ringR, sin(a) * ringR);
    }

    return AnimatedScale(
      duration: const Duration(milliseconds: 140),
      scale: lifted ? 1.08 : 1.0,
      child: Opacity(
        opacity: dimmed ? 0.26 : 1.0,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Glow.
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: accent.withValues(alpha: 0.22), blurRadius: 14),
                  ],
                ),
              ),
              // Dotted orbit ring.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _GroupRingPainter(ringR)),
                ),
              ),
              // Group hub at centre.
              Positioned(
                left: c - hub / 2,
                top: c - hub / 2,
                child: Container(
                  width: hub,
                  height: hub,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.9),
                    border: Border.all(
                      color: readable.surfaceBase.withValues(alpha: 0.9),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(Icons.group_rounded, size: hub * 0.55, color: Colors.black),
                ),
              ),
              // Members orbiting the hub.
              for (var i = 0; i < members.length; i++)
                Positioned(
                  left: c + pos(i, members.length).dx - memberSize / 2,
                  top: c + pos(i, members.length).dy - memberSize / 2,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: readable.surfaceBase.withValues(alpha: 0.9),
                        width: 1.1,
                      ),
                    ),
                    child: ClipOval(
                      child: UserAvatar(
                        peerId: members[i].peerId,
                        size: memberSize,
                        showGlow: false,
                        showPhotoFrame: false,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupRingPainter extends CustomPainter {
  final double radius;
  const _GroupRingPainter(this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = AppColors.tealAccent.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const dash = 5.0;
    const gap = 3.5;
    final circ = 2 * pi * radius;
    final count = (circ / (dash + gap)).floor();
    for (var i = 0; i < count; i++) {
      final start = (i * (dash + gap) / circ) * 2 * pi;
      final sweep = (dash / circ) * 2 * pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GroupRingPainter old) => old.radius != radius;
}
