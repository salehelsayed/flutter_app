import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

import '../../domain/models/orbit2_friend.dart';

/// A single floating friend avatar: one uniform-size circle with a calm,
/// desaturated identity glow and a hairline ring. Lifts on drag; dims when it
/// doesn't match the active search.
class FloatingAvatar extends StatelessWidget {
  final Orbit2Friend friend;
  final bool dimmed;
  final bool lifted;
  final bool motionEnabled;

  const FloatingAvatar({
    super.key,
    required this.friend,
    this.dimmed = false,
    this.lifted = false,
    this.motionEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final tier = friend.tier;
    final d = tier.diameter;
    final peer = RingAvatarGenerator.glowColorForPeerId(friend.peerId);
    final mutedHue = Color.lerp(peer, readable.surfaceRaised, 0.5)!;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motionEnabled
          ? const Duration(milliseconds: 420)
          : Duration.zero,
      curve: Curves.easeOutBack,
      builder: (context, entrance, child) {
        final e = entrance.clamp(0.0, 1.0);
        return Opacity(
          opacity: e * (dimmed ? 0.26 : 1.0),
          child: Transform.scale(scale: 0.86 + 0.14 * e, child: child),
        );
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: lifted ? 1.08 : 1.0,
        child: SizedBox(
          width: d,
          height: d,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: mutedHue.withValues(alpha: tier.idleGlowAlpha),
                      blurRadius: tier.idleGlowBlur,
                    ),
                  ],
                ),
              ),
              ClipOval(
                child: UserAvatar(
                  peerId: friend.peerId,
                  size: d,
                  showGlow: false,
                  showPhotoFrame: false,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: readable.border.withValues(alpha: 0.32),
                        width: 1,
                      ),
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
