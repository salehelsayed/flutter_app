// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../../fakes/fake_just_audio.dart';

/// Beta 2026-09-24: a received voice note read as
/// "Beta iPhone\n0:11\n11:05 PM\nReceived via direct connection". Nothing told
/// a screen-reader user it was a voice message.
void main() {
  late JustAudioPlatform originalPlatform;

  setUp(() {
    originalPlatform = JustAudioPlatform.instance;
    JustAudioPlatform.instance = FakeJustAudioPlatform();
  });

  tearDown(() {
    JustAudioPlatform.instance = originalPlatform;
  });

  const voiceNote = MediaAttachment(
    id: 'att-voice-0924',
    messageId: 'msg-voice-0924',
    mime: 'audio/mp4',
    size: 10000,
    mediaType: 'audio',
    durationMs: 11000,
    downloadStatus: 'done',
    createdAt: '2026-09-24T23:05:00.000Z',
  );

  Widget app(Locale locale) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: AudioPlayerWidget(attachment: voiceNote)),
  );

  for (final entry in const <String, String>{
    'en': 'Voice message',
    'de': 'Sprachnachricht',
    'ar': 'رسالة صوتية',
  }.entries) {
    testWidgets('BETA-0924-30 the voice player announces "${entry.value}" '
        '(${entry.key})', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(app(Locale(entry.key)));
        await tester.pump();

        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(entry.value))),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    });
  }
}
