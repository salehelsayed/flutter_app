import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/empty_conversation_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget() {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: EmptyConversationState(
          contactPeerId: '12D3KooWTestPeerId1234567890',
          connectionDate: 'February 9, 2026',
        ),
      ),
    );
  }

  group('EmptyConversationState', () {
    testWidgets('displays "Connected!" label', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Connected!'), findsOneWidget);
    });

    testWidgets('displays connection date', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('February 9, 2026'), findsOneWidget);
    });

    testWidgets('displays writing prompt', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(
        find.text('Write the first letter\nto start your conversation'),
        findsOneWidget,
      );
    });

    testWidgets('renders large avatar (80px)', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final avatar80 = sizedBoxes.where(
        (sb) => sb.width == 80 && sb.height == 80,
      );
      expect(avatar80, isNotEmpty);
    });

    testWidgets('"Connected!" text is green', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final textWidget = tester.widget<Text>(find.text('Connected!'));
      expect(textWidget.style?.color, const Color(0xFF1DB954));
    });

    testWidgets('contains breathing glow container', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      // The glow is wrapped in a 160x160 SizedBox
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final glow160 = sizedBoxes.where(
        (sb) => sb.width == 160 && sb.height == 160,
      );
      expect(glow160, isNotEmpty);
    });
  });
}
