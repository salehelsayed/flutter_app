import 'dart:async';

import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// A no-op [JustAudioPlatform] for widget tests that build voice bubbles.
///
/// `AudioPlayerWidget` constructs an `AudioPlayer()` in `initState`, which the
/// real platform routes to the `com.ryanheise.just_audio.methods` MethodChannel.
/// Under `flutter_test` that channel is unimplemented, so `init` /
/// `disposeAllPlayers` / `disposePlayer` throw `MissingPluginException` (failing
/// the test or polluting teardown). Installing this fake makes those calls
/// benign no-ops without any platform channel.
class FakeJustAudioPlatform extends JustAudioPlatform {
  final Map<String, _FakeAudioPlayer> _players = {};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = _FakeAudioPlayer(request.id);
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

class _FakeAudioPlayer extends AudioPlayerPlatform {
  final _playbackEvents = StreamController<PlaybackEventMessage>.broadcast();
  final _playerData = StreamController<PlayerDataMessage>.broadcast();
  bool _disposed = false;

  _FakeAudioPlayer(super.id) {
    _emitPlayback(ProcessingStateMessage.idle);
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _playbackEvents.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _playerData.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _emitPlayback(
      ProcessingStateMessage.ready,
      duration: Duration.zero,
      currentIndex: request.initialIndex ?? 0,
    );
    return LoadResponse(duration: Duration.zero);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    if (!_disposed) {
      _playerData.add(PlayerDataMessage(playing: true));
    }
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    if (!_disposed) {
      _playerData.add(PlayerDataMessage(playing: false));
    }
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
    SetSkipSilenceRequest request,
  ) async => SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async => SetAndroidAudioAttributesResponse();

  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();

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
}

/// Installs [FakeJustAudioPlatform] as the active just_audio platform.
/// Idempotent and safe to call from a test `setUp`.
void installFakeJustAudioPlatform() {
  JustAudioPlatform.instance = FakeJustAudioPlatform();
}
