import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';

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

      expect(find.text('Message 1'), findsOneWidget);
      expect(find.text('Message 2'), findsOneWidget);
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

      expect(find.text('Message first'), findsOneWidget);
      expect(find.text('Message second'), findsOneWidget);
      expect(find.text('Message third'), findsOneWidget);
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
  });
}
