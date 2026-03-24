import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compact_origin_marker.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget() {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CompactOriginMarker(
          contactPeerId: '12D3KooWTestPeerId1234567890',
          connectionDate: 'February 9, 2026',
        ),
      ),
    );
  }

  group('CompactOriginMarker', () {
    testWidgets('displays "Connected!" text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Connected!'), findsOneWidget);
    });

    testWidgets('displays connection date', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('February 9, 2026'), findsOneWidget);
    });

    testWidgets('renders 48px avatar', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final avatar48 = sizedBoxes.where(
        (sb) => sb.width == 48 && sb.height == 48,
      );
      expect(avatar48, isNotEmpty);
    });

    testWidgets('"Connected!" text is 15px green', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final textWidget = tester.widget<Text>(find.text('Connected!'));
      expect(textWidget.style?.fontSize, 15);
      expect(textWidget.style?.color, const Color(0xFF1DB954));
    });

    testWidgets('date text is 12px', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final textWidget = tester.widget<Text>(find.text('February 9, 2026'));
      expect(textWidget.style?.fontSize, 12);
    });
  });
}
