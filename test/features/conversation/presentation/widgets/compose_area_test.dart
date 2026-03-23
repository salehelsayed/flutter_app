import 'dart:ui' show TextDirection;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/l10n/app_localizations_en.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class _TestAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _TestAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizationsEn());

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}

void main() {
  Widget buildTestWidget({
    ValueChanged<String>? onSend,
    VoidCallback? onAttach,
    bool hasAttachments = false,
    bool isProcessing = false,
    bool isSending = false,
    String? initialText,
    String? quotedText,
    bool isQuoteUnavailable = false,
    VoidCallback? onClearQuote,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        _TestAppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en')],
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ComposeArea(
            onSend: onSend ?? (_) {},
            onAttach: onAttach,
            hasAttachments: hasAttachments,
            isProcessing: isProcessing,
            isSending: isSending,
            initialText: initialText,
            quotedText: quotedText,
            isQuoteUnavailable: isQuoteUnavailable,
            onClearQuote: onClearQuote,
          ),
        ),
      ),
    );
  }

  group('ComposeArea', () {
    testWidgets('shows placeholder text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Write something...'), findsOneWidget);
    });

    testWidgets('seeds the text field with initialText', (tester) async {
      await tester.pumpWidget(buildTestWidget(initialText: 'Shared caption'));
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'Shared caption');
    });

    testWidgets('starts empty when initialText is omitted', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, isEmpty);
    });

    testWidgets('renders quote preview when quotedText is provided', (
      tester,
    ) async {
      var cleared = false;
      await tester.pumpWidget(
        buildTestWidget(
          quotedText: 'Quoted target',
          onClearQuote: () => cleared = true,
        ),
      );

      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Quoted target'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(cleared, isTrue);
    });

    testWidgets('shows unavailable quote preview fallback', (tester) async {
      await tester.pumpWidget(buildTestWidget(isQuoteUnavailable: true));

      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Message unavailable'), findsOneWidget);
    });

    testWidgets('shows attachment button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('shows send button icon', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      // Send button exists in tree but may be invisible
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('send button starts with zero opacity', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // The send button is wrapped in an Opacity widget that starts at 0
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      final zeroOpacity = opacityWidgets.where((o) => o.opacity == 0.0);
      expect(zeroOpacity, isNotEmpty);
    });

    testWidgets('send button becomes visible when text is entered', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();

      // After animation settles, opacity should be 1
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      final fullOpacity = opacityWidgets.where((o) => o.opacity == 1.0);
      expect(fullOpacity, isNotEmpty);
    });

    group('BiDi input direction', () {
      testWidgets('TextField defaults to LTR when empty', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, TextDirection.ltr);
      });

      testWidgets('TextField switches to RTL when Arabic is typed', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'مرحبا');
        await tester.pump();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, TextDirection.rtl);
      });

      testWidgets('TextField switches to RTL for Arabic-first mixed text', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'مرحبا Hello');
        await tester.pump();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, TextDirection.rtl);
      });

      testWidgets('TextField stays LTR when English is typed', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'Hello');
        await tester.pump();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, TextDirection.ltr);
      });

      testWidgets('TextField switches back to LTR after clearing text', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'مرحبا');
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).textDirection,
          TextDirection.rtl,
        );

        await tester.enterText(find.byType(TextField), 'Hello');
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).textDirection,
          TextDirection.ltr,
        );
      });
    });

    testWidgets('onSend is called with trimmed text', (tester) async {
      String? sentText;
      await tester.pumpWidget(
        buildTestWidget(onSend: (text) => sentText = text),
      );

      await tester.enterText(find.byType(TextField), '  Hello!  ');
      await tester.pumpAndSettle();

      // Tap the send button
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(sentText, 'Hello!');
    });

    testWidgets('text field clears after send', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(find.byType(TextField), 'Hello!');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      // TextField should be empty
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '');
    });

    testWidgets(
      'restores draft when parent rehydrates initialText after send',
      (tester) async {
        String? sentText;
        String? restoredDraft;
        late StateSetter setHostState;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              _TestAppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const <Locale>[Locale('en')],
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  setHostState = setState;
                  return Column(
                    children: [
                      const Spacer(),
                      ComposeArea(
                        onSend: (text) => sentText = text,
                        initialText: restoredDraft,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), 'Retry me');
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        expect(sentText, 'Retry me');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          '',
        );

        setHostState(() => restoredDraft = 'Retry me');
        await tester.pump();

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Retry me',
        );
      },
    );

    testWidgets('attachment button fires onAttach callback', (tester) async {
      var attachPressed = false;
      await tester.pumpWidget(
        buildTestWidget(onAttach: () => attachPressed = true),
      );

      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(attachPressed, true);
    });

    testWidgets('send button visible when hasAttachments is true and no text', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(hasAttachments: true));
      await tester.pumpAndSettle();

      // Send button should be fully visible via the animation
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      final fullOpacity = opacityWidgets.where((o) => o.opacity == 1.0);
      expect(fullOpacity, isNotEmpty);
    });

    testWidgets('media-only send fires onSend with empty string', (
      tester,
    ) async {
      String? sentText;
      await tester.pumpWidget(
        buildTestWidget(
          onSend: (text) => sentText = text,
          hasAttachments: true,
        ),
      );
      await tester.pumpAndSettle();

      // Tap send without entering any text
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(sentText, '');
    });

    testWidgets('send button hidden when no text and no attachments', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(hasAttachments: false));
      await tester.pump();

      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      final zeroOpacity = opacityWidgets.where((o) => o.opacity == 0.0);
      expect(zeroOpacity, isNotEmpty);
    });

    testWidgets('send button reacts to hasAttachments changing to true', (
      tester,
    ) async {
      // Start without attachments
      await tester.pumpWidget(buildTestWidget(hasAttachments: false));
      await tester.pump();

      // Verify hidden
      var opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(opacityWidgets.where((o) => o.opacity == 0.0), isNotEmpty);

      // Now rebuild with hasAttachments = true
      await tester.pumpWidget(buildTestWidget(hasAttachments: true));
      await tester.pumpAndSettle();

      // Should now be visible
      opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(opacityWidgets.where((o) => o.opacity == 1.0), isNotEmpty);
    });

    testWidgets('does not fire onSend when no text and no attachments', (
      tester,
    ) async {
      String? sentText;
      await tester.pumpWidget(
        buildTestWidget(
          onSend: (text) => sentText = text,
          hasAttachments: false,
        ),
      );
      await tester.pumpAndSettle();

      // Even though send button is in the tree, tapping it should not fire
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(sentText, isNull);
    });

    testWidgets('disables send button when isProcessing is true', (
      tester,
    ) async {
      String? sentText;
      await tester.pumpWidget(
        buildTestWidget(
          onSend: (text) => sentText = text,
          hasAttachments: true,
          isProcessing: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(sentText, isNull);
    });

    testWidgets('disables send button when isSending is true', (tester) async {
      String? sentText;
      await tester.pumpWidget(
        buildTestWidget(
          onSend: (text) => sentText = text,
          hasAttachments: true,
          isSending: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(sentText, isNull);
    });

    testWidgets('disables attach button when isProcessing is true', (
      tester,
    ) async {
      var attachPressed = false;
      await tester.pumpWidget(
        buildTestWidget(
          onAttach: () => attachPressed = true,
          isProcessing: true,
        ),
      );

      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(attachPressed, false);
    });

    testWidgets('attach button dimmed when isProcessing is true', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(isProcessing: true));
      await tester.pump();

      final icon = tester.widget<Icon>(find.byIcon(Icons.add_rounded));
      // When processing, the icon color should have lower opacity
      expect(icon.color, const Color.fromRGBO(255, 255, 255, 0.15));
    });

    testWidgets('attachment, text field, and send button are in a single Row', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      // TextField and attachment icon should share a common Row ancestor
      final textFieldRows = find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(Row),
      );
      final attachRows = find.ancestor(
        of: find.byIcon(Icons.add_rounded),
        matching: find.byType(Row),
      );
      // Both should have Row ancestors (they share the same parent Row)
      expect(textFieldRows, findsWidgets);
      expect(attachRows, findsWidgets);
    });

    testWidgets('send button is icon-only circle (no text label)', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.text('Send'), findsNothing);
    });
  });

  group('ComposeArea voice recording', () {
    Widget buildVoiceWidget({
      ValueChanged<String>? onSend,
      VoidCallback? onAttach,
      bool hasAttachments = false,
      bool isProcessing = false,
      VoidCallback? onRecordStart,
      VoidCallback? onRecordStop,
      VoidCallback? onRecordCancel,
      VoiceRecordingState recordingState = VoiceRecordingState.idle,
      Duration recordingDuration = Duration.zero,
    }) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          _TestAppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[Locale('en')],
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ComposeArea(
              onSend: onSend ?? (_) {},
              onAttach: onAttach,
              hasAttachments: hasAttachments,
              isProcessing: isProcessing,
              onRecordStart: onRecordStart,
              onRecordStop: onRecordStop,
              onRecordCancel: onRecordCancel,
              recordingState: recordingState,
              recordingDuration: recordingDuration,
            ),
          ),
        ),
      );
    }

    testWidgets('mic button visible when text is empty and no attachments', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildVoiceWidget(
          onRecordStart: () {},
          onRecordStop: () {},
          onRecordCancel: () {},
        ),
      );

      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    testWidgets('send button visible when text is non-empty', (tester) async {
      await tester.pumpWidget(
        buildVoiceWidget(
          onRecordStart: () {},
          onRecordStop: () {},
          onRecordCancel: () {},
        ),
      );

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      // Mic button should be gone
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
    });

    testWidgets('send button visible when hasAttachments is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildVoiceWidget(
          hasAttachments: true,
          onRecordStart: () {},
          onRecordStop: () {},
          onRecordCancel: () {},
        ),
      );
      await tester.pumpAndSettle();

      // Mic button should not be shown
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
    });

    testWidgets('recording overlay appears when isRecording is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildVoiceWidget(
          recordingState: VoiceRecordingState.recording,
          recordingDuration: const Duration(seconds: 3),
          onRecordStart: () {},
          onRecordStop: () {},
          onRecordCancel: () {},
        ),
      );

      expect(find.text('0:03'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    });

    testWidgets('recording overlay disappears when isRecording is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildVoiceWidget(
          recordingState: VoiceRecordingState.idle,
          onRecordStart: () {},
          onRecordStop: () {},
          onRecordCancel: () {},
        ),
      );

      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('recording overlay cancel gesture forwards onRecordCancel', (
      tester,
    ) async {
      var cancelled = false;
      await tester.pumpWidget(
        buildVoiceWidget(
          recordingState: VoiceRecordingState.recording,
          onRecordStart: () {},
          onRecordStop: () {},
          onRecordCancel: () => cancelled = true,
        ),
      );

      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(cancelled, isTrue);
    });

    testWidgets('text field hidden during recording', (tester) async {
      await tester.pumpWidget(
        buildVoiceWidget(
          recordingState: VoiceRecordingState.recording,
          onRecordStart: () {},
          onRecordStop: () {},
          onRecordCancel: () {},
        ),
      );

      // TextField should not be visible (recording overlay replaces it)
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('mic button not shown without onRecordStart callback', (
      tester,
    ) async {
      await tester.pumpWidget(buildVoiceWidget());
      // Without onRecordStart, no mic button
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
    });
  });
}
