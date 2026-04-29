import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget({
    VoidCallback? onBack,
    VoidCallback? onOverflow,
    BackgroundReadableColors readableColors = BackgroundReadableColors.dark,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Theme(
        data: ThemeData(extensions: <ThemeExtension<dynamic>>[readableColors]),
        child: Scaffold(
          body: ConversationHeader(
            contactPeerId: '12D3KooWTestPeerId1234567890',
            contactUsername: 'Alice',
            connectionDate: 'February 9, 2026',
            onBack: onBack ?? () {},
            onOverflow: onOverflow,
          ),
        ),
      ),
    );
  }

  group('ConversationHeader', () {
    testWidgets('displays contact username', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('displays connection date', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Connected February 9, 2026'), findsOneWidget);
    });

    testWidgets('shows back chevron icon', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    });

    testWidgets('shows overflow menu icon', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('back button fires onBack callback', (tester) async {
      var backPressed = false;
      await tester.pumpWidget(
        buildTestWidget(onBack: () => backPressed = true),
      );

      await tester.tap(find.byIcon(Icons.chevron_left));
      expect(backPressed, true);
    });

    testWidgets('overflow button fires onOverflow callback', (tester) async {
      var overflowPressed = false;
      await tester.pumpWidget(
        buildTestWidget(onOverflow: () => overflowPressed = true),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      expect(overflowPressed, true);
    });

    testWidgets('renders RingAvatar with 36px size', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
      expect(avatar.size, 36);
    });

    testWidgets('uses representative light readable roles', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          readableColors: BackgroundReadableColors.representativeLight,
        ),
      );

      final name = tester.widget<Text>(find.text('Alice'));
      expect(
        name.style?.color,
        BackgroundReadableColors.representativeLight.textPrimary,
      );

      final backIcon = tester.widget<Icon>(find.byIcon(Icons.chevron_left));
      expect(
        backIcon.color,
        BackgroundReadableColors.representativeLight.iconSecondary,
      );

      final headerContainer = tester.widget<Container>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).gradient is LinearGradient,
        ),
      );
      final decoration = headerContainer.decoration as BoxDecoration;
      final gradient = decoration.gradient as LinearGradient;
      expect(
        gradient.colors.first,
        BackgroundReadableColors.representativeLight.glassSurface,
      );
    });
  });
}
