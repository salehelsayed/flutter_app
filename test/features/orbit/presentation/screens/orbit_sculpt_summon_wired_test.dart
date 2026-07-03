import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/secure_storage/fake_secure_key_store.dart';

/// 198 F6 — the interactive Inner-Circle surface (Sculpt & Summon) driven
/// through its real production widget: edit session, geometry handles, find,
/// labels, persistence, and the reset seam.
class _SpyStore extends FakeSecureKeyStore {
  int writes = 0;
  int deletes = 0;
  @override
  Future<void> write(String key, String value) {
    writes++;
    return super.write(key, value);
  }

  @override
  Future<void> delete(String key) {
    deletes++;
    return super.delete(key);
  }
}

OrbitItem _friend(int i, {int unread = 0}) => OrbitFriendItem(OrbitFriend(
      contact: ContactModel(
        peerId: 'peer-$i',
        publicKey: 'pk-$i',
        rendezvous: '/ip4/127.0.0.1/tcp/400$i',
        username: 'friend$i',
        signature: 'sig-$i',
        scannedAt: '2024-01-01T00:00:00Z',
      ),
      messageCount: i,
      unreadCount: unread,
      lastMessageTimestamp: '2024-01-01T00:00:00Z',
    ));

OrbitItem _group(String name) => OrbitGroupItem(OrbitGroup(
      group: GroupModel(
        id: 'g-$name',
        name: name,
        type: GroupType.chat,
        topicName: 'topic-$name',
        createdBy: 'creator',
        myRole: GroupRole.admin,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      lastActivityTimestamp: DateTime.utc(2026, 7, 2),
    ));

List<OrbitItem> _friends(int n) => [for (var i = 0; i < n; i++) _friend(i)];

void main() {
  late List<OrbitFriend> tappedFriends;
  late List<OrbitGroup> tappedGroups;
  late List<bool> editEvents;

  setUp(() {
    tappedFriends = [];
    tappedGroups = [];
    editEvents = [];
  });

  Widget host(
    List<OrbitItem> items, {
    FakeSecureKeyStore? store,
    Listenable? resetSignal,
    Key? key,
  }) =>
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [BackgroundReadableColors.dark]),
        home: Scaffold(
          body: InnerCircleInteractiveSurface(
            key: key,
            userPeerId: 'me',
            items: items,
            onFriendTap: tappedFriends.add,
            onGroupTap: tappedGroups.add,
            secureKeyStore: store,
            onEditSessionActiveChanged: editEvents.add,
            resetSignal: resetSignal,
          ),
        ),
      );

  Future<void> settle(WidgetTester tester, {int count = 16}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
  }

  Offset bgPoint(WidgetTester tester) {
    // A point to the LEFT of the (horizontally centered) circle column — empty
    // background, never on a node/title/caption, so the sibling background
    // gesture layer receives it.
    final r = tester.getRect(
        find.byKey(const ValueKey('orbit-inner-circle-background')));
    return Offset(r.left + 36, r.center.dy);
  }

  Future<void> longPressBg(WidgetTester tester) async {
    final g = await tester.startGesture(bgPoint(tester));
    await tester.pump(const Duration(milliseconds: 620)); // past 500ms long-press
    await g.up();
    await tester.pump();
  }

  Future<void> doubleTapBg(WidgetTester tester) async {
    final p = bgPoint(tester);
    final g1 = await tester.startGesture(p);
    await g1.up();
    await tester.pump(const Duration(milliseconds: 60));
    final g2 = await tester.startGesture(p);
    await g2.up();
    await tester.pump();
  }

  Future<void> tapAwayBg(WidgetTester tester) async {
    final g = await tester.startGesture(bgPoint(tester));
    await g.up();
    await tester.pump(const Duration(milliseconds: 350)); // clear double-tap window
  }

  Finder bannerF() => find.byKey(const ValueKey('orbit-edit-banner'));
  Finder handleF(OrbitKnob k) =>
      find.byKey(ValueKey('orbit-handle-${k.name}'));
  Finder bubbleF() => find.byKey(const ValueKey('orbit-edit-value-bubble'));

  group('198 F6 — edit session (Group B)', () {
    testWidgets('TC-198-14 long-press empty space enters edit (banner, Reset)',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      expect(bannerF(), findsNothing);

      await longPressBg(tester);
      expect(bannerF(), findsOneWidget);
      expect(find.byKey(const ValueKey('orbit-edit-reset')), findsOneWidget);
      expect(editEvents, [true]);
      await settle(tester);
    });

    testWidgets('TC-198-26 collapsed edit shows only av/sp handles',
        (tester) async {
      await tester.pumpWidget(host(_friends(20))); // overflow, but collapsed
      await settle(tester);
      await longPressBg(tester);
      expect(handleF(OrbitKnob.avatarScale), findsOneWidget);
      expect(handleF(OrbitKnob.spacingScale), findsOneWidget);
      expect(handleF(OrbitKnob.arcWrap), findsNothing);
      expect(handleF(OrbitKnob.maxPerArc), findsNothing);
      expect(handleF(OrbitKnob.orbitGap), findsNothing);
      await settle(tester);
    });

    testWidgets('expanded edit shows all 5 handles', (tester) async {
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await tester.tap(find.byType(OverflowBadge)); // expand arcs
      await settle(tester);
      await longPressBg(tester);
      for (final k in OrbitKnob.values) {
        expect(handleF(k), findsOneWidget, reason: '${k.name} handle');
      }
      await settle(tester);
    });

    testWidgets('TC-198-20/21 arm shows bubble + steppers; step + clamp',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      expect(bubbleF(), findsNothing);

      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      expect(bubbleF(), findsOneWidget);
      expect(find.text('1.0×'), findsOneWidget);
      expect(find.byKey(const ValueKey('orbit-edit-step-increase')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('orbit-edit-step-increase')));
      await tester.pump();
      expect(find.text('1.2×'), findsOneWidget);
      // saturate at 1.4 without throwing.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const ValueKey('orbit-edit-step-increase')));
        await tester.pump();
      }
      expect(find.text('1.4×'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('TC-198-22 handle drag changes the knob', (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      expect(find.text('1.0×'), findsOneWidget);

      // Drag up increases avatarScale (-dy/90); a big drag saturates at 1.4.
      await tester.drag(handleF(OrbitKnob.avatarScale), const Offset(0, -80));
      await tester.pump();
      expect(find.text('1.0×'), findsNothing);
      await settle(tester);
    });

    testWidgets('TC-198-25 Reset restores defaults, session stays active',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-edit-step-increase')));
      await tester.pump();
      expect(find.text('1.2×'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('orbit-edit-reset')));
      await tester.pump();
      // still editing (banner present), value back to default.
      expect(bannerF(), findsOneWidget);
      expect(find.text('1.0×'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('TC-198-18 empty-space tap-away exits; callback fires false',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      expect(bannerF(), findsOneWidget);

      await tapAwayBg(tester);
      expect(bannerF(), findsNothing);
      expect(editEvents, [true, false]);
      await settle(tester);
    });

    testWidgets('TC-198-19 dimmed node tap-away exits edit, does NOT open chat',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      expect(bannerF(), findsOneWidget);

      // Tapping a (dimmed) node while editing ends the session without routing.
      await tester.tap(find.bySemanticsLabel('Open chat with friend0'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(bannerF(), findsNothing);
      expect(tappedFriends, isEmpty);
      await settle(tester);
    });

    testWidgets('TC-198-27 badge toggles arcs mid-edit without exiting',
        (tester) async {
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await longPressBg(tester);
      expect(bannerF(), findsOneWidget);

      await tester.tap(find.byType(OverflowBadge));
      await settle(tester);
      // still editing, and now all 5 handles show (arcs expanded).
      expect(bannerF(), findsOneWidget);
      expect(handleF(OrbitKnob.orbitGap), findsOneWidget);
      await settle(tester);
    });

    testWidgets('TC-198-15 long-press on a node does not enter edit',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.longPress(find.bySemanticsLabel('Open chat with friend0'));
      await tester.pump();
      expect(bannerF(), findsNothing);
      await settle(tester);
    });
  });

  group('198 F6 — persistence (Group D)', () {
    testWidgets('TC-198-33 sculpt persists across a remount', (tester) async {
      final store = FakeSecureKeyStore();
      await tester.pumpWidget(host(_friends(8), store: store, key: const ValueKey('a')));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-edit-step-increase')));
      await tester.pump();
      expect(find.text('1.2×'), findsOneWidget);
      await settle(tester);

      // Remount a fresh surface state against the same store.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(host(_friends(8), store: store, key: const ValueKey('b')));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      expect(find.text('1.2×'), findsOneWidget,
          reason: 'restored the persisted avatarScale');
      await settle(tester);
    });

    testWidgets('TC-198-36 Reset deletes the key → fresh mount is default',
        (tester) async {
      final store = FakeSecureKeyStore();
      await store.write(OrbitGeometryPrefs.storageKey, '1.2|1.0|1.0|9|1.0');
      await tester.pumpWidget(host(_friends(8), store: store, key: const ValueKey('a')));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-edit-reset')));
      await tester.pump();
      await settle(tester);

      expect(await store.read(OrbitGeometryPrefs.storageKey), isNull);
    });

    testWidgets('TC-198-38 no write until first edit; first edit writes once',
        (tester) async {
      final spy = _SpyStore();
      await tester.pumpWidget(host(_friends(20), store: spy));
      await settle(tester);
      // Expansion + labels write nothing.
      await tester.tap(find.byType(OverflowBadge));
      await settle(tester);
      await doubleTapBg(tester); // labels
      await settle(tester);
      expect(spy.writes, 0);

      // First knob edit writes.
      await longPressBg(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-edit-step-increase')));
      await tester.pump();
      expect(spy.writes, 1);
      await settle(tester);
    });
  });

  group('198 F6 — find (Group E)', () {
    testWidgets('TC-198-39 find pill present, expands with focus',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      expect(find.byKey(const ValueKey('orbit-find-pill')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      await settle(tester);
    });

    testWidgets('TC-198-40 single match lights + chip with ring provenance',
        (tester) async {
      final items = <OrbitItem>[_friend(0), _group('Zenith'), _friend(2)];
      await tester.pumpWidget(host(items));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'zenith');
      await tester.pump();
      // one chip, provenance "Ring 1" (index 1 → ring 1).
      expect(find.byKey(const ValueKey('orbit-find-chip-1')), findsOneWidget);
      expect(find.text('Ring 1'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('TC-198-41 six matches light all, exactly 4 chips',
        (tester) async {
      final items = [for (var i = 0; i < 6; i++) _friend(i)]; // friend0..5
      await tester.pumpWidget(host(items));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend');
      await tester.pump();
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('orbit-find-chip-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('orbit-find-chip-4')), findsNothing);
      await settle(tester);
    });

    testWidgets('TC-198-44 group match chips + opens the group conversation',
        (tester) async {
      final items = <OrbitItem>[..._friends(5), _group('Book Club')];
      await tester.pumpWidget(host(items));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'book');
      await tester.pump();
      final chip = find.byKey(const ValueKey('orbit-find-chip-5'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pump();
      expect(tappedGroups.single.name, 'Book Club');
      await settle(tester);
    });

    testWidgets('TC-198-46 zero matches → no chips (anti-signal)',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'zzzzz');
      await tester.pump();
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsNothing);
      await settle(tester);
    });

    testWidgets('TC-198-48 tap-away closes + clears find', (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend');
      await tester.pump();
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsOneWidget);

      await tapAwayBg(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsNothing);
      await settle(tester);
    });
  });

  group('198 F6 — composition (Group F) + reset (Group R)', () {
    testWidgets('TC-198-53 double-tap toggles labels', (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      expect(find.text('friend0'), findsNothing);

      await doubleTapBg(tester);
      await settle(tester);
      expect(find.text('friend0'), findsOneWidget);

      await doubleTapBg(tester);
      await settle(tester);
      expect(find.text('friend0'), findsNothing);
    });

    testWidgets('TC-198-50 typing in find does not exit edit', (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      expect(bannerF(), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend');
      await tester.pump();
      expect(bannerF(), findsOneWidget, reason: 'edit survives find typing');
      await settle(tester);
    });

    testWidgets('TC-198-52 chip tap opens chat AND ends edit', (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend0');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-find-chip-0')));
      await tester.pump();
      expect(tappedFriends.single.username, 'friend0');
      expect(bannerF(), findsNothing, reason: 'chip tap ended the edit session');
      await settle(tester);
    });

    testWidgets('TC-198-54 single node tap opens chat immediately',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Open chat with friend3'));
      await tester.pump(); // no double-tap-timeout wait
      expect(tappedFriends.single.username, 'friend3');
      await settle(tester);
    });

    testWidgets('TC-198-63 reset signal collapses arcs, exits edit, clears find',
        (tester) async {
      final reset = ValueNotifier<int>(0);
      addTearDown(reset.dispose);
      await tester.pumpWidget(host(_friends(20), resetSignal: reset));
      await settle(tester);
      await tester.tap(find.byType(OverflowBadge)); // expand
      await settle(tester);
      await longPressBg(tester); // edit
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend');
      await tester.pump();
      expect(bannerF(), findsOneWidget);
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsOneWidget);

      reset.value++; // Feed→Orbit rising edge
      await settle(tester);
      expect(bannerF(), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsNothing);
      expect(editEvents.last, isFalse);
    });
  });
}
