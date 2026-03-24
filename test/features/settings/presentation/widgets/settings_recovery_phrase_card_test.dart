import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_recovery_phrase_card.dart';

void main() {
  final testWords = [
    'abandon', 'ability', 'able', 'about', 'above', 'absent',
    'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
  ];

  Widget wrap(Widget child) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  testWidgets('shows RECOVERY PHRASE label', (tester) async {
    await tester.pumpWidget(wrap(
      SettingsRecoveryPhraseCard(words: testWords),
    ));

    expect(find.text('RECOVERY PHRASE'), findsOneWidget);
  });

  testWidgets('shows red warning text', (tester) async {
    await tester.pumpWidget(wrap(
      SettingsRecoveryPhraseCard(words: testWords),
    ));

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
    await tester.pumpWidget(wrap(
      SettingsRecoveryPhraseCard(words: testWords, isRevealed: false),
    ));

    expect(find.text('Tap to reveal'), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets('tapping overlay calls onToggleReveal', (tester) async {
    var toggled = false;
    await tester.pumpWidget(wrap(
      SettingsRecoveryPhraseCard(
        words: testWords,
        isRevealed: false,
        onToggleReveal: () => toggled = true,
      ),
    ));

    await tester.tap(find.text('Tap to reveal'));
    expect(toggled, isTrue);
  });

  testWidgets('revealed state: shows 12 numbered words', (tester) async {
    await tester.pumpWidget(wrap(
      SettingsRecoveryPhraseCard(words: testWords, isRevealed: true),
    ));

    // No overlay
    expect(find.text('Tap to reveal'), findsNothing);

    // Check all 12 words and indices
    for (var i = 0; i < testWords.length; i++) {
      expect(find.text('${i + 1}'), findsOneWidget);
      expect(find.text(testWords[i]), findsOneWidget);
    }
  });

  testWidgets('revealed state: shows Copy and Hide buttons', (tester) async {
    await tester.pumpWidget(wrap(
      SettingsRecoveryPhraseCard(words: testWords, isRevealed: true),
    ));

    expect(find.text('Copy to clipboard'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });

  testWidgets('tapping Copy calls onCopy', (tester) async {
    var copied = false;
    await tester.pumpWidget(wrap(
      SettingsRecoveryPhraseCard(
        words: testWords,
        isRevealed: true,
        onCopy: () => copied = true,
      ),
    ));

    await tester.tap(find.text('Copy to clipboard'));
    expect(copied, isTrue);
  });

  testWidgets('tapping Hide calls onHide', (tester) async {
    var hidden = false;
    await tester.pumpWidget(wrap(
      SettingsRecoveryPhraseCard(
        words: testWords,
        isRevealed: true,
        onHide: () => hidden = true,
      ),
    ));

    await tester.tap(find.text('Hide'));
    expect(hidden, isTrue);
  });

  testWidgets('Copy button shows "Copied!" when isCopied=true', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(
      SettingsRecoveryPhraseCard(
        words: testWords,
        isRevealed: true,
        isCopied: true,
      ),
    ));

    expect(find.text('Copied!'), findsOneWidget);
    expect(find.text('Copy to clipboard'), findsNothing);
  });
}
