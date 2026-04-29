import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/full_emoji_picker.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  group('FullEmojiPicker', () {
    testWidgets('renders grid of emojis', (tester) async {
      // Build a widget that shows the picker
      late BuildContext savedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              savedContext = context;
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => showFullEmojiPicker(context),
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Grid should be visible
      expect(find.byType(GridView), findsOneWidget);
      // Should see some emojis from the first category (Smileys)
      expect(find.text('😀'), findsOneWidget);
    });

    testWidgets('fires onSelected on tap', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await showFullEmojiPicker(context);
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap the first emoji
      await tester.tap(find.text('😀'));
      await tester.pumpAndSettle();

      expect(result, '😀');
    });

    testWidgets('category tabs render and switch', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => showFullEmojiPicker(context),
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify category tabs exist
      expect(find.text('Smileys'), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      expect(find.text('Animals'), findsOneWidget);

      // Switch to Animals category
      await tester.tap(find.text('Animals'));
      await tester.pumpAndSettle();

      // Should see animal emojis
      expect(find.text('🐶'), findsOneWidget);
    });

    testWidgets('category labels stay readable on light background sheets', (
      tester,
    ) async {
      const colors = BackgroundReadableColors.representativeLight;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[colors]),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => showFullEmojiPicker(context),
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final smileys = tester.widget<Text>(find.text('Smileys'));
      final people = tester.widget<Text>(find.text('People'));

      expectTextContrast(smileys.style!.color!, colors.surfaceBase);
      expectTextContrast(people.style!.color!, colors.surfaceBase);
    });
  });
}
