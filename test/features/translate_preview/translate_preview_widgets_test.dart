import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/features/translate_preview/translate_preview_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_model_delivery_controller.dart';

class _FakeAi implements OnDeviceAi {
  final translations = <({String text, String languageName})>[];
  final transcriptions = <String>[];
  Completer<String> next = Completer<String>();

  @override
  Future<String> translate(String text, {required String languageName}) {
    translations.add((text: text, languageName: languageName));
    return next.future;
  }

  @override
  Future<String> transcribe(String audioPath) {
    transcriptions.add(audioPath);
    return next.future;
  }
}

Widget _host(Widget child, {Locale locale = const Locale('en')}) =>
    localizedApp(
      Scaffold(body: Column(children: [const Text('original thought'), child])),
      locale: locale,
    );

// Each test makes its own fake: a Completer made in setUp lives outside the
// test's fake-async zone, so completing it never reaches tester.pump().
void main() {
  testWidgets('Translate: loading, then the translation with its label, '
      'BETA tag, and Hide hides it, in the Mknoon language', (tester) async {
    final ai = _FakeAi();
    tester.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(
      _host(
        TranslatePreview(text: 'How are you today?', ai: ai),
        locale: const Locale('de'),
      ),
    );

    await tester.tap(find.text('Übersetzung anzeigen'));
    await tester.pump();
    expect(find.text('Wird übersetzt…'), findsOneWidget);
    expect(ai.translations, [
      (text: 'How are you today?', languageName: 'German'),
    ]);

    ai.next.complete('Wie geht es dir heute?');
    await tester.pump();
    expect(find.text('Wie geht es dir heute?'), findsOneWidget);
    expect(find.text('BETA'), findsOneWidget);
    expect(find.text('Nur auf deinem Handy'), findsOneWidget);
    expect(find.text('original thought'), findsOneWidget);

    await tester.tap(find.text('Ausblenden'));
    await tester.pump();
    expect(find.text('Wie geht es dir heute?'), findsNothing);
    expect(find.text('original thought'), findsOneWidget);
    expect(find.text('Übersetzung anzeigen'), findsOneWidget);

    await tester.tap(find.text('Übersetzung anzeigen'));
    await tester.pump();
    expect(find.text('Wie geht es dir heute?'), findsOneWidget);
    expect(ai.translations, hasLength(1));
  });

  testWidgets('Translate targets the Mknoon app language, not the phone '
      'language', (tester) async {
    final ai = _FakeAi();
    tester.platformDispatcher.localeTestValue = const Locale('fr');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(
      _host(
        TranslatePreview(text: 'How are you today?', ai: ai),
        locale: const Locale('de'),
      ),
    );

    await tester.tap(find.text('Übersetzung anzeigen'));
    await tester.pump();
    expect(ai.translations, [
      (text: 'How are you today?', languageName: 'German'),
    ]);
  });

  testWidgets("Translate: a failure says Couldn't translate and Try again "
      'runs it again', (tester) async {
    final ai = _FakeAi();
    await tester.pumpWidget(
      _host(TranslatePreview(text: 'مرحبا كيف حالك', ai: ai)),
    );

    await tester.tap(find.text('See translation'));
    await tester.pump();
    ai.next.completeError(StateError('model missing'));
    await tester.pump();
    expect(find.text("Couldn't translate"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    ai.next = Completer<String>();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('Translating…'), findsOneWidget);
    ai.next.complete('Hello, how are you');
    await tester.pump();
    expect(find.text('Hello, how are you'), findsOneWidget);
    expect(ai.translations.map((t) => t.languageName), ['English', 'English']);
  });

  testWidgets(
    'See translation is hidden for the Mknoon language and for Arabizi',
    (tester) async {
      final ai = _FakeAi();
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              TranslatePreview(text: 'How are you today?', ai: ai),
              TranslatePreview(text: 'ana mesh 3aref', ai: ai),
            ],
          ),
        ),
      );
      expect(find.text('See translation'), findsNothing);
    },
  );

  testWidgets('Transcribe: loading, the transcript with its label, then '
      'See translation on the transcript', (tester) async {
    final ai = _FakeAi();
    await tester.pumpWidget(
      _host(TranscribePreview(audioPath: '/tmp/voice.m4a', ai: ai)),
    );

    await tester.tap(find.text('Transcribe'));
    await tester.pump();
    expect(find.text('Transcribing…'), findsOneWidget);
    expect(ai.transcriptions, ['/tmp/voice.m4a']);

    ai.next.complete('أنا في الطريق');
    await tester.pump();
    expect(find.text('أنا في الطريق'), findsOneWidget);
    expect(find.text('Only on your phone'), findsOneWidget);
    expect(find.text('Hide'), findsNothing);

    ai.next = Completer<String>();
    await tester.tap(find.text('See translation'));
    await tester.pump();
    ai.next.complete("I'm on my way");
    await tester.pump();
    expect(ai.translations, [(text: 'أنا في الطريق', languageName: 'English')]);
    expect(find.text("I'm on my way"), findsOneWidget);
    expect(find.text('Only on your phone'), findsNWidgets(2));
    expect(find.text('Hide'), findsOneWidget);
  });

  testWidgets("Transcribe: a failure says Couldn't transcribe", (tester) async {
    final ai = _FakeAi();
    await tester.pumpWidget(
      _host(TranscribePreview(audioPath: '/tmp/voice.m4a', ai: ai)),
    );
    await tester.tap(find.text('Transcribe'));
    await tester.pump();
    ai.next.completeError(StateError('decode failed'));
    await tester.pump();
    expect(find.text("Couldn't transcribe"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('A German app shows the busy and failure labels in German', (
    tester,
  ) async {
    final ai = _FakeAi();
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            TranslatePreview(text: 'مرحبا كيف حالك', ai: ai),
            TranscribePreview(audioPath: '/tmp/voice.m4a', ai: ai),
          ],
        ),
        locale: const Locale('de'),
      ),
    );

    await tester.tap(find.text('Übersetzung anzeigen'));
    await tester.tap(find.text('Abschreiben'));
    await tester.pump();
    expect(find.text('Wird übersetzt…'), findsOneWidget);
    expect(find.text('Wird abgeschrieben…'), findsOneWidget);

    ai.next.completeError(StateError('model missing'));
    await tester.pump();
    expect(find.text('Übersetzen fehlgeschlagen'), findsOneWidget);
    expect(find.text('Abschreiben fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsNWidgets(2));
  });
}
