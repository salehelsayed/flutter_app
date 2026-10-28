// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../../shared/fakes/fake_just_audio.dart';

class _UnusedAi implements OnDeviceAi {
  @override
  Future<String> transcribe(String audioPath) => throw UnimplementedError();

  @override
  Future<String> translate(String text, {required String languageName}) =>
      throw UnimplementedError();
}

ConversationMessage _voice({required String id, required bool incoming}) =>
    ConversationMessage(
      id: id,
      contactPeerId: 'peer-b',
      senderPeerId: incoming ? 'peer-b' : 'peer-a',
      text: '',
      timestamp: '2026-10-28T18:00:00.000Z',
      status: 'delivered',
      isIncoming: incoming,
      createdAt: '2026-10-28T18:00:00.000Z',
      media: [
        MediaAttachment(
          id: '$id-audio',
          messageId: id,
          mime: 'audio/mp4',
          size: 1234,
          mediaType: 'audio',
          durationMs: 1200,
          localPath: '/tmp/$id.m4a',
          downloadStatus: 'done',
          createdAt: '2026-10-28T18:00:00.000Z',
        ),
      ],
    );

Widget _screen(List<ConversationMessage> messages) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ConversationScreen(
      contactPeerId: 'peer-b',
      contactUsername: 'User-B',
      connectionDate: 'October 28, 2026',
      ownPeerId: 'peer-a',
      messages: messages,
      onSend: (_) {},
      onBack: () {},
      hasMoreOlderMessages: false,
      initialLoadDone: true,
    ),
  ),
);

void main() {
  late JustAudioPlatform originalPlatform;

  setUp(() {
    originalPlatform = JustAudioPlatform.instance;
    JustAudioPlatform.instance = FakeJustAudioPlatform();
    debugOnDeviceAiOverride = _UnusedAi();
  });

  tearDown(() {
    JustAudioPlatform.instance = originalPlatform;
    debugTranslatePreviewEnabledOverride = null;
    debugOnDeviceAiOverride = null;
  });

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('without TRANSLATE_PREVIEW a received voice message has no '
      'Transcribe', (tester) async {
    expect(kTranslatePreviewEnabled, isFalse);
    await tester.pumpWidget(_screen([_voice(id: 'in', incoming: true)]));
    await tester.pump();
    expect(find.byKey(const ValueKey('in-audio')), findsOneWidget);
    expect(find.text('Transcribe'), findsNothing);
    await finish(tester);
  });

  testWidgets('with TRANSLATE_PREVIEW only the received voice message offers '
      'Transcribe', (tester) async {
    debugTranslatePreviewEnabledOverride = true;
    await tester.pumpWidget(
      _screen([
        _voice(id: 'in', incoming: true),
        _voice(id: 'out', incoming: false),
      ]),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('in-audio')), findsOneWidget);
    expect(find.byKey(const ValueKey('out-audio')), findsOneWidget);
    expect(find.text('Transcribe'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transcribe-preview-in-audio')),
      findsOneWidget,
    );
    await finish(tester);
  });
}
