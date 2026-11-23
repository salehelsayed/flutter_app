import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/fixtures/ios_semantics_frames.dart';
import 'orbit_screen_pump_harness.dart';

String _fmt(Rect r) =>
    '${r.left.round()},${r.top.round()} '
    '${r.width.round()}x${r.height.round()}';

OrbitItem _friend(int i) => OrbitFriendItem(
  OrbitFriend(
    contact: ContactModel(
      peerId: 'peer-$i',
      publicKey: 'pk-$i',
      rendezvous: '/ip4/127.0.0.1/tcp/400$i',
      username: 'friend$i',
      signature: 'sig-$i',
      scannedAt: '2024-01-01T00:00:00Z',
    ),
    messageCount: i,
    unreadCount: 0,
    lastMessageTimestamp: '2024-01-01T00:00:00Z',
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 90));
  }
}

/// BL-33: on the iPhone 13 (dpr 3) every expanded orbit person was reported at
/// exactly a third of its real frame (pixelp0 18x18 at 56,99), while the
/// header chrome was correct.
///
/// The iOS accessibility bridge keeps one native object per semantics node with
/// a parent pointer, and builds each frame by walking those pointers up to the
/// root (Flutter 3.47.2 SemanticsObject.mm:40-44 and :66-95). When an update
/// moves children to a new parent AND removes their old parent, the removed
/// object's dealloc (SemanticsObject.mm:285-297, called from
/// accessibility_bridge.mm:199-203) sets the parent of every child it still
/// lists to nil. The moved children then lose every ancestor transform,
/// including the device pixel ratio, so their whole subtree reports at 1/dpr.
///
/// This test records the real semantics updates the app sends, replays them
/// through a port of that bookkeeping, and requires the iOS frame of every
/// orbit person to equal its real frame after the arcs expand.
void main() {
  final binding = IosSemanticsRecordingBinding();

  testWidgets('BL-33 expanded orbit people keep their real frames on iOS', (
    tester,
  ) async {
    const dpr = 3.0;
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844) * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildOrbitScreenHarness(
        viewMode: OrbitViewMode.innerCircle,
        header: OrbitHeaderProjection(
          userPeerId: 'me',
          innerItems: [for (var i = 0; i < 24; i++) _friend(i)],
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byType(OverflowBadge));
    await _settle(tester);

    final ios = binding.replayIosFrames(dpr);
    final people = <SemanticsNode>[];
    void walk(SemanticsNode node) {
      if (node.label.startsWith('Open chat with')) people.add(node);
      node.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(
      tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
    );
    expect(people.length, greaterThan(13), reason: 'the arcs are open');

    final wrong = [
      for (final node in people)
        if (_fmt(ios[node.id]!) != _fmt(flutterSemanticsFrame(node, dpr)))
          '${node.label}: ios ${_fmt(ios[node.id]!)}, '
              'real ${_fmt(flutterSemanticsFrame(node, dpr))}',
    ];
    expect(wrong, isEmpty);
    semantics.dispose();
  });
}
