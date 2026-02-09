import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';

void main() {
  Widget buildTestWidget({
    List<ConversationMessage> messages = const [],
    ValueChanged<String>? onSend,
    VoidCallback? onBack,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ConversationScreen(
          contactPeerId: '12D3KooWTestPeerId1234567890',
          contactUsername: 'Alice',
          connectionDate: 'February 9, 2026',
          ownPeerId: '12D3KooWMyPeerId1234567890',
          messages: messages,
          onSend: onSend ?? (_) {},
          onBack: onBack ?? () {},
        ),
      ),
    );
  }

  ConversationMessage makeMessage({
    String id = 'msg-1',
    bool isIncoming = true,
    String text = 'Hello!',
    String timestamp = '2026-02-09T15:30:00.000Z',
    String status = 'delivered',
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: '12D3KooWTestPeerId1234567890',
      senderPeerId: isIncoming
          ? '12D3KooWTestPeerId1234567890'
          : '12D3KooWMyPeerId1234567890',
      text: text,
      timestamp: timestamp,
      status: status,
      isIncoming: isIncoming,
      createdAt: '2026-02-09T15:30:01.000Z',
    );
  }

  // Use pump with duration instead of pumpAndSettle because
  // AmbientBackground has a repeating 8s animation that never settles.
  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('ConversationScreen', () {
    testWidgets('shows empty state when no messages', (tester) async {
      await tester.pumpWidget(buildTestWidget(messages: []));
      await tester.pump();

      expect(find.text('Connected!'), findsWidgets);
      expect(
        find.text('Write the first letter\nto start your conversation'),
        findsOneWidget,
      );
    });

    testWidgets('shows letter cards when messages present', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        messages: [
          makeMessage(id: 'msg-1', text: 'First message'),
        ],
      ));
      await pumpFrames(tester);

      expect(find.text('First message'), findsOneWidget);
      expect(
        find.text('Write the first letter\nto start your conversation'),
        findsNothing,
      );
    });

    testWidgets('compose area always visible', (tester) async {
      await tester.pumpWidget(buildTestWidget(messages: []));
      await tester.pump();

      expect(find.text('Write something...'), findsOneWidget);
    });

    testWidgets('compose area visible with messages too', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        messages: [makeMessage()],
      ));
      await pumpFrames(tester);

      expect(find.text('Write something...'), findsOneWidget);
    });

    testWidgets('header shows contact name', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows origin marker when messages present', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        messages: [makeMessage()],
      ));
      await pumpFrames(tester);

      // Compact origin marker shows "Connected!" text
      expect(find.text('Connected!'), findsWidgets);
    });

    testWidgets('shows date separator for today\'s messages', (tester) async {
      final now = DateTime.now().toUtc().toIso8601String();
      await tester.pumpWidget(buildTestWidget(
        messages: [makeMessage(timestamp: now)],
      ));
      await pumpFrames(tester);

      expect(find.text('TODAY'), findsOneWidget);
    });
  });
}
