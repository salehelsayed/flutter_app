import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
import 'ring_avatar_painter.dart';

/// A unique ring-based avatar generated from a peerId.
///
/// The avatar consists of concentric rings in brand colors with a
/// hash-derived center glow. The same peerId will always produce
/// the same avatar on any device.
///
/// Example:
/// ```dart
/// RingAvatar(
///   peerId: '12D3KooW...',
///   size: 80,
/// )
/// ```
class RingAvatar extends StatelessWidget {
  /// The peer ID used to generate the unique avatar.
  final String peerId;

  /// The size of the avatar in logical pixels.
  final double size;

  const RingAvatar({
    super.key,
    required this.peerId,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    // Generate deterministic avatar data from peerId
    final data = RingAvatarGenerator.generate(peerId, size);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: RingAvatarPainter(data: data),
      ),
    );
  }
}
