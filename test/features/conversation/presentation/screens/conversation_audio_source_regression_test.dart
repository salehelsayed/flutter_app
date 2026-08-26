// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../../../../shared/fakes/fake_just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConversationScreen audio source regression', () {
    late JustAudioPlatform originalPlatform;
    late _TrackingFakeJustAudioPlatform fakePlatform;

    setUp(() {
      originalPlatform = JustAudioPlatform.instance;
      fakePlatform = _TrackingFakeJustAudioPlatform();
      JustAudioPlatform.instance = fakePlatform;
    });

    tearDown(() async {
      await fakePlatform.disposeAllPlayers(DisposeAllPlayersRequest());
      JustAudioPlatform.instance = originalPlatform;
    });

    testWidgets('rapid outgoing audio insertions load distinct local sources', (
      tester,
    ) async {
      ConversationMessage makeOutgoingVoice({
        required String messageId,
        required String attachmentId,
        required String localPath,
      }) {
        return ConversationMessage(
          id: messageId,
          contactPeerId: 'peer-b',
          senderPeerId: 'peer-a',
          text: '',
          timestamp: '2026-02-26T18:00:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-26T18:00:00.000Z',
          media: [
            MediaAttachment(
              id: attachmentId,
              messageId: messageId,
              mime: 'audio/mp4',
              size: 1234,
              mediaType: 'audio',
              durationMs: 1200,
              localPath: localPath,
              downloadStatus: 'done',
              createdAt: '2026-02-26T18:00:00.000Z',
            ),
          ],
        );
      }

      final m1 = makeOutgoingVoice(
        messageId: 'msg-1',
        attachmentId: 'aud-1',
        localPath: '/tmp/voice_1.m4a',
      );
      final m2 = makeOutgoingVoice(
        messageId: 'msg-2',
        attachmentId: 'aud-2',
        localPath: '/tmp/voice_2.m4a',
      );
      final m3 = makeOutgoingVoice(
        messageId: 'msg-3',
        attachmentId: 'aud-3',
        localPath: '/tmp/voice_3.m4a',
      );

      await tester.pumpWidget(_buildScreen(messages: [m1]));
      await tester.pump();

      await tester.pumpWidget(_buildScreen(messages: [m1, m2]));
      await tester.pump();

      await tester.pumpWidget(_buildScreen(messages: [m1, m2, m3]));
      await tester.pump();

      final loadedPaths = fakePlatform.loadedUris
          .map((uri) => Uri.parse(uri).path)
          .toSet();

      expect(loadedPaths, contains('/tmp/voice_1.m4a'));
      expect(loadedPaths, contains('/tmp/voice_2.m4a'));
      expect(loadedPaths, contains('/tmp/voice_3.m4a'));

      expect(find.byKey(const ValueKey('aud-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('aud-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('aud-3')), findsOneWidget);

      // Ensure AudioPlayer timers are disposed before test teardown.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
      'incoming message preserves the active voice player without reloading',
      (tester) async {
        final voice = ConversationMessage(
          id: 'voice-message',
          contactPeerId: 'peer-b',
          senderPeerId: 'peer-b',
          text: '',
          timestamp: '2026-02-26T18:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-26T18:00:00.000Z',
          media: const [
            MediaAttachment(
              id: 'voice-attachment',
              messageId: 'voice-message',
              mime: 'audio/mp4',
              size: 1234,
              mediaType: 'audio',
              durationMs: 1200,
              localPath: '/tmp/voice_message.m4a',
              downloadStatus: 'done',
              createdAt: '2026-02-26T18:00:00.000Z',
            ),
          ],
        );
        final incomingText = ConversationMessage(
          id: 'incoming-text',
          contactPeerId: 'peer-b',
          senderPeerId: 'peer-b',
          text: 'New message while listening',
          timestamp: '2026-02-26T18:01:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-26T18:01:00.000Z',
        );

        final sourceLoad = fakePlatform.enqueueLoad(
          reportedDuration: const Duration(milliseconds: 1200),
        );
        await tester.pumpWidget(_buildScreen(messages: [voice]));
        await tester.pump();
        await sourceLoad.started;
        sourceLoad.complete();
        await _flushAsyncPlayerTasks(tester);

        expect(fakePlatform.activePlayerIds, hasLength(1));
        expect(fakePlatform.loadedUris, hasLength(1));
        final originalPlayerId = fakePlatform.activePlayerIds.single;
        final originalPlayer = fakePlatform.player(originalPlayerId);

        // Drive the exact platform player owned by the visible voice control
        // into the playing state, then verify the UI reflects that state.
        await originalPlayer.play(PlayRequest());
        await _flushAsyncPlayerTasks(tester);

        expect(fakePlatform.playCallCount, 1);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

        await tester.pumpWidget(_buildScreen(messages: [voice, incomingText]));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));

        expect(find.text('New message while listening'), findsOneWidget);
        expect(fakePlatform.initCallCount, 1);
        expect(fakePlatform.disposePlayerCallCount, 0);
        expect(fakePlatform.loadedUris, hasLength(1));
        expect(fakePlatform.activePlayerIds.single, originalPlayerId);
        expect(
          identical(fakePlatform.player(originalPlayerId), originalPlayer),
          isTrue,
        );
        expect(fakePlatform.playCallCount, 1);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'playing voice survives incoming rows beyond the ListView cache without reloading',
      (tester) async {
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);
        const voice = ConversationMessage(
          id: 'viewport-voice-message',
          contactPeerId: 'peer-b',
          senderPeerId: 'peer-b',
          text: '',
          timestamp: '2026-02-26T18:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-26T18:00:00.000Z',
          media: [
            MediaAttachment(
              id: 'viewport-voice-attachment',
              messageId: 'viewport-voice-message',
              mime: 'audio/mp4',
              size: 1234,
              mediaType: 'audio',
              durationMs: 1200,
              localPath: '/tmp/viewport_voice_message.m4a',
              downloadStatus: 'done',
              createdAt: '2026-02-26T18:00:00.000Z',
            ),
          ],
        );
        final tallBody = List<String>.filled(
          20,
          'viewport-filling-content',
        ).join(' ');
        final incomingRows = List<ConversationMessage>.generate(24, (index) {
          final timestamp = DateTime.utc(
            2026,
            2,
            26,
            18,
            1,
          ).add(Duration(minutes: index)).toIso8601String();
          return ConversationMessage(
            id: 'incoming-row-$index',
            contactPeerId: 'peer-b',
            senderPeerId: 'peer-b',
            text: 'Incoming row $index $tallBody',
            timestamp: timestamp,
            status: 'delivered',
            isIncoming: true,
            createdAt: timestamp,
          );
        });

        final sourceLoad = fakePlatform.enqueueLoad(
          reportedDuration: const Duration(milliseconds: 1200),
        );
        await tester.pumpWidget(
          _buildScreen(
            messages: const [voice],
            scrollController: scrollController,
          ),
        );
        await tester.pump();
        await sourceLoad.started;
        sourceLoad.complete();
        await _flushAsyncPlayerTasks(tester);

        final originalPlayerId = fakePlatform.activePlayerIds.single;
        final originalPlayer = fakePlatform.player(originalPlayerId);
        await originalPlayer.play(PlayRequest());
        await _flushAsyncPlayerTasks(tester);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

        final accumulatedMessages = <ConversationMessage>[voice];
        for (final incoming in incomingRows) {
          accumulatedMessages.add(incoming);
          await tester.pumpWidget(
            _buildScreen(
              messages: List<ConversationMessage>.unmodifiable(
                accumulatedMessages,
              ),
              scrollController: scrollController,
            ),
          );
          await tester.pump();
        }
        await _flushAsyncPlayerTasks(tester);

        const voiceKey = ValueKey('viewport-voice-attachment');
        expect(scrollController.position.maxScrollExtent, greaterThan(2000));
        expect(find.byKey(voiceKey), findsNothing);
        expect(fakePlatform.initCallCount, 1);
        expect(
          fakePlatform.disposePlayerCallCount,
          0,
          reason: 'the playing row must remain alive outside the sliver cache',
        );
        expect(fakePlatform.loadedUris, hasLength(1));
        expect(fakePlatform.activePlayerIds.single, originalPlayerId);
        expect(
          identical(fakePlatform.player(originalPlayerId), originalPlayer),
          isTrue,
        );
        expect(fakePlatform.playCallCount, 1);

        // Playback-aware retention must end when playback ends; ordinary
        // paused rows remain recyclable rather than leaking every voice row.
        await originalPlayer.pause(PauseRequest());
        await _flushAsyncPlayerTasks(tester);
        expect(fakePlatform.disposePlayerCallCount, 1);
        expect(fakePlatform.loadedUris, hasLength(1));
        expect(fakePlatform.activePlayerIds, isEmpty);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
  });
}

class _TrackingFakeJustAudioPlatform extends FakeJustAudioPlatform {
  final Map<String, AudioPlayerPlatform> _activePlayers = {};
  int initCallCount = 0;
  int disposePlayerCallCount = 0;

  Iterable<String> get activePlayerIds => _activePlayers.keys;

  AudioPlayerPlatform player(String id) => _activePlayers[id]!;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    initCallCount++;
    final player = await super.init(request);
    _activePlayers[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    disposePlayerCallCount++;
    _activePlayers.remove(request.id);
    return super.disposePlayer(request);
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    _activePlayers.clear();
    return super.disposeAllPlayers(request);
  }
}

Future<void> _flushAsyncPlayerTasks(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

Widget _buildScreen({
  required List<ConversationMessage> messages,
  ScrollController? scrollController,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ConversationScreen(
        contactPeerId: 'peer-b',
        contactUsername: 'User-B',
        connectionDate: 'February 26, 2026',
        ownPeerId: 'peer-a',
        messages: messages,
        scrollController: scrollController,
        onSend: (_) {},
        onBack: () {},
        hasMoreOlderMessages: true,
        initialLoadDone: true,
      ),
    ),
  );
}
