import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/confirmation_dialog.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  group('showConfirmationDialog', () {
    testWidgets('renders title and description', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showConfirmationDialog(
                  context: context,
                  title: 'Block Alice?',
                  description: 'They won\'t be able to send you messages.',
                  confirmLabel: 'Block',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Block Alice?'), findsOneWidget);
      expect(
        find.text('They won\'t be able to send you messages.'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);
    });

    testWidgets('Cancel returns false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showConfirmationDialog(
                  context: context,
                  title: 'Block Alice?',
                  description: 'Description.',
                  confirmLabel: 'Block',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('Confirm returns true', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showConfirmationDialog(
                  context: context,
                  title: 'Delete chat?',
                  description: 'Description.',
                  confirmLabel: 'Delete',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('danger action label remains readable on the red gradient', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showConfirmationDialog(
                  context: context,
                  title: 'Delete chat?',
                  description: 'Description.',
                  confirmLabel: 'Delete',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final confirmText = tester.widget<Text>(find.text('Delete'));
      expectTextContrast(confirmText.style!.color!, const Color(0xFFB91C1C));
      expectTextContrast(confirmText.style!.color!, const Color(0xFF991B1B));
    });
  });
}
