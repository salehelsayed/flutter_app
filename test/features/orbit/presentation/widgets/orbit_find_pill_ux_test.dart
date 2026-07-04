import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_dock.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../screens/orbit_screen_pump_harness.dart';

/// 205 items 1-3 — the shipped inner-circle find pill: a discoverable close X
/// that collapses AND dismisses the keyboard, a roomy pill anchored just above
/// the keyboard, and bright (iconPrimary) search lenses on every faint site.
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
  // BackgroundReadableColors.dark tokens under test.
  const iconPrimary = Color(0xFFF8FAFC);

  void suppressAssetErrors(WidgetTester tester) {
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('Unable to load asset') ||
          msg.contains('SvgPicture') ||
          msg.contains('ImageFilter')) {
        return;
      }
      old?.call(details);
    };
    addTearDown(() => FlutterError.onError = old);
  }

  Widget host(
    List<OrbitItem> items, {
    double bottomClearance = 0,
    bool resize = true,
  }) =>
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: const [BackgroundReadableColors.dark]),
        home: Scaffold(
          resizeToAvoidBottomInset: resize,
          body: InnerCircleInteractiveSurface(
            userPeerId: 'me',
            items: items,
            onFriendTap: (_) {},
            onGroupTap: (_) {},
            bottomClearance: bottomClearance,
          ),
        ),
      );

  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  Future<void> settle(WidgetTester tester, {int count = 16}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
  }

  Finder pillF() => find.byKey(const ValueKey('orbit-find-pill'));

  group('205 find-pill UX', () {
    testWidgets(
        'TC-205-01 find pill exposes a close X that collapses and dismisses '
        'the keyboard', (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.tap(pillF());
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend');
      await tester.pump();

      final closeF = find.byKey(const ValueKey('orbit-find-close'));
      expect(closeF, findsOneWidget,
          reason: 'the expanded pill must offer a discoverable close X');

      await tester.tap(closeF);
      await tester.pump();
      // Discriminator: the pill reverts to the 44px collapsed circle AND the
      // TextField is gone (keyboard-dismiss proxy) — distinguishes "closed"
      // from "cleared but still open".
      expect(find.byType(TextField), findsNothing,
          reason: 'field gone → keyboard dismissed');
      expect(tester.getSize(pillF()), const Size(44, 44),
          reason: 'reverted to the collapsed 44px circle');
      await settle(tester);
    });

    testWidgets('TC-205-02 find pill sits just above the keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);

      // resize:false mirrors the production orbit screen — the pill carries the
      // bottomInset term itself; bottomClearance:92 is a persistent-nav floor.
      await tester
          .pumpWidget(host(_friends(8), bottomClearance: 92, resize: false));
      await settle(tester);
      await tester.tap(pillF());
      await tester.pump();

      final surface =
          tester.getRect(find.byType(InnerCircleInteractiveSurface));
      final pill = tester.getRect(pillF());
      final keyboardTop = surface.bottom - 300;
      final gap = keyboardTop - pill.bottom;
      // HEAD: 40 base + max(0, 92-28) unconditional bandLift = 104px float.
      expect(gap, lessThanOrEqualTo(12),
          reason: 'the pill hugs the keyboard top (no unconditional band lift)');
      await settle(tester);
    });

    testWidgets('TC-205-03 expanded find pill is comfortably sized', (
      tester,
    ) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.tap(pillF());
      await tester.pump();

      expect(tester.getSize(pillF()).height, greaterThanOrEqualTo(56),
          reason: 'a roomy >=56 pill (HEAD is 48)');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style?.fontSize, 16, reason: 'HEAD is 15');
      await settle(tester);
    });

    testWidgets('TC-205-04 all faint search lenses use iconPrimary', (
      tester,
    ) async {
      suppressAssetErrors(tester);

      // (a) collapsed find-pill lens.
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      final collapsedLens = tester.widget<Icon>(find.descendant(
        of: pillF(),
        matching: find.byIcon(Icons.search),
      ));
      expect(collapsedLens.color, iconPrimary, reason: 'collapsed pill lens');

      // (b) expanded find-pill lens.
      await tester.tap(pillF());
      await tester.pump();
      final expandedLens = tester.widget<Icon>(find.descendant(
        of: pillF(),
        matching: find.byIcon(Icons.search),
      ));
      expect(expandedLens.color, iconPrimary, reason: 'expanded pill lens');
      await settle(tester);

      // (c) all-chats search dock lens.
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(() {
        controller.dispose();
        focus.dispose();
      });
      await tester.pumpWidget(wrap(OrbitSearchDock(
        controller: controller,
        focusNode: focus,
        onChanged: (_) {},
        onClear: () {},
        onClose: () {},
        query: '',
      )));
      await tester.pump();
      final dockLens = tester.widget<Icon>(find.byIcon(Icons.search));
      expect(dockLens.color, iconPrimary, reason: 'all-chats dock lens');

      // (d) no-results empty-state lens (all-chats surface, size 40).
      await tester.pumpWidget(buildOrbitScreenHarness(
        viewMode: OrbitViewMode.allChats,
        list: const OrbitViewProjection(
          searchActive: true,
          searchQuery: 'zzzzz',
        ),
      ));
      await tester.pump();
      await tester.pump();
      final noResultsLens = tester.widget<Icon>(find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.search && w.size == 40));
      expect(noResultsLens.color, iconPrimary,
          reason: 'no-results empty-state lens');
    });
  });
}
