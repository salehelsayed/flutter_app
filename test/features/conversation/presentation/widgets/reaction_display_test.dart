import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_display.dart';

void main() {
  group('ReactionDisplay', () {
    testWidgets('renders nothing when reactions empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReactionDisplay(reactions: [], ownPeerId: 'my-peer'),
          ),
        ),
      );
      expect(find.byType(Wrap), findsNothing);
    });

    testWidgets('renders emoji chips grouped by emoji with counts', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReactionDisplay(
              reactions: [
                MessageReaction(
                  id: 'r1',
                  messageId: 'msg-1',
                  emoji: '👍',
                  senderPeerId: 'sender-1',
                  timestamp: '2026-02-27T10:00:00.000Z',
                  createdAt: '2026-02-27T10:00:01.000Z',
                ),
                MessageReaction(
                  id: 'r2',
                  messageId: 'msg-1',
                  emoji: '👍',
                  senderPeerId: 'sender-2',
                  timestamp: '2026-02-27T10:01:00.000Z',
                  createdAt: '2026-02-27T10:01:01.000Z',
                ),
                MessageReaction(
                  id: 'r3',
                  messageId: 'msg-1',
                  emoji: '❤️',
                  senderPeerId: 'sender-3',
                  timestamp: '2026-02-27T10:02:00.000Z',
                  createdAt: '2026-02-27T10:02:01.000Z',
                ),
              ],
              ownPeerId: 'my-peer',
            ),
          ),
        ),
      );

      // 👍 has count 2, ❤️ has count 1
      expect(find.text('👍 2'), findsOneWidget);
      expect(find.text('❤️'), findsOneWidget);
    });

    testWidgets('highlights chip when ownPeerId matches sender', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReactionDisplay(
              reactions: [
                MessageReaction(
                  id: 'r1',
                  messageId: 'msg-1',
                  emoji: '👍',
                  senderPeerId: 'my-peer',
                  timestamp: '2026-02-27T10:00:00.000Z',
                  createdAt: '2026-02-27T10:00:01.000Z',
                ),
              ],
              ownPeerId: 'my-peer',
            ),
          ),
        ),
      );

      // Find the container with the teal border
      final containers = tester.widgetList<Container>(find.byType(Container));
      final tealBorderContainers = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.border is Border) {
          final border = decoration.border as Border;
          return border.top.color == const Color.fromRGBO(78, 205, 196, 0.30);
        }
        return false;
      });
      expect(tealBorderContainers, isNotEmpty);
    });

    testWidgets('fires onReactionTap with emoji string on tap', (tester) async {
      String? tappedEmoji;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionDisplay(
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
              ownPeerId: 'my-peer',
              onReactionTap: (emoji) => tappedEmoji = emoji,
            ),
          ),
        ),
      );

      await tester.tap(find.text('👍'));
      expect(tappedEmoji, '👍');
    });

    testWidgets('renders non-preset emoji chips inline without fallback', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReactionDisplay(
              reactions: [
                MessageReaction(
                  id: 'r-custom',
                  messageId: 'msg-1',
                  emoji: '😀',
                  senderPeerId: 'sender-1',
                  timestamp: '2026-02-27T10:00:00.000Z',
                  createdAt: '2026-02-27T10:00:01.000Z',
                ),
              ],
              ownPeerId: 'my-peer',
            ),
          ),
        ),
      );

      expect(find.text('😀'), findsOneWidget);
    });
  });
}
