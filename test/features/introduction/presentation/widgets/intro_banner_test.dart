import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_banner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  group('IntroBanner', () {
    Widget wrapBanner({
      required String contactUsername,
      required VoidCallback onMakeIntroductions,
      required VoidCallback onMaybeLater,
      BackgroundReadableColors? readableColors,
    }) {
      final banner = IntroBanner(
        contactUsername: contactUsername,
        onMakeIntroductions: onMakeIntroductions,
        onMaybeLater: onMaybeLater,
      );

      return MaterialApp(
        home: Scaffold(
          body: readableColors == null
              ? banner
              : Theme(
                  data: ThemeData(extensions: [readableColors]),
                  child: banner,
                ),
        ),
      );
    }

    testWidgets('renders banner with contact username', (tester) async {
      await tester.pumpWidget(
        wrapBanner(
          contactUsername: 'Alice',
          onMakeIntroductions: () {},
          onMaybeLater: () {},
        ),
      );

      expect(find.text('Help Alice meet your circle'), findsOneWidget);
      expect(
        find.text('Introduce them to friends who might click'),
        findsOneWidget,
      );
      expect(find.text('Make introductions'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);
    });

    testWidgets('"Make introductions" button triggers callback', (
      tester,
    ) async {
      var tapped = false;

      await tester.pumpWidget(
        wrapBanner(
          contactUsername: 'Bob',
          onMakeIntroductions: () => tapped = true,
          onMaybeLater: () {},
        ),
      );

      await tester.tap(find.text('Make introductions'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('"Maybe later" triggers callback', (tester) async {
      var dismissed = false;

      await tester.pumpWidget(
        wrapBanner(
          contactUsername: 'Charlie',
          onMakeIntroductions: () {},
          onMaybeLater: () => dismissed = true,
        ),
      );

      await tester.tap(find.text('Maybe later'));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });

    testWidgets('uses readable text colors on the daylight theme', (
      tester,
    ) async {
      const colors = BackgroundReadableColors.representativeLight;
      const lightBannerSurface = Color(0xFFE5F4EA);

      await tester.pumpWidget(
        wrapBanner(
          contactUsername: 'Alice',
          onMakeIntroductions: () {},
          onMaybeLater: () {},
          readableColors: colors,
        ),
      );

      final title = tester.widget<Text>(
        find.text('Help Alice meet your circle'),
      );
      final subtitle = tester.widget<Text>(
        find.text('Introduce them to friends who might click'),
      );
      final maybeLater = tester.widget<Text>(find.text('Maybe later'));

      expect(title.style?.color, colors.textPrimary);
      expect(subtitle.style?.color, colors.textMuted);
      expect(maybeLater.style?.color, colors.textMuted);
      expectTextContrast(title.style!.color!, lightBannerSurface);
      expectTextContrast(subtitle.style!.color!, lightBannerSurface);
      expectTextContrast(maybeLater.style!.color!, lightBannerSurface);
    });
  });
}
