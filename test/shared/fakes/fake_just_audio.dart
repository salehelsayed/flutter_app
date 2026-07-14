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
  final List<FakeAudioLoadBarrier> _queuedLoads = [];

  final List<String> loadedUris = [];
  int playCallCount = 0;

  /// Queues one caller-controlled load. Existing users that do not queue a
  /// barrier retain the original immediate zero-duration behavior.
  FakeAudioLoadBarrier enqueueLoad({required Duration reportedDuration}) {
    final barrier = FakeAudioLoadBarrier(reportedDuration: reportedDuration);
    _queuedLoads.add(barrier);
    return barrier;
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = _FakeAudioPlayer(
      request.id,
      loadAudio: _loadAudio,
      onPlay: () => playCallCount++,
    );
    _players[request.id] = player;
    return player;
  }

  Future<Duration> _loadAudio(AudioSourceMessage source) async {
    final uri = _firstUri(source);
    if (uri != null) {
      loadedUris.add(uri);
    }

    if (_queuedLoads.isEmpty) {
      return Duration.zero;
    }
    return _queuedLoads.removeAt(0)._waitForCompletion();
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

/// A deterministic observation and completion gate for one platform load.
class FakeAudioLoadBarrier {
  FakeAudioLoadBarrier({required this.reportedDuration});

  final Duration reportedDuration;
  final Completer<void> _started = Completer<void>();
  final Completer<void> _completion = Completer<void>();

  Future<void> get started => _started.future;
  bool get hasStarted => _started.isCompleted;
  bool get isCompleted => _completion.isCompleted;

  void complete() {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }

  Future<Duration> _waitForCompletion() async {
    if (!_started.isCompleted) {
      _started.complete();
    }
    await _completion.future;
    return reportedDuration;
  }
}

class _FakeAudioPlayer extends AudioPlayerPlatform {
  final Future<Duration> Function(AudioSourceMessage source) loadAudio;
  final void Function() onPlay;
  final _playbackEvents = StreamController<PlaybackEventMessage>.broadcast(
    sync: true,
  );
  final _playerData = StreamController<PlayerDataMessage>.broadcast();
  bool _disposed = false;

  _FakeAudioPlayer(super.id, {required this.loadAudio, required this.onPlay});

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _playbackEvents.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _playerData.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final duration = await loadAudio(request.audioSourceMessage);
    Timer.run(() {
      _emitPlayback(
        ProcessingStateMessage.ready,
        duration: duration,
        currentIndex: request.initialIndex ?? 0,
      );
    });
    return LoadResponse(duration: duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    onPlay();
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
    final event = PlaybackEventMessage(
      processingState: state,
      updateTime: DateTime.now(),
      updatePosition: updatePosition,
      bufferedPosition: bufferedPosition,
      duration: duration,
      icyMetadata: null,
      currentIndex: currentIndex,
      androidAudioSessionId: null,
    );
    _playbackEvents.add(event);
  }
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

/// Installs [FakeJustAudioPlatform] as the active just_audio platform.
/// Idempotent and safe to call from a test `setUp`.
void installFakeJustAudioPlatform() {
  JustAudioPlatform.instance = FakeJustAudioPlatform();
}
