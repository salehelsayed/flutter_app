import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  Widget wrap(BackgroundReadableColors colors, {String initialText = 'hello'}) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: [colors]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ComposeArea(
            initialText: initialText,
            onSend: (_) {},
            onRecordStart: () {},
            onRecordStop: () {},
            onRecordCancel: () {},
          ),
        ),
      ),
    );
  }

  BoxDecoration composerDecoration(WidgetTester tester) {
    return tester
        .widgetList<Container>(find.byType(Container))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.gradient is LinearGradient);
  }

  testWidgets('bar is two-stop Signal porcelain and send is violet on light', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;

    await tester.pumpWidget(wrap(colors));
    await tester.pump();

    final gradient = composerDecoration(tester).gradient! as LinearGradient;
    expect(gradient.colors, [Colors.transparent, colors.composerBarColor]);
    expect(gradient.stops, [0.0, 0.2]);

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.style!.color, colors.textPrimary);
    final inputDecoration = textField.decoration!;
    expect(inputDecoration.hintStyle!.color, colors.composerHint);
    // Explicit false (not null): null lets the light theme's filled
    // InputDecorationTheme paint a square fill rect over the rounded pill.
    expect(inputDecoration.filled, isFalse);
    expectTextContrast(colors.composerHint, const Color(0xFFEDEEF3));

    final sendContainer = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Icons.arrow_upward_rounded),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).color == colors.sendBg,
            ),
          )
          .first,
    );
    final sendDecoration = sendContainer.decoration as BoxDecoration;
    expect(sendDecoration.color, colors.sendBg);
    final sendIcon = tester.widget<Icon>(
      find.byIcon(Icons.arrow_upward_rounded),
    );
    expect(sendIcon.color, colors.sendIcon);

    final effectiveSendFill = Color.alphaBlend(
      colors.sendBg,
      colors.composerInputFill,
    );
    expectComponentContrast(colors.sendIcon, effectiveSendFill);
  });

  testWidgets('dark bar gradient remains the transcribed two-stop literal', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(BackgroundReadableColors.dark));
    await tester.pump();

    final gradient = composerDecoration(tester).gradient! as LinearGradient;
    expect(gradient.colors, const [
      Colors.transparent,
      Color.fromRGBO(10, 10, 15, 0.95),
    ]);
    expect(gradient.stops, [0.0, 0.2]);
  });

  for (final focused in [false, true]) {
    testWidgets('dark chat hint meets contrast with focus=$focused', (
      tester,
    ) async {
      const deadline = Duration(seconds: 3);
      await tester
          .pumpWidget(wrap(BackgroundReadableColors.dark, initialText: ''))
          .timeout(deadline);
      final field = find.byType(TextField);
      if (focused) {
        await tester.tap(field).timeout(deadline);
        await tester.pump().timeout(deadline);
      }

      final input = tester.widget<TextField>(field);
      expect(input.focusNode!.hasFocus, focused);
      final hint = tester.widget<Text>(find.text(input.decoration!.hintText!));
      final hintColor = hint.style!.color!;
      expect(hintColor.withValues(alpha: 1), Colors.white);
      expect(hintColor.a, closeTo(0.55, 0.002));
      expectTextContrast(hintColor, const Color(0xFF17171C));
    });
  }
}
