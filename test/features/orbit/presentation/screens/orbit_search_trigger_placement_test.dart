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

/// Persistent mode seats BOTH bottom-right search affordances ON the nav
/// line: the all-chats search trigger and the Inner-Circle collapsed find
/// pill (re-seated as nav-band chrome) share one slot — right inset 16,
/// vertically centered on the Feed/Orbit bar, 52px circle.

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
        'TC-212-01 persistent all-chats seats the trigger on the nav line, '
        'right edge', (tester) async {
      suppressChromeErrors();
      setPhoneSurface(tester);

      await tester.pumpWidget(persistentPump());
      await settle(tester);

      final screen = screenSize(tester);
      final rect = tester.getRect(find.byType(OrbitSearchTrigger));
      final navRect = tester.getRect(find.byType(FeedNavigationBar));

      expect(rect.right, screen.width - 16,
          reason: 'the trigger keeps the physical right edge (inset 16)');
      expect(rect.center.dy, closeTo(navRect.center.dy, 1.0),
          reason: 'the trigger rides the nav bar\'s vertical level');
      expect(rect.height, 52, reason: '212 visual upgrade: 44 → 52');
      expect(rect.left, greaterThan(navRect.right),
          reason: 'the trigger sits beside the centered bar, not over it');
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
        'TC-212-03 rings pill and list trigger share ONE nav-line seat',
        (tester) async {
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
      final navRect = tester.getRect(find.byType(FeedNavigationBar));
      expect(tester.getSize(pillF), const Size(52, 52));
      expect(pillRect, triggerRect,
          reason: 'one seat on both surfaces — same rect, on the nav line');
      expect(pillRect.center.dy, closeTo(navRect.center.dy, 1.0),
          reason: 'and that seat rides the nav bar\'s vertical level');
    });

    testWidgets(
        'TC-NAVHIDE-01 hideShellNav keeps the nav-line find pill in its seat '
        '(chromeless Orbit must NOT drop the search/find affordance)',
        (tester) async {
      suppressChromeErrors();
      setPhoneSurface(tester);

      Widget ringsPump({required bool hideShellNav}) =>
          buildOrbitScreenHarness(
            viewMode: OrbitViewMode.innerCircle,
            header: OrbitHeaderProjection(
              userPeerId: 'me',
              innerItems: _friends(8),
            ),
            activeTab: 'orbit',
            onSwitchView: (_) {},
            searchTriggerAnimation: const AlwaysStoppedAnimation<double>(1.0),
            hideShellNav: hideShellNav,
          );

      // Baseline: toggle shown → capture the collapsed find pill's seat.
      await tester.pumpWidget(ringsPump(hideShellNav: false));
      await settle(tester);
      final pillF = find.byKey(const ValueKey('orbit-find-pill'));
      final shownRect = tester.getRect(pillF);

      // Chromeless: toggle hidden. The pill must keep the EXACT same seat — a
      // bare SizedBox.shrink collapsed the nav-band Stack and dropped the pill
      // off the bottom edge (the reported search-icon bug).
      await tester.pumpWidget(ringsPump(hideShellNav: true));
      await settle(tester);
      final hiddenRect = tester.getRect(pillF);
      expect(hiddenRect, shownRect,
          reason: 'the nav-line find pill keeps its seat with the toggle hidden');
      final screen = screenSize(tester);
      expect(hiddenRect.bottom, lessThanOrEqualTo(screen.height),
          reason: 'the pill stays on-screen (not clipped past the bottom edge)');

      // The toggle bar stays in the tree for layout (that is what preserves the
      // pill's seat) but is wrapped in a hidden Visibility — invisible and
      // non-interactive.
      expect(find.byType(FeedNavigationBar), findsOneWidget);
      final navVisibilities = find
          .ancestor(
            of: find.byType(FeedNavigationBar),
            matching: find.byType(Visibility),
          )
          .evaluate()
          .map((e) => e.widget as Visibility);
      expect(navVisibilities.any((v) => !v.visible), isTrue,
          reason: 'the hidden toggle is wrapped in a not-visible Visibility');
    });

    testWidgets('TC-212-04 RTL keeps the physical bottom-right corner',
        (tester) async {
      suppressChromeErrors();
      setPhoneSurface(tester);

      await tester.pumpWidget(persistentPump(locale: const Locale('ar')));
      await settle(tester);

      final screen = screenSize(tester);
      final rect = tester.getRect(find.byType(OrbitSearchTrigger));
      final navRect = tester.getRect(find.byType(FeedNavigationBar));
      expect(rect.right, screen.width - 16,
          reason: 'physical-right stance survives RTL (no Directional swap)');
      expect(rect.center.dy, closeTo(navRect.center.dy, 1.0),
          reason: 'the nav-line seat survives RTL too');
      expect(rect.height, 52);
    });

    testWidgets(
        'TC-212-06 nav-line rings pill opens the find bar and hides; '
        'toggling the surface away and back restores it', (tester) async {
      suppressChromeErrors();
      setPhoneSurface(tester);

      Widget ringsPump() => persistentPump(
            viewMode: OrbitViewMode.innerCircle,
            header: OrbitHeaderProjection(
              userPeerId: 'me',
              innerItems: _friends(8),
            ),
          );

      await tester.pumpWidget(ringsPump());
      await settle(tester);

      final pillF = find.byKey(const ValueKey('orbit-find-pill'));
      await tester.tap(pillF);
      await tester.pump();

      // Open: the expanded find bar owns the key (full-width, above the
      // nav); the nav-band collapsed pill is hidden, so ONE key remains.
      expect(pillF, findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.getRect(pillF).width, greaterThan(52),
          reason: 'the key now belongs to the expanded in-surface bar');

      // Toggle away while open (unmounts the find session), then back:
      // the collapsed pill must be back on the nav line, not stuck hidden.
      await tester.pumpWidget(persistentPump());
      await settle(tester);
      await tester.pumpWidget(ringsPump());
      await settle(tester);

      expect(pillF, findsOneWidget);
      expect(tester.getSize(pillF), const Size(52, 52),
          reason: 'the collapsed nav-band pill returned with the rings');
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
