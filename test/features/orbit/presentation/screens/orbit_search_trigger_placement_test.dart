import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';

import 'orbit_screen_pump_harness.dart';

/// 212 — the all-chats search trigger leaves the persistent nav Row and floats
/// at the bottom-right corner, in the SAME band the Inner-Circle find pill
/// owns (INV-212-1): right 16, bottom = navBottomOffset + 84, 52px circle.
/// With the test surface's zero safe-area inset that band bottom is
/// max(16, 0 - 14) + 84 = 100 from the screen's bottom edge.
const double _bandBottomOffset = 100.0;

OrbitItem _friend(int i) => OrbitFriendItem(OrbitFriend(
      contact: ContactModel(
        peerId: 'peer-$i',
        publicKey: 'pk-$i',
        rendezvous: '/ip4/127.0.0.1/tcp/400$i',
        username: 'friend$i',
        signature: 'sig-$i',
        scannedAt: '2024-01-01T00:00:00Z',
      ),
      messageCount: i,
      lastMessageTimestamp: '2024-01-01T00:00:00Z',
    ));

List<OrbitItem> _friends(int n) => [for (var i = 0; i < n; i++) _friend(i)];

void main() {
  void setPhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(414, 896);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  void suppressChromeErrors() {
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (details.toString().contains('overflowed') ||
          msg.contains('Unable to load asset') ||
          msg.contains('SvgPicture') ||
          msg.contains('ImageFilter')) {
        return;
      }
      old?.call(details);
    };
    addTearDown(() => FlutterError.onError = old);
  }

  Size screenSize(WidgetTester tester) =>
      tester.view.physicalSize / tester.view.devicePixelRatio;

  Widget persistentPump({
    OrbitViewMode viewMode = OrbitViewMode.allChats,
    OrbitHeaderProjection header = const OrbitHeaderProjection(),
    Locale locale = const Locale('en'),
  }) =>
      buildOrbitScreenHarness(
        viewMode: viewMode,
        header: header,
        locale: locale,
        activeTab: 'orbit',
        onSwitchView: (_) {},
        searchTriggerAnimation: const AlwaysStoppedAnimation<double>(1.0),
      );

  Future<void> settle(WidgetTester tester, {int count = 8}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
  }

  group('212 search trigger placement', () {
    testWidgets(
        'TC-212-01 persistent all-chats floats the trigger bottom-right in '
        'the find-pill band', (tester) async {
      suppressChromeErrors();
      setPhoneSurface(tester);

      await tester.pumpWidget(persistentPump());
      await settle(tester);

      final screen = screenSize(tester);
      final rect = tester.getRect(find.byType(OrbitSearchTrigger));
      final navRect = tester.getRect(find.byType(FeedNavigationBar));

      expect(rect.right, screen.width - 16,
          reason: 'the trigger owns the physical bottom-right corner');
      expect(rect.bottom, screen.height - _bandBottomOffset,
          reason: 'the trigger sits in the find-pill band (navOffset + 84)');
      expect(rect.height, 52, reason: '212 visual upgrade: 44 → 52');
      expect((rect.center.dy - navRect.center.dy).abs(), greaterThan(10),
          reason: 'no longer riding the nav bar\'s vertical level');
    });

    testWidgets(
        'TC-212-02 nav pill stays horizontally centered without the trigger '
        'slot', (tester) async {
      suppressChromeErrors();
      setPhoneSurface(tester);

      await tester.pumpWidget(persistentPump());
      await settle(tester);

      final screen = screenSize(tester);
      final navRect = tester.getRect(find.byType(FeedNavigationBar));
      expect(navRect.center.dx, closeTo(screen.width / 2, 1.0),
          reason: 'the bar keeps its center once the inline slot is gone');
    });

    testWidgets(
        'TC-212-03 rings pill and list trigger share one bottom-right band '
        '(INV-212-1)', (tester) async {
      suppressChromeErrors();
      setPhoneSurface(tester);

      await tester.pumpWidget(persistentPump());
      await settle(tester);
      final triggerRect = tester.getRect(find.byType(OrbitSearchTrigger));
      expect(tester.getSize(find.byType(OrbitSearchTrigger)),
          const Size(52, 52));

      await tester.pumpWidget(persistentPump(
        viewMode: OrbitViewMode.innerCircle,
        header: OrbitHeaderProjection(
          userPeerId: 'me',
          innerItems: _friends(8),
        ),
      ));
      await settle(tester);

      final pillF = find.byKey(const ValueKey('orbit-find-pill'));
      final pillRect = tester.getRect(pillF);
      expect(tester.getSize(pillF), const Size(52, 52));
      expect(pillRect.bottom, triggerRect.bottom,
          reason: 'one band on both surfaces');
      expect(pillRect.right, triggerRect.right,
          reason: 'one right edge on both surfaces');
    });

    testWidgets('TC-212-04 RTL keeps the physical bottom-right corner',
        (tester) async {
      suppressChromeErrors();
      setPhoneSurface(tester);

      await tester.pumpWidget(persistentPump(locale: const Locale('ar')));
      await settle(tester);

      final screen = screenSize(tester);
      final rect = tester.getRect(find.byType(OrbitSearchTrigger));
      expect(rect.right, screen.width - 16,
          reason: 'physical-right stance survives RTL (no Directional swap)');
      expect(rect.bottom, screen.height - _bandBottomOffset);
      expect(rect.height, 52);
    });

    testWidgets('TC-212-05 standalone geometry frozen (sentinel)',
        (tester) async {
      suppressChromeErrors();
      setPhoneSurface(tester);

      await tester.pumpWidget(buildOrbitScreenHarness(
        viewMode: OrbitViewMode.allChats,
        searchTriggerAnimation: const AlwaysStoppedAnimation<double>(1.0),
      ));
      await settle(tester);

      final screen = screenSize(tester);
      final rect = tester.getRect(find.byType(OrbitSearchTrigger));
      expect(rect.bottom, screen.height - 88,
          reason: 'standalone keeps its pre-212 bottom:88');
      expect(rect.right, screen.width - 16);
      expect(rect.height, 52, reason: 'the 212 visual upgrade is shared');

      final closeRect = tester.getRect(find.byType(OrbitCloseButton));
      expect(closeRect.top - rect.bottom, 8,
          reason: 'trigger keeps floating 8px above the 44px close button');
    });
  });
}
