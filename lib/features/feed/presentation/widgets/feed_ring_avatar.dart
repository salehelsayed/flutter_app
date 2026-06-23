import 'package:flutter/widgets.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';

/// Thin Feed-surface wrapper over [RingAvatar] (134 §4/§5).
///
/// Letter cards always render the hash-derived identity avatar at a fixed
/// size, never a contact photo. This indirection keeps the card renderers
/// decoupled from the shared [RingAvatar] widget and gives the redesigned
/// Feed a single seam to tune avatar presentation later.
class FeedRingAvatar extends StatelessWidget {
  /// The peer / sender identifier used to derive the deterministic avatar.
  final String peerId;

  /// The avatar edge length in logical pixels.
  final double size;

  const FeedRingAvatar({
    super.key,
    required this.peerId,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return RingAvatar(peerId: peerId, size: size);
  }
}
