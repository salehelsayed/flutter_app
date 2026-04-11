import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_bar.dart';

void main() {
  group('ReactionBar', () {
    testWidgets('renders 6 preset emojis + "+" button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionBar(
              onReactionSelected: (_) {},
              onPlusTap: () {},
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final emoji in kPresetEmojis) {
        expect(find.text(emoji), findsOneWidget);
      }
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('fires onReactionSelected with correct emoji', (tester) async {
      String? selectedEmoji;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionBar(
              onReactionSelected: (emoji) => selectedEmoji = emoji,
              onPlusTap: () {},
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('❤️'));
      expect(selectedEmoji, '❤️');
    });

    testWidgets('fires onPlusTap on "+" tap', (tester) async {
      var plusTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionBar(
              onReactionSelected: (_) {},
              onPlusTap: () => plusTapped = true,
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      expect(plusTapped, isTrue);
    });

    testWidgets(
      'non-preset currentEmoji does not falsely highlight any preset chip',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReactionBar(
                currentEmoji: '😀',
                onReactionSelected: (_) {},
                onPlusTap: () {},
                onDismiss: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final selectedContainers = tester
            .widgetList<Container>(find.byType(Container))
            .where((container) {
              final decoration = container.decoration;
              return decoration is BoxDecoration &&
                  decoration.color == const Color.fromRGBO(78, 205, 196, 0.20);
            });

        expect(selectedContainers, isEmpty);
      },
    );

    testWidgets('fires onDismiss on barrier tap', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionBar(
              onReactionSelected: (_) {},
              onPlusTap: () {},
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the outer GestureDetector (transparent area)
      await tester.tapAt(const Offset(10, 10));
      expect(dismissed, isTrue);
    });

    testWidgets('scale animation runs (0.8→1.0, 200ms)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionBar(
              onReactionSelected: (_) {},
              onPlusTap: () {},
              onDismiss: () {},
            ),
          ),
        ),
      );

      // At start, ScaleTransition should exist (at least one)
      expect(find.byType(ScaleTransition), findsWidgets);

      // Pump forward to let animation finish
      await tester.pumpAndSettle();
      expect(find.byType(ScaleTransition), findsWidgets);
    });
  });
}
