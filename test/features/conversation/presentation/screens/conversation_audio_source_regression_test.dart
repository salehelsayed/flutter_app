// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConversationScreen audio source regression', () {
    late JustAudioPlatform originalPlatform;
    late _FakeJustAudioPlatform fakePlatform;

    setUp(() {
      originalPlatform = JustAudioPlatform.instance;
      fakePlatform = _FakeJustAudioPlatform();
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
  });
}

Widget _buildScreen({required List<ConversationMessage> messages}) {
  return MaterialApp(
    home: Scaffold(
      body: ConversationScreen(
        contactPeerId: 'peer-b',
        contactUsername: 'User-B',
        connectionDate: 'February 26, 2026',
        ownPeerId: 'peer-a',
        messages: messages,
        onSend: (_) {},
        onBack: () {},
        hasMoreOlderMessages: true,
        initialLoadDone: true,
      ),
    ),
  );
}

class _FakeJustAudioPlatform extends JustAudioPlatform {
  final Map<String, _FakeAudioPlayerPlatform> _players = {};
  final List<String> loadedUris = [];

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = _FakeAudioPlayerPlatform(
      request.id,
      onLoadUri: (uri) => loadedUris.add(uri),
    );
    _players[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    await _players.remove(request.id)?.dispose(DisposeRequest());
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    for (final player in _players.values) {
      await player.dispose(DisposeRequest());
    }
    _players.clear();
    return DisposeAllPlayersResponse();
  }
}

class _FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  final void Function(String uri) onLoadUri;

  final _playbackEvents = StreamController<PlaybackEventMessage>.broadcast();
  final _playerData = StreamController<PlayerDataMessage>.broadcast();
  bool _disposed = false;

  _FakeAudioPlayerPlatform(super.id, {required this.onLoadUri}) {
    _emitPlayback(ProcessingStateMessage.idle);
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _playbackEvents.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _playerData.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final uri = _firstUri(request.audioSourceMessage);
    if (uri != null) {
      onLoadUri(uri);
    }

    _emitPlayback(
      ProcessingStateMessage.ready,
      duration: const Duration(seconds: 1),
      currentIndex: request.initialIndex ?? 0,
    );

    return LoadResponse(duration: const Duration(seconds: 1));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _playerData.add(PlayerDataMessage(playing: true));
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _playerData.add(PlayerDataMessage(playing: false));
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    return SetVolumeResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    return SetSpeedResponse();
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async {
    return SetPitchResponse();
  }

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
    SetSkipSilenceRequest request,
  ) async {
    return SetSkipSilenceResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async {
    return SetShuffleModeResponse();
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async {
    return SetAndroidAudioAttributesResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    return SeekResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    if (_disposed) return DisposeResponse();
    _disposed = true;
    await _playbackEvents.close();
    await _playerData.close();
    return DisposeResponse();
  }

  void _emitPlayback(
    ProcessingStateMessage state, {
    Duration updatePosition = Duration.zero,
    Duration bufferedPosition = Duration.zero,
    Duration? duration,
    int? currentIndex,
  }) {
    if (_disposed) return;
    _playbackEvents.add(
      PlaybackEventMessage(
        processingState: state,
        updateTime: DateTime.now(),
        updatePosition: updatePosition,
        bufferedPosition: bufferedPosition,
        duration: duration,
        icyMetadata: null,
        currentIndex: currentIndex,
        androidAudioSessionId: null,
      ),
    );
  }

  String? _firstUri(AudioSourceMessage source) {
    if (source is UriAudioSourceMessage) return source.uri;
    if (source is ClippingAudioSourceMessage) return _firstUri(source.child);
    if (source is LoopingAudioSourceMessage) return _firstUri(source.child);
    if (source is ConcatenatingAudioSourceMessage) {
      if (source.children.isEmpty) return null;
      return _firstUri(source.children.first);
    }
    return null;
  }
}
