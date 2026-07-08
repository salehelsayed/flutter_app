import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';

/// Regression: the 194 unread "messenger orbit" must revolve concentrically
/// around the avatar. The indicator sizes ITSELF to ~1.66x the avatar
/// (ring at 1.35x radius + satellite halo) and lays its satellites out around
/// that self-assumed center. Mounted inside OrbitalAvatar's tap-target Stack
/// (~48px), a plain SizedBox gets CLAMPED below that natural size, so the
/// indicator's internal center drifts from the real box center and the
/// satellites shear off-axis (the reported bug). The avatar Stack is Clip.none,
/// but Clip.none does NOT relax layout constraints — the indicator must be
/// given unbounded constraints so it renders at its natural size, centered.
void main() {
  testWidgets(
    'unread satellites orbit the avatar center at ringRadius (concentric)',
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
                unreadMotionEnabled: false, // rotation frozen at angle 0
                child: const SizedBox.expand(key: Key('avatar-core')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final avatarCenter =
          tester.getRect(find.byKey(const Key('avatar-core'))).center;

      // Every satellite must sit on the 1.35x ring measured from the AVATAR
      // center (the rotation axis). A clamped indicator box drifts its center
      // and the measured distances diverge from ringRadius.
      final ringRadius = size / 2 * 1.35;
      for (var i = 0; i < 3; i++) {
        final satCenter =
            tester.getRect(find.byKey(ValueKey('unread-satellite-$i'))).center;
        final d = (satCenter - avatarCenter).distance;
        expect(
          d,
          closeTo(ringRadius, 1.5),
          reason: 'satellite $i must orbit the avatar center at ringRadius '
              '($ringRadius); got $d — off-axis means the indicator box was '
              'clamped below its natural size',
        );
      }
    },
  );
}
