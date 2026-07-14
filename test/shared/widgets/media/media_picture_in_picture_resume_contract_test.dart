import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';
import 'package:flutter_app/shared/widgets/media/media_picture_in_picture_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_playback_adapter.dart';
import 'package:flutter_app/shared/widgets/media/media_video_resume_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PiP persistence handles video only unknown later clamp and completion',
    () async {
      final gateway = _Gateway();
      final store = _Store();
      final authorization = _authorization(durationMs: null);
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(),
        reloadCurrent: () async => authorization,
        resumeStore: store,
        restorePlayback: (_) async {},
        sessionIdFactory: () => 'opaque-session',
        pollTicks: const Stream<void>.empty(),
      );
      addTearDown(controller.dispose);

      expect(
        await controller.start(
          authorization: authorization,
          playback: _Playback(
            position: const Duration(milliseconds: 12000),
            duration: Duration.zero,
          ),
        ),
        MediaPictureInPictureStartOutcome.started,
      );
      expect(store.positions, <int>[12000]);

      gateway.emit(
        const PictureInPictureEvent(
          session: 'opaque-session',
          attachment: 'attachment-1',
          state: PictureInPictureState.checkpoint,
          positionMs: 15000,
        ),
      );
      await controller.drain();
      expect(store.positions, <int>[12000, 15000]);

      gateway.emit(
        const PictureInPictureEvent(
          session: 'opaque-session',
          attachment: 'attachment-1',
          state: PictureInPictureState.checkpoint,
          positionMs: 15000,
          durationMs: 9000,
        ),
      );
      await controller.drain();
      expect(store.positions, <int>[12000, 15000, 9000]);

      gateway.emit(
        const PictureInPictureEvent(
          session: 'opaque-session',
          attachment: 'attachment-1',
          state: PictureInPictureState.completed,
          positionMs: 0,
          durationMs: 9000,
          reason: PictureInPictureTerminalReason.completed,
        ),
      );
      gateway.emit(
        const PictureInPictureEvent(
          session: 'opaque-session',
          attachment: 'attachment-1',
          state: PictureInPictureState.completed,
          positionMs: 0,
          durationMs: 9000,
          reason: PictureInPictureTerminalReason.completed,
        ),
      );
      await controller.drain();
      expect(store.positions, <int>[12000, 15000, 9000, 0]);
    },
  );

  test(
    'system close restores a current route paused at its bounded checkpoint',
    () async {
      final gateway = _Gateway();
      final store = _Store();
      final restores = <MediaPictureInPictureRestore>[];
      final authorization = _authorization(durationMs: 9000);
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(),
        reloadCurrent: () async => authorization,
        resumeStore: store,
        restorePlayback: (restore) async => restores.add(restore),
        sessionIdFactory: () => 'opaque-session',
        pollTicks: const Stream<void>.empty(),
      );
      addTearDown(controller.dispose);
      await controller.start(
        authorization: authorization,
        playback: _Playback(
          position: const Duration(milliseconds: 1000),
          duration: const Duration(milliseconds: 9000),
        ),
      );
      gateway.emit(
        const PictureInPictureEvent(
          session: 'opaque-session',
          attachment: 'attachment-1',
          state: PictureInPictureState.stopped,
          positionMs: 12000,
          durationMs: 9000,
          reason: PictureInPictureTerminalReason.systemClose,
        ),
      );
      await controller.drain();

      expect(store.positions, <int>[1000, 9000]);
      expect(restores, hasLength(1));
      expect(restores.single.positionMs, 9000);
      expect(restores.single.shouldPlay, isFalse);
    },
  );

  test('non-video never writes resume state or reaches native', () async {
    final gateway = _Gateway();
    final store = _Store();
    final authorization = _authorization(
      item: const MediaViewerItem(
        attachmentId: 'image-1',
        messageId: 'message-1',
        kind: MediaViewerKind.image,
        mime: 'image/jpeg',
        owner: MediaOwnerLane.direct,
        localPath: '/app/Documents/media/image.jpg',
        canEnterPictureInPicture: true,
      ),
    );
    final controller = MediaPictureInPictureController(
      gateway: gateway,
      pathAuthority: _PathAuthority(),
      reloadCurrent: () async => authorization,
      resumeStore: store,
      restorePlayback: (_) async {},
      sessionIdFactory: () => 'opaque-session',
    );
    addTearDown(controller.dispose);

    expect(
      await controller.start(
        authorization: authorization,
        playback: _Playback(position: Duration.zero, duration: Duration.zero),
      ),
      MediaPictureInPictureStartOutcome.denied,
    );
    expect(store.positions, isEmpty);
    expect(gateway.calls, 0);
  });
}

MediaPictureInPictureAuthorization _authorization({
  MediaViewerItem? item,
  int? durationMs,
}) => MediaPictureInPictureAuthorization(
  item:
      item ??
      MediaViewerItem(
        attachmentId: 'attachment-1',
        messageId: 'message-1',
        kind: MediaViewerKind.video,
        mime: 'video/mp4',
        owner: MediaOwnerLane.direct,
        localPath: '/app/Documents/media/video.mp4',
        durationMs: durationMs,
        canEnterPictureInPicture: true,
      ),
  generation: 1,
  policyState: MediaPictureInPicturePolicyState.ordinary,
  isIncoming: true,
  isTransferComplete: true,
  routeActive: true,
);

class _Gateway implements PictureInPictureGateway {
  final _events = StreamController<PictureInPictureEvent>.broadcast(sync: true);
  int calls = 0;

  void emit(PictureInPictureEvent event) => _events.add(event);

  @override
  Stream<PictureInPictureEvent> get events => _events.stream;
  @override
  Future<PictureInPictureCapability> capability() async {
    calls++;
    return const PictureInPictureCapability.androidSupported();
  }

  @override
  Future<PictureInPictureStartOutcome> start(
    PictureInPictureRequest request,
  ) async {
    calls++;
    return PictureInPictureStartOutcome.started;
  }

  @override
  Future<PictureInPictureCommandResult> activate(
    String session,
    String attachment,
  ) async {
    calls++;
    return const PictureInPictureCommandResult.success();
  }

  @override
  Future<PictureInPictureCommandResult> stop(
    String session,
    String attachment,
  ) async {
    calls++;
    return const PictureInPictureCommandResult.success();
  }

  @override
  Future<void> dispose() => _events.close();
}

class _PathAuthority implements AppOwnedMediaPathAuthority {
  @override
  Future<String?> authorize(String? candidatePath) async => candidatePath;
}

class _Store implements MediaViewerResumeStore {
  final positions = <int>[];
  @override
  Future<int?> readResumePosition(MediaViewerItem item) async => null;
  @override
  Future<void> writeResumePosition(MediaViewerItem item, int positionMs) async {
    positions.add(positionMs);
  }
}

class _Playback extends MediaPlaybackAdapter {
  _Playback({required this.position, required this.duration});
  @override
  final Duration position;
  @override
  final Duration duration;
  @override
  double get aspectRatio => 1;
  @override
  Object? get initializationError => null;
  @override
  bool get isCompleted => false;
  @override
  bool get isInitialized => true;
  @override
  bool get isMuted => false;
  @override
  bool get isPlaying => true;
  @override
  double get speed => 1;
  @override
  void addListener(void Function() listener) {}
  @override
  Widget buildSurface() => const SizedBox.shrink();
  @override
  Future<void> dispose() async {}
  @override
  Future<void> initialize() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> play() async {}
  @override
  void removeListener(void Function() listener) {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> setSpeed(double speed) async {}
}
