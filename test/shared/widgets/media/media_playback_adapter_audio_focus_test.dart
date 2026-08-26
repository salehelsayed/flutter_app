import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/shared/widgets/media/media_playback_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

void main() {
  test(
    'Android video retains audio-focus ownership without background playback',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final options = userInitiatedMediaVideoPlayerOptions();

      expect(options.mixWithOthers, isFalse);
      expect(options.allowBackgroundPlayback, isFalse);
    },
  );

  test('non-Android video mixes notification audio', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in <TargetPlatform>{
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.fuchsia,
    }) {
      debugDefaultTargetPlatformOverride = platform;
      final options = userInitiatedMediaVideoPlayerOptions();
      expect(options.mixWithOthers, isTrue, reason: platform.name);
      expect(options.allowBackgroundPlayback, isFalse, reason: platform.name);
    }
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'production adapter passes the mixing policy to its file controller',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      File? capturedFile;
      VideoPlayerOptions? capturedOptions;
      final adapter = VideoPlayerControllerAdapter(
        '/tmp/incoming-video.mp4',
        controllerFactory: (file, options) {
          capturedFile = file;
          capturedOptions = options;
          return _NoopVideoPlayerController();
        },
        becomingNoisyEvents: const Stream<void>.empty(),
      );

      await adapter.initialize();

      expect(capturedFile?.path, '/tmp/incoming-video.mp4');
      expect(capturedOptions?.mixWithOthers, isFalse);
      expect(capturedOptions?.allowBackgroundPlayback, isFalse);
      await adapter.dispose();
    },
  );

  test('becoming noisy pauses active video without automatic resume', () async {
    final noisyEvents = StreamController<void>.broadcast(sync: true);
    addTearDown(noisyEvents.close);
    final controller = _TrackingVideoPlayerController();
    final adapter = VideoPlayerControllerAdapter(
      '/tmp/incoming-video.mp4',
      controllerFactory: (_, _) => controller,
      becomingNoisyEvents: noisyEvents.stream,
    );

    await adapter.initialize();
    controller.setPlaying(true);

    noisyEvents.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(controller.pauseCalls, 1);
    expect(controller.playCalls, 0);
    expect(controller.value.isPlaying, isFalse);

    // A later noisy event while already paused stays a no-op and never gains
    // authority to restart playback.
    noisyEvents.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(controller.pauseCalls, 1);
    expect(controller.playCalls, 0);

    await adapter.dispose();
  });

  test('disposing the adapter cancels becoming-noisy handling', () async {
    final noisyEvents = StreamController<void>.broadcast(sync: true);
    addTearDown(noisyEvents.close);
    final controller = _TrackingVideoPlayerController();
    final adapter = VideoPlayerControllerAdapter(
      '/tmp/incoming-video.mp4',
      controllerFactory: (_, _) => controller,
      becomingNoisyEvents: noisyEvents.stream,
    );

    await adapter.initialize();
    controller.setPlaying(true);
    await adapter.dispose();

    noisyEvents.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(controller.pauseCalls, 0);
    expect(controller.disposeCalls, 1);
  });
}

class _NoopVideoPlayerController extends VideoPlayerController {
  _NoopVideoPlayerController()
    : super.networkUrl(Uri.parse('https://example.invalid/noop.mp4'));

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setLooping(bool looping) async {}
}

class _TrackingVideoPlayerController extends VideoPlayerController {
  _TrackingVideoPlayerController()
    : super.networkUrl(Uri.parse('https://example.invalid/tracking.mp4'));

  int pauseCalls = 0;
  int playCalls = 0;
  int disposeCalls = 0;

  void setPlaying(bool isPlaying) {
    value = value.copyWith(isPlaying: isPlaying);
  }

  @override
  Future<void> initialize() async {
    value = value.copyWith(isInitialized: true);
  }

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> play() async {
    playCalls++;
    setPlaying(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    setPlaying(false);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await super.dispose();
  }
}
