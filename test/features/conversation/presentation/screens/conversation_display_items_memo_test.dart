import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  ConversationMessage makeMessage({
    String id = 'm1',
    bool isIncoming = false,
    String text = 'Hello!',
    String timestamp = '2026-02-09T15:30:00.000Z',
    String status = 'delivered',
    String? editedAt,
  }) => ConversationMessage(
    id: id,
    contactPeerId: '12D3KooWTestPeerId1234567890',
    senderPeerId: isIncoming
        ? '12D3KooWTestPeerId1234567890'
        : '12D3KooWMyPeerId1234567890',
    text: text,
    timestamp: timestamp,
    status: status,
    isIncoming: isIncoming,
    createdAt: timestamp,
    editedAt: editedAt,
  );

  Widget buildTestWidget({
    required List<ConversationMessage> messages,
    Locale locale = const Locale('en'),
    bool isSending = false,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ConversationScreen(
          contactPeerId: '12D3KooWTestPeerId1234567890',
          contactUsername: 'Alice',
          connectionDate: 'February 9, 2026',
          ownPeerId: '12D3KooWMyPeerId1234567890',
          messages: messages,
          onSend: (_) {},
          onBack: () {},
          initialLoadDone: true,
          isSending: isSending,
        ),
      ),
    );
  }

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  LetterCard liveLetterCard(WidgetTester tester, String messageId) {
    return tester.widget<LetterCard>(
      find.descendant(
        of: find.byKey(ValueKey('msg-$messageId')),
        matching: find.byType(LetterCard),
      ),
    );
  }

  setUp(() => ConversationScreen.debugDisplayItemsBuildCount = 0);

  // TC-159-03 — an identical-input rebuild reuses the cached grouping pass.
  testWidgets(
    'TC-159-03 _buildDisplayItems is NOT recomputed on an identical-input rebuild',
    (tester) async {
      final messages = [
        makeMessage(id: 'm1', text: 'First'),
        makeMessage(
          id: 'm2',
          text: 'Second',
          timestamp: '2026-02-09T15:31:00.000Z',
        ),
      ];

      await tester.pumpWidget(buildTestWidget(messages: messages));
      await pumpFrames(tester);
      // Re-sync the cache after the post-frame `_wasEmpty` flip settles.
      await tester.pumpWidget(buildTestWidget(messages: messages));
      await pumpFrames(tester);

      ConversationScreen.debugDisplayItemsBuildCount = 0;

      // Unrelated rebuild: SAME messages instance, only `isSending` changes
      // (isSending is not part of the grouping memo key).
      await tester.pumpWidget(
        buildTestWidget(messages: messages, isSending: true),
      );
      await pumpFrames(tester);

      expect(
        ConversationScreen.debugDisplayItemsBuildCount,
        0,
        reason: 'an identical-input rebuild must reuse the cached grouping pass',
      );
    },
  );

  // TC-159-04 — the memo invalidates on a status flip (new list ref) and the
  // rendered glyph reflects the new status.
  testWidgets(
    'TC-159-04 a sent→delivered status flip recomputes and the row updates',
    (tester) async {
      final original = makeMessage(id: 'm1', text: 'Outgoing', status: 'sent');
      await tester.pumpWidget(buildTestWidget(messages: [original]));
      await pumpFrames(tester);
      await tester.pumpWidget(buildTestWidget(messages: [original]));
      await pumpFrames(tester);

      expect(liveLetterCard(tester, 'm1').status, 'sent');
      ConversationScreen.debugDisplayItemsBuildCount = 0;

      // The wired layer reallocates `_messages` on a status change → new ref.
      final flipped = [original.copyWith(status: 'delivered')];
      await tester.pumpWidget(buildTestWidget(messages: flipped));
      await pumpFrames(tester);

      expect(
        ConversationScreen.debugDisplayItemsBuildCount,
        greaterThan(0),
        reason: 'a status flip changes the input list ref → must recompute',
      );
      expect(liveLetterCard(tester, 'm1').status, 'delivered');
    },
  );

  // TC-159-03b — a body mutation (text/editedAt) recomputes and the bubble shows
  // the FRESH content, never the stale `ConversationMessage` in the cached item.
  testWidgets(
    'TC-159-03b a body edit recomputes and the bubble shows the new text',
    (tester) async {
      final original = makeMessage(id: 'm1', text: 'original body');
      await tester.pumpWidget(buildTestWidget(messages: [original]));
      await pumpFrames(tester);
      await tester.pumpWidget(buildTestWidget(messages: [original]));
      await pumpFrames(tester);

      expect(find.text('original body'), findsOneWidget);
      ConversationScreen.debugDisplayItemsBuildCount = 0;

      // Same id/timestamp/status, changed text + editedAt (== is id-only).
      final edited = [
        original.copyWith(
          text: 'edited body',
          editedAt: '2026-02-09T15:35:00.000Z',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(messages: edited));
      await pumpFrames(tester);

      expect(
        ConversationScreen.debugDisplayItemsBuildCount,
        greaterThan(0),
        reason: 'an edit (same id) must recompute — no stale bubble',
      );
      expect(find.text('edited body'), findsOneWidget);
      expect(find.text('original body'), findsNothing);
    },
  );

  // TC-159-03c — a locale change recomputes the day-separator labels even with
  // an identical message-list instance (locale is a key scalar, not in the ref).
  testWidgets(
    'TC-159-03c a locale change recomputes and re-localizes the day separator',
    (tester) async {
      // A past date → an absolute (locale-formatted) day-separator label.
      final messages = [makeMessage(id: 'm1', text: 'Hello')];

      await tester.pumpWidget(
        buildTestWidget(messages: messages, locale: const Locale('en')),
      );
      await pumpFrames(tester);
      await tester.pumpWidget(
        buildTestWidget(messages: messages, locale: const Locale('en')),
      );
      await pumpFrames(tester);

      final enLabel = tester
          .widget<DateSeparator>(find.byType(DateSeparator))
          .label;
      ConversationScreen.debugDisplayItemsBuildCount = 0;

      // SAME message-list instance, only the locale changes.
      await tester.pumpWidget(
        buildTestWidget(messages: messages, locale: const Locale('ar')),
      );
      await pumpFrames(tester);

      expect(
        ConversationScreen.debugDisplayItemsBuildCount,
        greaterThan(0),
        reason: 'a locale switch must invalidate the memo (locale is in the key)',
      );
      final arLabel = tester
          .widget<DateSeparator>(find.byType(DateSeparator))
          .label;
      expect(
        arLabel,
        isNot(enLabel),
        reason: 'the day-separator label must re-localize on a locale switch',
      );
    },
  );
}
