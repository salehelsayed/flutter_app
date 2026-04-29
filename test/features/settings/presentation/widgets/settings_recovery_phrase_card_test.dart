import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_recovery_phrase_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testWords = [
    'abandon',
    'ability',
    'able',
    'about',
    'above',
    'absent',
    'absorb',
    'abstract',
    'absurd',
    'abuse',
    'access',
    'accident',
  ];

  Widget wrap(
    Widget child, {
    BackgroundReadableColors readableColors = BackgroundReadableColors.dark,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[readableColors]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  BoxDecoration cardDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.padding == const EdgeInsets.all(16) &&
            widget.decoration is BoxDecoration,
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  BoxDecoration wordCellDecoration(WidgetTester tester, String word) {
    final container = tester.widget<Container>(
      find.ancestor(
        of: find.text(word),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.padding ==
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8) &&
              widget.decoration is BoxDecoration,
        ),
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  BoxDecoration actionDecoration(WidgetTester tester, String text) {
    final container = tester.widget<Container>(
      find.ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.padding ==
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10) &&
              widget.decoration is BoxDecoration,
        ),
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('shows RECOVERY PHRASE label', (tester) async {
    await tester.pumpWidget(wrap(SettingsRecoveryPhraseCard(words: testWords)));

    expect(find.text('RECOVERY PHRASE'), findsOneWidget);
  });

  testWidgets('shows warning text', (tester) async {
    await tester.pumpWidget(wrap(SettingsRecoveryPhraseCard(words: testWords)));

    expect(
      find.text(
        'Never share this phrase with anyone. It grants full access to your account.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('hidden state: shows "Tap to reveal" overlay with eye icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(SettingsRecoveryPhraseCard(words: testWords, isRevealed: false)),
    );

    expect(find.text('Tap to reveal'), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets('uses representative light roles in hidden state', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;
    await tester.pumpWidget(
      wrap(
        SettingsRecoveryPhraseCard(words: testWords, isRevealed: false),
        readableColors: colors,
      ),
    );

    final card = cardDecoration(tester);
    expect(card.color, colors.glassSurface);
    expect((card.border! as Border).top.color, colors.glassBorder);

    final title = tester.widget<Text>(find.text('RECOVERY PHRASE'));
    expect(title.style?.color, colors.textMuted);

    final warning = tester.widget<Text>(
      find.text(
        'Never share this phrase with anyone. It grants full access to your account.',
      ),
    );
    expect(warning.style?.color, const Color(0xFFB91C1C));

    final overlay = tester.widget<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color == colors.overlayScrim,
      ),
    );
    final overlayDecoration = overlay.decoration! as BoxDecoration;
    expect(overlayDecoration.color, colors.overlayScrim);

    final revealIcon = tester.widget<Icon>(find.byIcon(Icons.visibility));
    expect(revealIcon.color, Colors.white);

    final revealText = tester.widget<Text>(find.text('Tap to reveal'));
    expect(revealText.style?.color, Colors.white);
  });

  testWidgets('tapping overlay calls onToggleReveal', (tester) async {
    var toggled = false;
    await tester.pumpWidget(
      wrap(
        SettingsRecoveryPhraseCard(
          words: testWords,
          isRevealed: false,
          onToggleReveal: () => toggled = true,
        ),
      ),
    );

    await tester.tap(find.text('Tap to reveal'));
    expect(toggled, isTrue);
  });

  testWidgets('revealed state: shows 12 numbered words', (tester) async {
    await tester.pumpWidget(
      wrap(SettingsRecoveryPhraseCard(words: testWords, isRevealed: true)),
    );

    expect(find.text('Tap to reveal'), findsNothing);

    for (var i = 0; i < testWords.length; i++) {
      expect(find.text('${i + 1}'), findsOneWidget);
      expect(find.text(testWords[i]), findsOneWidget);
    }
  });

  testWidgets('uses dark readable roles in revealed state', (tester) async {
    const colors = BackgroundReadableColors.dark;
    await tester.pumpWidget(
      wrap(
        SettingsRecoveryPhraseCard(words: testWords, isRevealed: true),
        readableColors: colors,
      ),
    );

    final wordCell = wordCellDecoration(tester, 'abandon');
    expect(wordCell.color, colors.surfaceSubtle);
    expect((wordCell.border! as Border).top.color, colors.border);

    final number = tester.widget<Text>(find.text('1'));
    expect(number.style?.color, colors.textMuted);

    final word = tester.widget<Text>(find.text('abandon'));
    expect(word.style?.color, colors.textPrimary);

    final copyDecoration = actionDecoration(tester, 'Copy to clipboard');
    expect(copyDecoration.color, colors.surfaceSubtle);
    expect((copyDecoration.border! as Border).top.color, colors.glassBorder);

    final copyIcon = tester.widget<Icon>(find.byIcon(Icons.copy));
    expect(copyIcon.color, colors.iconSecondary);

    final copyText = tester.widget<Text>(find.text('Copy to clipboard'));
    expect(copyText.style?.color, colors.textSecondary);

    final hideIcon = tester.widget<Icon>(find.byIcon(Icons.visibility_off));
    expect(hideIcon.color, colors.iconSecondary);
  });

  testWidgets('revealed state: shows Copy and Hide buttons', (tester) async {
    await tester.pumpWidget(
      wrap(SettingsRecoveryPhraseCard(words: testWords, isRevealed: true)),
    );

    expect(find.text('Copy to clipboard'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });

  testWidgets('tapping Copy calls onCopy', (tester) async {
    var copied = false;
    await tester.pumpWidget(
      wrap(
        SettingsRecoveryPhraseCard(
          words: testWords,
          isRevealed: true,
          onCopy: () => copied = true,
        ),
      ),
    );

    await tester.tap(find.text('Copy to clipboard'));
    expect(copied, isTrue);
  });

  testWidgets('tapping Hide calls onHide', (tester) async {
    var hidden = false;
    await tester.pumpWidget(
      wrap(
        SettingsRecoveryPhraseCard(
          words: testWords,
          isRevealed: true,
          onHide: () => hidden = true,
        ),
      ),
    );

    await tester.tap(find.text('Hide'));
    expect(hidden, isTrue);
  });

  testWidgets('Copy button shows "Copied!" when isCopied=true', (tester) async {
    await tester.pumpWidget(
      wrap(
        SettingsRecoveryPhraseCard(
          words: testWords,
          isRevealed: true,
          isCopied: true,
        ),
      ),
    );

    expect(find.text('Copied!'), findsOneWidget);
    expect(find.text('Copy to clipboard'), findsNothing);
  });

  testWidgets('uses darker copied accent on representative light', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;
    await tester.pumpWidget(
      wrap(
        SettingsRecoveryPhraseCard(
          words: testWords,
          isRevealed: true,
          isCopied: true,
        ),
        readableColors: colors,
      ),
    );

    final checkIcon = tester.widget<Icon>(find.byIcon(Icons.check));
    expect(checkIcon.color, const Color(0xFF0F766E));

    final copiedText = tester.widget<Text>(find.text('Copied!'));
    expect(copiedText.style?.color, colors.textSecondary);
  });
}
