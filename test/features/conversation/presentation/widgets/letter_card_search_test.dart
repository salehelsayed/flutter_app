import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const colors = BackgroundReadableColors.dark;

  Future<Color?> markOf(WidgetTester tester, {required bool current}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[colors]),
        home: Scaffold(
          body: LetterCard(
            senderPeerId: '12D3KooWTestPeerId1234567890',
            senderName: 'Lina',
            text: 'back to Dahab?',
            time: '10:05',
            isIncoming: true,
            bubbleLayout: true,
            searchQuery: 'dahab',
            isCurrentSearchHit: current,
          ),
        ),
      ),
    );
    Color? found;
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'Dahab') {
          found = span.style?.backgroundColor;
        }
        return true;
      });
    }
    return found;
  }

  for (final (language, width, text) in [
    ('en', 320.0, 'See you later.'),
    ('de', 360.0, 'Bis später.'),
    ('ar', 390.0, 'أراك لاحقًا.'),
  ]) {
    testWidgets('AX5 layout fits chat bubble metadata in $language', (
      tester,
    ) async {
      const deadline = Duration(seconds: 3);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.reset);
      await tester
          .pumpWidget(
            MaterialApp(
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(3.1)),
                child: child!,
              ),
              home: Scaffold(
                body: LetterCard(
                  senderPeerId: 'peer',
                  senderName: 'Lina',
                  text: text,
                  time: '10:05 PM',
                  isIncoming: true,
                  isEdited: true,
                  bubbleLayout: true,
                  showAvatar: false,
                  showSenderName: false,
                  transportStatusGlyph: true,
                  transport: 'inbox',
                ),
              ),
            ),
          )
          .timeout(deadline);

      expect(tester.takeException(), isNull);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(LetterCard)),
      )!;
      for (final label in ['10:05 PM', l10n.conversation_edited_indicator]) {
        final bounds = tester.getRect(find.text(label));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(width));
      }
    });
  }

  testWidgets('the current match is solid accent, other matches a soft tint', (
    tester,
  ) async {
    expect(await markOf(tester, current: true), colors.accent);
    final soft = await markOf(tester, current: false);
    expect(soft, isNotNull);
    expect(soft, isNot(colors.accent));
    expect(soft!.a, lessThan(colors.accent.a));
  });
}
