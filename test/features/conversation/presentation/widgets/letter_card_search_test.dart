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
