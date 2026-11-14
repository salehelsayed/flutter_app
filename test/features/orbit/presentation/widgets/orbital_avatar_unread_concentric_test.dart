import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';

/// Regression: the 194 unread "messenger orbit" must revolve around the
/// avatar's own center. An earlier build clamped the indicator box inside the
/// tap-target Stack, so its internal center drifted and the satellites
/// sheared off-axis.
void main() {
  testWidgets(
    'unread satellites ride the tilted orbit centered on the avatar',
    (tester) async {
      const size = 40.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: OrbitalAvatar(
                peerId: 'p',
                size: size,
                globalIndex: 0,
                onTap: () {},
                unreadCount: 3,
                motionEnabled: false, // no entrance animation
                unreadMotionEnabled: false, // rotation frozen at its rest phase
                child: const SizedBox.expand(key: Key('avatar-core')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final avatarCenter = tester
          .getRect(find.byKey(const Key('avatar-core')))
          .center;

      // Every satellite must sit on the tilted orbit ellipse measured from
      // the AVATAR center: semi-major a = radius + 10, semi-minor 0.32a,
      // rotated -18 degrees. A clamped or offset box shears the dots off it.
      const a = size / 2 + 10;
      const b = a * 0.32;
      const tilt = -18 * math.pi / 180;
      for (var i = 0; i < 3; i++) {
        final p =
            tester.getRect(find.byKey(ValueKey('unread-satellite-$i'))).center -
            avatarCenter;
        final x = p.dx * math.cos(-tilt) - p.dy * math.sin(-tilt);
        final y = p.dx * math.sin(-tilt) + p.dy * math.cos(-tilt);
        final onEllipse = (x / a) * (x / a) + (y / b) * (y / b);
        expect(
          onEllipse,
          closeTo(1, 0.08),
          reason:
              'satellite $i must ride the orbit ellipse around the avatar '
              'center; offset $p is off it',
        );
      }
    },
  );
}
