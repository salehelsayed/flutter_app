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

  // The loaded Feed renders system cards on the warm mineral canvas.
  const canvas = Color(0xFFECE8E1);

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
        backgroundColor: canvas,
        body: Padding(
          padding: EdgeInsets.all(24),
          child: LetterCardSystem(letter: connection),
        ),
      ),
    );
  }

  testWidgets(
    'loaded Signal system card is distinct from warm canvas without a heavy '
    'outline',
    (tester) async {
      await tester.pumpWidget(mount());
      await tester.pump();

      // Connected label uses the warm meta color and is AA on the canvas.
      final label = tester.widget<Text>(find.text('Connected'));
      expect(label.style!.color, FeedTokens.light.textMeta.color);
      expect(label.style!.color, const Color(0xFF56515E));
      expectTextContrast(label.style!.color!, canvas);

      // The system bubble uses the updated warm success fill.
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

      expect(fill, const Color(0xFFDCE9E1));
      // The filled bubble is distinct from the warm canvas AND the raised card
      // surface — never transparent or same-as-canvas.
      expect(fill, isNot(canvas));
      expect(fill, isNot(FeedTokens.light.surfaceRaised));

      // Readable warm message text on the fill.
      expect(bubbleText.style!.color, const Color(0xFF25222B));
      expectTextContrast(bubbleText.style!.color!, fill);
    },
  );
}
