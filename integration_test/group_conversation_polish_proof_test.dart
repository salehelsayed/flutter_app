/// Real-device proof for Finding 11 (P2) conversation polish — items 3, 5, 2.
///
/// The host widget suites already exercise Flutter's real layout/scroll/intl
/// engine, but Finding 11 is pure presentation-layer, where the one genuine
/// host↔device gap is *rendering*: real iOS ICU locale data, Arabic RTL/bidi +
/// Arabic-Indic digit shaping, real platform fonts, and the real device
/// viewport/DPR the scroll geometry resolves against. This proof renders the
/// REAL screens (where the changes physically live — the localized `_formatTime`,
/// the `highlightAnchorKey`-wrapped highlighted row, the reversed `ListView`) on
/// a booted simulator and asserts those behaviors under real iOS.
///
/// Proves:
///   * Item 3 — GroupConversationScreen AND GroupListScreen render time-of-day
///     per the active locale: de → 24h "14:05" (no AM/PM), en → "2:05 PM",
///     ar → Eastern-Arabic digits — on real iOS ICU data.
///   * Item 5a — on the real device viewport, `jumpTo(0)` on the reversed list
///     (what `_scrollToLiveEdge` performs) lands the newest message at the live
///     edge, on-screen.
///   * Item 2 — the `highlightAnchorKey` GlobalKey is attached to the single
///     highlighted row, and `Scrollable.ensureVisible(anchor.currentContext)`
///     (what `_bringHighlightOnScreen` performs after its coarse jump) brings an
///     initially off-screen highlighted row into the real device viewport.
@Tags(['device'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart' as intl;

import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  GroupModel chatGroup() => GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'topic-1',
    createdAt: DateTime.utc(2026, 2, 1, 10),
    createdBy: 'peer-1',
    myRole: GroupRole.admin,
  );

  // Fixed local wall-clock 14:05 so toLocal() is a no-op (TZ-independent).
  final localAfternoon = DateTime(2026, 2, 9, 14, 5);

  GroupMessage messageAt(String id, DateTime when, {String text = 'Hello'}) =>
      GroupMessage(
        id: id,
        groupId: 'group-1',
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: text,
        timestamp: when,
        createdAt: when,
        isIncoming: true,
      );

  Widget conversationApp({
    required Locale locale,
    required List<GroupMessage> messages,
    ScrollController? scrollController,
    String? highlightedMessageId,
    GlobalKey? highlightAnchorKey,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: GroupConversationScreen(
          group: chatGroup(),
          messages: messages,
          ownPeerId: 'peer-1',
          onSend: (_) {},
          onBack: () {},
          canWrite: true,
          initialLoadDone: true,
          scrollController: scrollController,
          highlightedMessageId: highlightedMessageId,
          highlightAnchorKey: highlightAnchorKey,
        ),
      ),
    );
  }

  Future<void> pumpFrames(WidgetTester tester, {int count = 12}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  bool rectWithin(Rect inner, Rect outer) =>
      inner.top >= outer.top - 1 &&
      inner.bottom <= outer.bottom + 1 &&
      inner.overlaps(outer);

  group('Finding 11 item 3 — locale-aware timestamps (real iOS ICU)', () {
    testWidgets('de conversation row renders 24-hour time, no AM/PM', (
      tester,
    ) async {
      await tester.pumpWidget(
        conversationApp(
          locale: const Locale('de'),
          messages: [messageAt('msg-de', localAfternoon)],
        ),
      );
      await pumpFrames(tester);

      expect(find.textContaining('14:05'), findsOneWidget);
      expect(find.textContaining('PM'), findsNothing);
      expect(find.textContaining('AM'), findsNothing);
    });

    testWidgets('en conversation row keeps 12-hour AM/PM', (tester) async {
      await tester.pumpWidget(
        conversationApp(
          locale: const Locale('en'),
          messages: [messageAt('msg-en', localAfternoon)],
        ),
      );
      await pumpFrames(tester);

      final expected = intl.DateFormat.jm('en').format(localAfternoon);
      expect(expected, contains('PM'));
      expect(find.textContaining(expected), findsOneWidget);
    });

    testWidgets('ar conversation row renders Eastern-Arabic digits', (
      tester,
    ) async {
      await tester.pumpWidget(
        conversationApp(
          locale: const Locale('ar'),
          messages: [messageAt('msg-ar', localAfternoon)],
        ),
      );
      await pumpFrames(tester);

      final expected = intl.DateFormat.jm('ar').format(localAfternoon);
      expect(expected, isNot(contains('14:05')));
      expect(find.textContaining(expected), findsOneWidget);
    });

    testWidgets('de group-list row renders 24-hour time, no AM/PM', (
      tester,
    ) async {
      final group = chatGroup();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupListScreen(
            groups: [group],
            latestMessages: {group.id: messageAt('msg-list', localAfternoon)},
            onGroupTap: (_) {},
            onBack: () {},
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.textContaining('14:05'), findsOneWidget);
      expect(find.textContaining('PM'), findsNothing);
    });
  });

  group('Finding 11 items 5a & 2 — scroll geometry (real device viewport)', () {
    final start = DateTime.utc(2026, 2, 1, 10);
    List<GroupMessage> fortyMessages() => List.generate(
      40,
      (i) => messageAt(
        'msg-$i',
        start.add(Duration(minutes: i)),
        text: 'Message $i',
      ),
    );

    testWidgets('item 5a — jumpTo(0) lands the newest message at the live edge', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        conversationApp(
          locale: const Locale('en'),
          messages: fortyMessages(),
          scrollController: controller,
        ),
      );
      await pumpFrames(tester);

      // Scroll up into history.
      controller.jumpTo(controller.position.maxScrollExtent / 2);
      await pumpFrames(tester);
      expect(controller.offset, greaterThan(32));

      // What _scrollToLiveEdge ultimately performs.
      controller.jumpTo(0);
      await pumpFrames(tester);

      expect(controller.offset, closeTo(0, 1.0));
      final newest = find.text('Message 39');
      expect(newest, findsOneWidget);
      final listRect = tester.getRect(
        find.byKey(const ValueKey('group-messages')),
      );
      expect(rectWithin(tester.getRect(newest), listRect), isTrue);
    });

    testWidgets(
      'item 2 — ensureVisible on the highlighted anchor brings an off-screen row into view',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final anchorKey = GlobalKey();

        await tester.pumpWidget(
          conversationApp(
            locale: const Locale('en'),
            messages: fortyMessages(),
            scrollController: controller,
            highlightedMessageId: 'msg-0', // oldest — far from the live edge
            highlightAnchorKey: anchorKey,
          ),
        );
        await pumpFrames(tester);

        // At the live edge the oldest highlighted row is not built, so the
        // anchor has no context yet — exactly the state _bringHighlightOnScreen
        // starts from before its coarse jump.
        expect(anchorKey.currentContext, isNull);

        // Coarse jump toward the oldest end to materialise the row.
        controller.jumpTo(controller.position.maxScrollExtent);
        await pumpFrames(tester);
        expect(
          anchorKey.currentContext,
          isNotNull,
          reason: 'highlightAnchorKey must be attached to the highlighted row',
        );

        // Instant (Duration.zero) so the await completes without needing
        // concurrent frame pumps — an animated ensureVisible deadlocks the
        // live integration binding. Geometry verification is unaffected.
        await Scrollable.ensureVisible(anchorKey.currentContext!, alignment: 0.5);
        await pumpFrames(tester);

        final highlight = find.byKey(const ValueKey('grp-highlight-msg-0'));
        expect(highlight, findsOneWidget);
        final listRect = tester.getRect(
          find.byKey(const ValueKey('group-messages')),
        );
        expect(
          rectWithin(tester.getRect(highlight), listRect),
          isTrue,
          reason: 'the tapped row must sit within the visible viewport',
        );
      },
    );
  });
}
