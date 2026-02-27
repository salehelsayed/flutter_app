import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_display.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';

void main() {
  Widget buildTestWidget({
    bool isIncoming = true,
    String? status,
    String senderName = 'Alice',
    String text = 'Hello, this is a test message.',
    String time = '3:30 PM',
    String? transport,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LetterCard(
            senderPeerId: '12D3KooWTestPeerId1234567890',
            senderName: senderName,
            text: text,
            time: time,
            isIncoming: isIncoming,
            status: status,
            transport: transport,
          ),
        ),
      ),
    );
  }

  group('LetterCard', () {
    group('received (incoming) card', () {
      testWidgets('shows sender name', (tester) async {
        await tester.pumpWidget(buildTestWidget(isIncoming: true));
        expect(find.text('Alice'), findsOneWidget);
      });

      testWidgets('shows message text', (tester) async {
        await tester.pumpWidget(buildTestWidget(isIncoming: true));
        expect(find.text('Hello, this is a test message.'), findsOneWidget);
      });

      testWidgets('shows time', (tester) async {
        await tester.pumpWidget(buildTestWidget(isIncoming: true));
        expect(find.text('3:30 PM'), findsOneWidget);
      });

      testWidgets('does not show delivery note', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: true, status: null),
        );
        expect(find.byIcon(Icons.done_rounded), findsNothing);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      });
    });

    group('sent (outgoing) card', () {
      testWidgets('shows sender name (You)', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, senderName: 'You', status: 'sent'),
        );
        expect(find.text('You'), findsOneWidget);
      });

      testWidgets('shows message body', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'sent'),
        );
        expect(find.text('Hello, this is a test message.'), findsOneWidget);
      });

      testWidgets('shows one tick when status is sending', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'sending'),
        );
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      });

      testWidgets('shows one tick when status is sent', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'sent'),
        );
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      });

      testWidgets('shows two ticks when status is delivered', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'delivered'),
        );
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      });

      testWidgets('shows two ticks when status is queued', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'queued'),
        );
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      });

      testWidgets('shows failed icon when status is failed', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'failed'),
        );
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      });

      testWidgets('no delivery note when status is null', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: null),
        );
        expect(find.byIcon(Icons.done_rounded), findsNothing);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      });
    });

    testWidgets('renders RingAvatar with 32px size', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final avatar32 = sizedBoxes.where(
        (sb) => sb.width == 32 && sb.height == 32,
      );
      expect(avatar32, isNotEmpty);
    });

    group('transport icons', () {
      testWidgets('shows wifi icon when transport is wifi', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(transport: 'wifi'),
        );
        expect(find.byIcon(Icons.wifi), findsOneWidget);
      });

      testWidgets('shows relay icon when transport is relay', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(transport: 'relay'),
        );
        expect(find.byIcon(Icons.cell_tower), findsOneWidget);
      });

      testWidgets('shows inbox icon when transport is inbox', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(transport: 'inbox'),
        );
        expect(find.byIcon(Icons.inbox), findsOneWidget);
      });

      testWidgets('shows no transport icon when transport is null',
          (tester) async {
        await tester.pumpWidget(
          buildTestWidget(transport: null),
        );
        expect(find.byIcon(Icons.wifi), findsNothing);
        expect(find.byIcon(Icons.cell_tower), findsNothing);
        expect(find.byIcon(Icons.inbox), findsNothing);
      });

      testWidgets('unrecognized transport shows help_outline icon',
          (tester) async {
        await tester.pumpWidget(
          buildTestWidget(transport: 'carrier_pigeon'),
        );
        expect(find.byIcon(Icons.help_outline), findsOneWidget);
      });
    });

    group('URL links', () {
      testWidgets('URL in message body renders as tappable link',
          (tester) async {
        await tester.pumpWidget(
          buildTestWidget(text: 'Check https://example.com out'),
        );
        expect(find.byType(LinkableText), findsOneWidget);
      });

      testWidgets('URL has underline decoration', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(text: 'https://example.com'),
        );
        final richText = tester.widget<RichText>(
          find.descendant(
            of: find.byType(LinkableText),
            matching: find.byType(RichText),
          ),
        );
        final outer = richText.text as TextSpan;
        final inner = outer.children![0] as TextSpan;
        final urlSpan = inner.children!.whereType<TextSpan>().first;
        expect(urlSpan.style?.decoration, TextDecoration.underline);
      });

      testWidgets('plain text without URLs still renders', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(text: 'Just a plain message'),
        );
        expect(find.byType(LinkableText), findsOneWidget);
        expect(find.textContaining('Just a plain message'), findsOneWidget);
      });
    });

    group('reactions', () {
      testWidgets('renders ReactionDisplay when reactions provided',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LetterCard(
                  senderPeerId: '12D3KooWTestPeerId1234567890',
                  senderName: 'Alice',
                  text: 'Hello',
                  time: '3:30 PM',
                  isIncoming: true,
                  ownPeerId: 'my-peer',
                  reactions: const [
                    MessageReaction(
                      id: 'r1',
                      messageId: 'msg-1',
                      emoji: '👍',
                      senderPeerId: 'sender-1',
                      timestamp: '2026-02-27T10:00:00.000Z',
                      createdAt: '2026-02-27T10:00:01.000Z',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(find.byType(ReactionDisplay), findsOneWidget);
        expect(find.text('👍'), findsOneWidget);
      });

      testWidgets('hidden when reactions empty', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        expect(find.byType(ReactionDisplay), findsNothing);
      });

      testWidgets('fires onLongPress on long-press', (tester) async {
        var pressed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LetterCard(
                  senderPeerId: '12D3KooWTestPeerId1234567890',
                  senderName: 'Alice',
                  text: 'Hello',
                  time: '3:30 PM',
                  isIncoming: true,
                  onLongPress: () => pressed = true,
                ),
              ),
            ),
          ),
        );
        await tester.longPress(find.text('Hello'));
        expect(pressed, isTrue);
      });

      testWidgets('fires onReactionTap when chip tapped', (tester) async {
        String? tappedEmoji;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LetterCard(
                  senderPeerId: '12D3KooWTestPeerId1234567890',
                  senderName: 'Alice',
                  text: 'Hello',
                  time: '3:30 PM',
                  isIncoming: true,
                  ownPeerId: 'my-peer',
                  reactions: const [
                    MessageReaction(
                      id: 'r1',
                      messageId: 'msg-1',
                      emoji: '👍',
                      senderPeerId: 'sender-1',
                      timestamp: '2026-02-27T10:00:00.000Z',
                      createdAt: '2026-02-27T10:00:01.000Z',
                    ),
                  ],
                  onReactionTap: (emoji) => tappedEmoji = emoji,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('👍'));
        expect(tappedEmoji, '👍');
      });
    });
  });
}
