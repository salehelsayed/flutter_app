import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import '../../../translate_preview/fake_model_delivery_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/l10n/app_localizations_en.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/voice_record_button.dart';
import 'package:flutter_app/shared/widgets/media/recording_overlay.dart';
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
    bool shouldRequestFocus = false,
    VoidCallback? onRecordStart,
    VoidCallback? onRecordStop,
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
            shouldRequestFocus: shouldRequestFocus,
            onRecordStart: onRecordStart,
            onRecordStop: onRecordStop,
          ),
        ),
      ),
    );
  }

  testWidgets('A02 recording phases name the actual action once', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var starts = 0;
    var stops = 0;
    var sends = 0;
    var discards = 0;
    for (final entry in {
      VoiceRecordingState.idle: 'Record voice message',
      VoiceRecordingState.arming: 'Cancel recording start',
      VoiceRecordingState.recording: 'Stop and send voice message',
      VoiceRecordingState.stopping: 'Finishing voice message',
      VoiceRecordingState.reviewing: 'Send voice message',
    }.entries) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ComposeArea(
              onSend: (_) {},
              recordingState: entry.key,
              onRecordStart: () => starts++,
              onRecordStop: () => stops++,
              onRecordCancel: () {},
              onReviewSend: () => sends++,
              onReviewDiscard: () => discards++,
            ),
          ),
        ),
      );
      await tester.pump();
      final finder = find.bySemanticsLabel(entry.value);
      expect(finder, findsOneWidget);
      expect(find.text(entry.value), findsNothing);
      final node = tester.getSemantics(finder);
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      final actionable = entry.key != VoiceRecordingState.stopping;
      expect(
        node.getSemanticsData().flagsCollection.isEnabled == ui.Tristate.isTrue,
        actionable,
      );
      expect(
        node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        actionable,
      );
      if (actionable) {
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          node.id,
          ui.SemanticsAction.tap,
        );
      }
      if (entry.key == VoiceRecordingState.reviewing) {
        final discard = tester.getSemantics(
          find.bySemanticsLabel('Discard recording'),
        );
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          discard.id,
          ui.SemanticsAction.tap,
        );
      }
    }
    handle.dispose();
    expect([starts, stops, sends, discards], [1, 2, 1, 1]);
  });

  group('Send as text recording controls', () {
    late FakeModelDeliveryController delivery;

    setUp(() {
      debugTranslatePreviewEnabledOverride = true;
      delivery = FakeModelDeliveryController(const ModelReady(sizeBytes: 1));
      debugModelDeliveryOverride = delivery;
    });

    tearDown(() {
      debugTranslatePreviewEnabledOverride = null;
      debugModelDeliveryOverride = null;
    });

    Widget recordingBar({
      required VoiceRecordingState phase,
      required bool compact,
      required String locale,
      VoidCallback? onText,
      VoidCallback? onVoice,
      VoidCallback? onDiscard,
    }) => MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ComposeArea(
            onSend: (_) {},
            compact: compact,
            recordingState: phase,
            onRecordStart: () {},
            onRecordStop: onVoice ?? () {},
            onRecordCancel: () {},
            onReviewSend: onVoice ?? () {},
            onReviewDiscard: onDiscard ?? () {},
            onSendAsText: onText,
          ),
        ),
      ),
    );

    for (final entry in {
      'en': 'Send as text',
      'de': 'Als Text senden',
      'ar': 'إرسال كنص',
    }.entries) {
      for (final compact in [false, true]) {
        for (final phase in [
          VoiceRecordingState.recording,
          VoiceRecordingState.reviewing,
        ]) {
          testWidgets(
            '${entry.key} ${phase.name} compact=$compact exposes one localized text action',
            (tester) async {
              final semantics = tester.ensureSemantics();
              var conversions = 0;
              var voices = 0;
              await tester.pumpWidget(
                recordingBar(
                  phase: phase,
                  compact: compact,
                  locale: entry.key,
                  onText: () => conversions++,
                  onVoice: () => voices++,
                ),
              );
              await tester.pump();
              expect(find.text(entry.value), findsOneWidget);
              final action = find.bySemanticsLabel(entry.value);
              expect(action, findsOneWidget);
              final node = tester.getSemantics(action);
              expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
              expect(
                node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
                isTrue,
              );
              tester.binding.renderViews.single.owner!.semanticsOwner!
                  .performAction(node.id, ui.SemanticsAction.tap);
              await tester.pump();
              expect(conversions, 1);
              expect(voices, 0);
              expect(tester.takeException(), isNull);
              semantics.dispose();
            },
          );
        }
        testWidgets(
          '${entry.key} compact=$compact transcribing retains discard and disables voice',
          (tester) async {
            final semantics = tester.ensureSemantics();
            var voices = 0;
            var discards = 0;
            await tester.pumpWidget(
              recordingBar(
                phase: VoiceRecordingState.transcribing,
                compact: compact,
                locale: entry.key,
                onText: () {},
                onVoice: () => voices++,
                onDiscard: () => discards++,
              ),
            );
            await tester.pump();
            final l10n = AppLocalizations.of(
              tester.element(find.byType(ComposeArea)),
            )!;
            expect(find.text(l10n.translator_transcribing), findsOneWidget);
            expect(find.text(entry.value), findsNothing);
            expect(find.byType(TextField), findsNothing);
            final voice = tester.getSemantics(
              find.bySemanticsLabel(l10n.voice_review_send_action),
            );
            expect(
              voice.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            await tester.tap(find.byKey(const ValueKey('voice-review-send')));
            await tester.tap(
              find.byKey(const ValueKey('voice-review-discard')),
            );
            expect(voices, 0);
            expect(discards, 1);
            expect(tester.takeException(), isNull);
            semantics.dispose();
          },
        );
      }
    }

    for (final phase in [
      VoiceRecordingState.recording,
      VoiceRecordingState.reviewing,
    ]) {
      testWidgets('${phase.name} follows mounted model capability changes', (
        tester,
      ) async {
        await tester.pumpWidget(
          recordingBar(
            phase: phase,
            compact: false,
            locale: 'en',
            onText: () {},
          ),
        );
        expect(find.text('Send as text'), findsOneWidget);
        delivery.state.value = const ModelUnsupported();
        await tester.pump();
        expect(find.text('Send as text'), findsNothing);
        delivery.state.value = const ModelReady(sizeBytes: 1);
        await tester.pump();
        expect(find.text('Send as text'), findsOneWidget);
      });
    }

    testWidgets(
      'Thought-style recording without conversion callback keeps its controls',
      (tester) async {
        await tester.pumpWidget(
          recordingBar(
            phase: VoiceRecordingState.recording,
            compact: false,
            locale: 'en',
          ),
        );
        expect(find.text('Send as text'), findsNothing);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.byType(VoiceRecordButton), findsOneWidget);
      },
    );

    Widget optionO({
      required BackgroundReadableColors colors,
      VoiceRecordingState phase = VoiceRecordingState.reviewing,
      VoiceTextNotice notice = VoiceTextNotice.none,
      String? initialText,
      VoidCallback? onText,
      VoidCallback? onVoice,
      VoidCallback? onDiscard,
    }) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: [colors]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ComposeArea(
            onSend: (_) {},
            recordingState: phase,
            voiceTextNotice: notice,
            initialText: initialText,
            onDraftChanged: (_) {},
            onRecordStart: () {},
            onRecordStop: () {},
            onRecordCancel: () {},
            onReviewSend: onVoice ?? () {},
            onReviewDiscard: onDiscard ?? () {},
            onSendAsText: onText ?? () {},
          ),
        ),
      ),
    );

    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    final presets = {
      'dark': BackgroundReadableColors.dark,
      'light': BackgroundReadableColors.representativeLight,
    };

    for (final preset in presets.entries) {
      for (final phase in [
        VoiceRecordingState.recording,
        VoiceRecordingState.reviewing,
      ]) {
        testWidgets(
          '${preset.key} ${phase.name}: Send as text is a readable outlined '
          'button centred under the row',
          (tester) async {
            await tester.pumpWidget(
              optionO(colors: preset.value, phase: phase),
            );
            final action = find.byKey(const ValueKey('voice-send-as-text'));
            expect(action, findsOneWidget);
            final button = tester.widget<OutlinedButton>(action);
            expect(
              find.descendant(
                of: action,
                matching: find.byIcon(Icons.notes_rounded),
              ),
              findsOneWidget,
            );
            final size = tester.getSize(action);
            expect(size.height, greaterThanOrEqualTo(44));
            final bar = tester.getRect(find.byType(ComposeArea));
            final rect = tester.getRect(action);
            expect((rect.center.dx - bar.center.dx).abs(), lessThan(1));
            final row = tester.getRect(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('composer-attach-button')),
                    matching: find.byType(Row),
                  )
                  .first,
            );
            expect(rect.top, greaterThanOrEqualTo(row.bottom));

            final style = button.style!;
            final side = style.side!.resolve(const {})!;
            expect(side.width, 1.5);
            final shape =
                style.shape!.resolve(const {})! as RoundedRectangleBorder;
            expect(shape.borderRadius, BorderRadius.circular(22));
            final labelColor = style.foregroundColor!.resolve(const {})!;
            final barColor = preset.value.composerBarColor.withValues(alpha: 1);
            expect(labelColor, preset.value.accent);
            expect(side.color, preset.value.accent);
            expect(contrast(labelColor, barColor), greaterThanOrEqualTo(4.5));
          },
        );
      }

      testWidgets('${preset.key}: the from-voice hint sits above the row and '
          'leaves with the words', (tester) async {
        await tester.pumpWidget(
          optionO(
            colors: preset.value,
            phase: VoiceRecordingState.idle,
            notice: VoiceTextNotice.fromVoice,
            initialText: 'spoken words',
          ),
        );
        await tester.pump();
        const hint = 'From your voice. Check the words before you send.';
        expect(find.text(hint), findsOneWidget);
        expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
        final text = tester.widget<Text>(find.text(hint));
        expect(text.style!.fontSize, inInclusiveRange(12.5, 13));
        expect(text.style!.color, preset.value.textMuted);
        expect(
          tester.getRect(find.text(hint)).bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(TextField)).top),
        );
        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        expect(find.text(hint), findsNothing);
      });

      testWidgets('${preset.key}: a failed transcription shows the inline '
          'card with two equal choices', (tester) async {
        var texts = 0;
        var voices = 0;
        var discards = 0;
        await tester.pumpWidget(
          optionO(
            colors: preset.value,
            notice: VoiceTextNotice.failed,
            onText: () => texts++,
            onVoice: () => voices++,
            onDiscard: () => discards++,
          ),
        );
        await tester.pump();
        final card = find.byKey(const ValueKey('voice-text-failed-card'));
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.text("Couldn't transcribe")),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('Your recording is still here.'),
          ),
          findsOneWidget,
        );
        final send = find.descendant(
          of: card,
          matching: find.widgetWithText(FilledButton, 'Send voice message'),
        );
        final retry = find.descendant(
          of: card,
          matching: find.widgetWithText(OutlinedButton, 'Try again'),
        );
        expect(send, findsOneWidget);
        expect(retry, findsOneWidget);
        expect(tester.getSize(send).height, 44);
        expect(tester.getSize(retry), tester.getSize(send));
        expect(find.byKey(const ValueKey('voice-send-as-text')), findsNothing);
        expect(
          tester.getRect(card).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey('voice-review-send'))).top,
          ),
        );
        await tester.tap(send);
        await tester.tap(retry);
        await tester.tap(find.byKey(const ValueKey('voice-review-discard')));
        expect([voices, texts, discards], [1, 1, 1]);
      });
    }
  });

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

    // 204 TC-204-01 (BUG-2): the "+" attach button must be the SAME size as the
    // voice-note button — the user's literal ask. On HEAD the "+" Container is
    // 36×36 while VoiceRecordButton is 48×48, so both assertions RED.
    testWidgets('attach button matches the voice-note button size (48x48)', (
      tester,
    ) async {
      // Empty text + non-null record callbacks => the mic VoiceRecordButton
      // renders alongside the "+" (see _shouldShowMicButton).
      await tester.pumpWidget(
        buildTestWidget(onRecordStart: () {}, onRecordStop: () {}),
      );

      final attach = find.byKey(const ValueKey('composer-attach-button'));
      expect(attach, findsOneWidget);
      expect(find.byType(VoiceRecordButton), findsOneWidget);

      // Absolute 48-pt tap target.
      expect(tester.getSize(attach), const Size(48, 48));
      // Parity with the mic — "same size as the voice-note button".
      expect(
        tester.getSize(attach),
        tester.getSize(find.byType(VoiceRecordButton)),
      );
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

    testWidgets('requests focus without clearing the existing draft', (
      tester,
    ) async {
      late StateSetter setHostState;
      var shouldRequestFocus = false;

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
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: ComposeArea(
                    onSend: (_) {},
                    initialText: 'Draft stays here',
                    shouldRequestFocus: shouldRequestFocus,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      setHostState(() => shouldRequestFocus = true);
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'Draft stays here');
      expect(textField.focusNode?.hasFocus, isTrue);
    });

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

    testWidgets('by default an empty chat composer hides Send until there is '
        'text', (tester) async {
      double shown() {
        var opacity = 1.0;
        for (
          RenderObject? box = tester.renderObject(
            find.byIcon(Icons.arrow_upward_rounded),
          );
          box != null;
          box = box.parent
        ) {
          if (box is RenderOpacity) opacity *= box.opacity;
        }
        return opacity;
      }

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      expect(shown(), 0.0);

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pumpAndSettle();
      expect(shown(), 1.0);
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
      List<double> amplitudeValues = const <double>[],
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
              amplitudeValues: amplitudeValues,
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
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsNothing);
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

    testWidgets(
      'DTR08-COMP-002 shared recording overlay keeps elapsed amplitudes and cancel wiring',
      (tester) async {
        var cancelled = false;
        const amplitudes = <double>[0.1, 0.5, 0.9];
        await tester.pumpWidget(
          buildVoiceWidget(
            recordingState: VoiceRecordingState.recording,
            recordingDuration: const Duration(minutes: 2, seconds: 7),
            amplitudeValues: amplitudes,
            onRecordStart: () {},
            onRecordStop: () {},
            onRecordCancel: () => cancelled = true,
          ),
        );

        final overlay = tester.widget<RecordingOverlay>(
          find.byType(RecordingOverlay),
        );
        expect(overlay.elapsed, const Duration(minutes: 2, seconds: 7));
        expect(overlay.amplitudeValues, amplitudes);
        expect(find.text('2:07'), findsOneWidget);

        overlay.onCancel();
        expect(cancelled, isTrue);
      },
    );

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
