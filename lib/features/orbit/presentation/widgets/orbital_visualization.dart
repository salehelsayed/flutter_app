import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'orbital_ring_painter.dart';
import 'orbital_avatar.dart';
import 'overflow_badge.dart';

/// 320x320 orbital visualization: dashed rings, center avatar, friend avatars.
///
/// Ring 1 (inner): top 5 friends at 62px radius, 38px avatars.
/// Ring 2 (outer): next 8 friends at 108px radius, 30px avatars.
/// Overflow badge if friends > 13.
class OrbitalVisualization extends StatelessWidget {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final List<OrbitFriend> friends;

  static const double _size = 320;
  static const double _center = _size / 2;
  static const double _ring1Radius = 62;
  static const double _ring2Radius = 108;
  static const int _ring1Count = 5;
  static const int _ring2Count = 8;

  const OrbitalVisualization({
    super.key,
    required this.userPeerId,
    this.userAvatarBytes,
    required this.friends,
  });

  @override
  Widget build(BuildContext context) {
    final ring1Friends = friends.take(_ring1Count).toList();
    final ring2Friends =
        friends.skip(_ring1Count).take(_ring2Count).toList();
    final overflowCount = friends.length > 13 ? friends.length - 13 : 0;

    return Column(
      children: [
        // Section title
        const Padding(
          padding: EdgeInsets.only(bottom: 24),
          child: Text(
            'YOUR INNER CIRCLE',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0x66FFFFFF), // rgba(255,255,255,0.4)
              letterSpacing: 1,
            ),
          ),
        ),

        // Orbital container
        SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Dashed rings
              Positioned.fill(
                child: CustomPaint(
                  painter: OrbitalRingPainter(),
                ),
              ),

              // Center avatar
              if (userPeerId != null)
                Positioned(
                  left: _center - 24,
                  top: _center - 24,
                  child: UserAvatar(
                    peerId: userPeerId,
                    avatarBytes: userAvatarBytes,
                    size: 48,
                  ),
                ),

              // Ring 1 friends (inner orbit)
              ...List.generate(ring1Friends.length, (i) {
                final pos = _positionOnRing(
                  index: i,
                  count: ring1Friends.length,
                  radius: _ring1Radius,
                  ringIndex: 0,
                );
                return Positioned(
                  left: _center + pos.dx - 19,
                  top: _center + pos.dy - 19,
                  child: OrbitalAvatar(
                    peerId: ring1Friends[i].peerId,
                    size: 38,
                    globalIndex: i,
                    borderWidth: 1.5,
                    borderColor: const Color(0x1FFFFFFF),
                  ),
                );
              }),

              // Ring 2 friends (outer orbit)
              ...List.generate(ring2Friends.length, (i) {
                final pos = _positionOnRing(
                  index: i,
                  count: ring2Friends.length,
                  radius: _ring2Radius,
                  ringIndex: 1,
                );
                return Positioned(
                  left: _center + pos.dx - 15,
                  top: _center + pos.dy - 15,
                  child: OrbitalAvatar(
                    peerId: ring2Friends[i].peerId,
                    size: 30,
                    globalIndex: _ring1Count + i,
                    borderWidth: 1,
                    borderColor: const Color(0x14FFFFFF),
                  ),
                );
              }),

              // Overflow badge
              if (overflowCount > 0) ...[
                () {
                  final badgePos = _positionOnRing(
                    index: ring2Friends.length,
                    count: ring2Friends.length + 1,
                    radius: _ring2Radius,
                    ringIndex: 1,
                  );
                  return Positioned(
                    left: _center + badgePos.dx - 14,
                    top: _center + badgePos.dy - 14,
                    child: OverflowBadge(count: overflowCount),
                  );
                }(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Calculates position on a ring using the spec's trigonometric formula.
  Offset _positionOnRing({
    required int index,
    required int count,
    required double radius,
    required int ringIndex,
  }) {
    if (count == 0) return Offset.zero;
    final offset = ringIndex * 15; // degrees stagger per ring
    final angle =
        (index * 360 / count + offset - 90) * (pi / 180);
    return Offset(cos(angle) * radius, sin(angle) * radius);
  }
}
