import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/features/feed/domain/models/feed_letter.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_system.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  const connection = SystemLetter(
    contactPeerId: 'peer-signal',
    displayName: 'Signal Friend',
  );

  Widget mount() {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        extensions: const [
          BackgroundReadableColors.representativeLight,
          FeedTokens.light,
        ],
      ),
      home: const Scaffold(
        backgroundColor: Color(0xFFEDEEF3),
        body: Padding(
          padding: EdgeInsets.all(24),
          child: LetterCardSystem(letter: connection),
        ),
      ),
    );
  }

  testWidgets('feed system pill and Connected label render legibly on Signal', (
    tester,
  ) async {
    await tester.pumpWidget(mount());
    await tester.pump();

    final label = tester.widget<Text>(find.text('Connected'));
    expect(label.style!.color, FeedTokens.light.textMeta.color);
    expectTextContrast(label.style!.color!, const Color(0xFFEDEEF3));

    final bubbleText = tester.widget<Text>(find.text('tap to say hi'));
    final bubbleContainer = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('tap to say hi'),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).color ==
                      FeedTokens.light.greenFill15,
            ),
          )
          .first,
    );
    final fill = (bubbleContainer.decoration as BoxDecoration).color!;

    expect(fill, const Color(0xFFDFF3E9));
    expect(bubbleText.style!.color, const Color(0xFF16181F));
    expectTextContrast(bubbleText.style!.color!, fill);
  });
}
