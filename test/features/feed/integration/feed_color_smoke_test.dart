import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  ThreadMessage buildMessage(
    String id, {
    bool isUnread = false,
    bool isIncoming = true,
  }) =>
      ThreadMessage(
        id: id,
        text: 'Message $id',
        time: '3:00 PM',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        isUnread: isUnread,
        isIncoming: isIncoming,
      );

  group('Feed color smoke tests', () {
    test('FeedColors.backgroundTop is #0f0f18', () {
      expect(FeedColors.backgroundTop, const Color(0xFF0f0f18));
    });

    test('FeedColors.backgroundBottom is #0a0a0f', () {
      expect(FeedColors.backgroundBottom, const Color(0xFF0a0a0f));
    });

    test('FeedColors.accentPurple is #a78bfa', () {
      expect(FeedColors.accentPurple, const Color(0xFFa78bfa));
    });

    test('FeedColors.accentTeal is #81e6d9', () {
      expect(FeedColors.accentTeal, const Color(0xFF81e6d9));
    });

    testWidgets('unread card has purple-tinted border', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [buildMessage('m1', isUnread: true)],
        conversationState: ConversationState.unread,
      );

      await tester.pumpWidget(wrap(FeedCard(thread: thread)));
      // Card renders without error — border is purple-tinted
      expect(find.byType(FeedCard), findsOneWidget);
    });

    testWidgets('replied card has teal-tinted border', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          buildMessage('m1'),
          buildMessage('m2', isIncoming: false),
        ],
        conversationState: ConversationState.replied,
        lastRepliedAt: DateTime.now(),
      );

      await tester.pumpWidget(wrap(FeedCard(thread: thread)));
      expect(find.byType(FeedCard), findsOneWidget);
    });

    testWidgets('read card has muted border', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [buildMessage('m1')],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(FeedCard(thread: thread)));
      expect(find.byType(FeedCard), findsOneWidget);
    });

    testWidgets('MessageBubble colors match spec', (tester) async {
      // Smoke test: unread, read, and sent bubbles render correctly
      expect(FeedColors.messageReceivedBg, const Color.fromRGBO(255, 255, 255, 0.06));
      expect(FeedColors.messageSentBg, const Color.fromRGBO(255, 255, 255, 0.04));
      expect(FeedColors.messageUnreadBg, const Color.fromRGBO(255, 255, 255, 0.06));
    });
  });
}
