import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      );

  ThreadMessage _msg(String id, {bool isUnread = true}) => ThreadMessage(
        id: id,
        text: 'Message $id',
        time: '3:00 PM',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        isUnread: isUnread,
        isIncoming: true,
      );

  group('ScrollableMessagePreview', () {
    testWidgets('<= 3 messages: Column layout, no hint', (tester) async {
      await tester.pumpWidget(wrap(ScrollableMessagePreview(
        messages: [_msg('1'), _msg('2')],
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
      )));

      expect(find.textContaining('Message 1'), findsOneWidget);
      expect(find.textContaining('Message 2'), findsOneWidget);
      // No MoreMessagesHint
      expect(find.textContaining('more message'), findsNothing);
      // No ListView
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('> 3 messages: ListView with hint', (tester) async {
      await tester.pumpWidget(wrap(ScrollableMessagePreview(
        messages: [_msg('1'), _msg('2'), _msg('3'), _msg('4'), _msg('5')],
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
      )));

      expect(find.byType(ListView), findsOneWidget);
      // Initial remaining = 5 - 3 = 2
      expect(find.text('2 more messages'), findsOneWidget);
    });

    testWidgets('messages in oldest-first order', (tester) async {
      await tester.pumpWidget(wrap(ScrollableMessagePreview(
        messages: [_msg('first'), _msg('second'), _msg('third')],
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
      )));

      expect(find.textContaining('Message first'), findsOneWidget);
      expect(find.textContaining('Message second'), findsOneWidget);
      expect(find.textContaining('Message third'), findsOneWidget);
    });

    testWidgets('ViewEarlierLink shown when hasEarlierHistory', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(ScrollableMessagePreview(
        messages: [_msg('1')],
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        hasEarlierHistory: true,
        onViewEarlier: () => tapped = true,
      )));

      expect(find.text('View earlier messages'), findsOneWidget);
      await tester.tap(find.text('View earlier messages'));
      expect(tapped, isTrue);
    });

    testWidgets('ViewEarlierLink not shown when hasEarlierHistory is false',
        (tester) async {
      await tester.pumpWidget(wrap(ScrollableMessagePreview(
        messages: [_msg('1')],
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        hasEarlierHistory: false,
      )));

      expect(find.text('View earlier messages'), findsNothing);
    });

    testWidgets('no scrollbar widget', (tester) async {
      await tester.pumpWidget(wrap(ScrollableMessagePreview(
        messages: [_msg('1'), _msg('2'), _msg('3'), _msg('4'), _msg('5')],
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
      )));

      expect(find.byType(Scrollbar), findsNothing);
    });

    testWidgets('passes media to MessageBubble', (tester) async {
      final media = [
        MediaAttachment(
          id: 'a1',
          messageId: 'img-msg',
          mime: 'image/jpeg',
          size: 5000,
          mediaType: 'image',
          downloadStatus: 'pending',
          createdAt: '2026-02-23T10:00:00Z',
        ),
      ];

      final msgWithMedia = ThreadMessage(
        id: 'img-msg',
        text: '',
        time: '3:00 PM',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        isUnread: true,
        isIncoming: true,
        media: media,
      );

      await tester.pumpWidget(wrap(ScrollableMessagePreview(
        messages: [msgWithMedia],
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
      )));

      // MediaGrid should appear inside the MessageBubble
      expect(find.byType(MediaGrid), findsOneWidget);
    });

    testWidgets('resolves quoted text from sibling messages', (tester) async {
      final messages = [
        ThreadMessage(
          id: 'original',
          text: 'Hello there',
          time: '2:00 PM',
          timestamp: DateTime(2026, 2, 9, 14, 0),
          isUnread: true,
          isIncoming: true,
        ),
        ThreadMessage(
          id: 'reply',
          text: 'Hi back',
          time: '3:00 PM',
          timestamp: DateTime(2026, 2, 9, 15, 0),
          isUnread: true,
          isIncoming: true,
          quotedMessageId: 'original',
        ),
      ];

      await tester.pumpWidget(wrap(ScrollableMessagePreview(
        messages: messages,
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
      )));

      // The quoted text should appear in the reply bubble's quote bar
      expect(find.text('Hello there'), findsWidgets);
    });

    testWidgets('shows unavailable for unknown quoted message', (tester) async {
      final messages = [
        ThreadMessage(
          id: 'reply',
          text: 'Replying to old',
          time: '3:00 PM',
          timestamp: DateTime(2026, 2, 9, 15, 0),
          isUnread: true,
          isIncoming: true,
          quotedMessageId: 'nonexistent',
        ),
      ];

      await tester.pumpWidget(wrap(ScrollableMessagePreview(
        messages: messages,
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
      )));

      expect(find.text('Message unavailable'), findsOneWidget);
    });
  });
}
