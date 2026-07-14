import 'dart:async';
import 'dart:io';

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
    'capability query is non-mutating and hidden platforms never authorize media',
    () async {
      for (final capability in <PictureInPictureCapability>[
        const PictureInPictureCapability.androidSupported(),
        const PictureInPictureCapability.hidden(
          PictureInPictureCapabilityReason.iOSDisabled,
        ),
      ]) {
        final gateway = _CapabilityGateway(capability);
        var reloads = 0;
        final controller = MediaPictureInPictureController(
          gateway: gateway,
          pathAuthority: _AllowingPathAuthority(),
          reloadCurrent: () async {
            reloads++;
            return _authorization();
          },
          resumeStore: _RecordingResumeStore(),
          restorePlayback: (_) async {},
          pollTicks: const Stream<void>.empty(),
        );
        addTearDown(controller.dispose);

        expect(await controller.capability(), capability);
        expect(gateway.capabilityCalls, 1);
        expect(gateway.startCalls, 0);
        expect(reloads, 0);
      }
    },
  );

  test(
    'only ordinary completed local video can request PiP or checkpoint',
    () async {
      final ordinary = _authorization();
      expect(MediaPictureInPicturePolicy.evaluate(ordinary).isAllowed, isTrue);

      final denied = <MediaPictureInPictureAuthorization>[
        for (final state in <MediaPictureInPicturePolicyState>[
          MediaPictureInPicturePolicyState.protected,
          MediaPictureInPicturePolicyState.viewOnce,
          MediaPictureInPicturePolicyState.expired,
          MediaPictureInPicturePolicyState.quarantined,
          MediaPictureInPicturePolicyState.unsupported,
          MediaPictureInPicturePolicyState.terminal,
        ])
          _authorization(policyState: state),
        _authorization(isIncoming: false),
        _authorization(isTransferComplete: false),
        _authorization(routeActive: false),
        _authorization(item: _item(kind: MediaViewerKind.image)),
        _authorization(item: _item(canEnterPictureInPicture: false)),
        _authorization(
          item: _item(
            protection: const MediaViewerProtection(isDownloaded: false),
          ),
        ),
        _authorization(
          item: _item(
            protection: const MediaViewerProtection(isIntegrityVerified: false),
          ),
        ),
        _authorization(
          item: _item(
            protection: const MediaViewerProtection(isProtected: true),
          ),
        ),
        _authorization(item: _item(owner: null)),
        _authorization(item: _item(localPath: null)),
      ];

      for (final authorization in denied) {
        final gateway = _ThrowingGateway();
        final store = _RecordingResumeStore();
        final playback = _CountingPlaybackAdapter();
        final controller = MediaPictureInPictureController(
          gateway: gateway,
          pathAuthority: _AllowingPathAuthority(),
          reloadCurrent: () async => authorization,
          resumeStore: store,
          restorePlayback: (_) async {},
          sessionIdFactory: () => 'opaque-session',
        );
        addTearDown(controller.dispose);

        expect(
          await controller.start(
            authorization: authorization,
            playback: playback,
          ),
          MediaPictureInPictureStartOutcome.denied,
        );
        expect(gateway.calls, 0, reason: '${authorization.policyState}');
        expect(store.writes, isEmpty, reason: '${authorization.policyState}');
        expect(playback.pauseCalls, 0);
        expect(playback.disposeCalls, 0);
      }
    },
  );

  test(
    'app-owned authority accepts only canonical regular media-root files',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'pip-owned-path-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final documents = Directory('${temporary.path}/Documents')..createSync();
      final media = Directory('${documents.path}/media')..createSync();
      final localMedia = Directory('${documents.path}/local_media')
        ..createSync();
      final outside = Directory('${temporary.path}/outside')..createSync();
      final allowed = File('${media.path}/video.mp4')
        ..writeAsBytesSync(<int>[1]);
      final second = File('${localMedia.path}/second.mp4')
        ..writeAsBytesSync(<int>[2]);
      final escaped = File('${outside.path}/escaped.mp4')
        ..writeAsBytesSync(<int>[3]);
      final link = Link('${media.path}/link.mp4');
      link.createSync(escaped.path);

      final authority = IoAppOwnedMediaPathAuthority(
        documentsDirectory: () async => documents,
      );
      expect(
        await authority.authorize(allowed.path),
        await allowed.resolveSymbolicLinks(),
      );
      expect(
        await authority.authorize(second.path),
        await second.resolveSymbolicLinks(),
      );
      expect(await authority.authorize(escaped.path), isNull);
      expect(await authority.authorize(link.path), isNull);
      expect(await authority.authorize(media.path), isNull);
      expect(await authority.authorize('${media.path}/missing.mp4'), isNull);

      final symlinkedRootDocuments = Directory(
        '${temporary.path}/OtherDocuments',
      )..createSync();
      Link('${symlinkedRootDocuments.path}/media').createSync(media.path);
      final rootAuthority = IoAppOwnedMediaPathAuthority(
        documentsDirectory: () async => symlinkedRootDocuments,
      );
      expect(await rootAuthority.authorize(allowed.path), isNull);
    },
  );
}

MediaViewerItem _item({
  MediaViewerKind kind = MediaViewerKind.video,
  MediaOwnerLane? owner = MediaOwnerLane.direct,
  String? localPath = '/app/Documents/media/video.mp4',
  bool canEnterPictureInPicture = true,
  MediaViewerProtection protection = const MediaViewerProtection(),
}) => MediaViewerItem(
  attachmentId: 'attachment-1',
  messageId: 'message-1',
  kind: kind,
  mime: kind == MediaViewerKind.video ? 'video/mp4' : 'image/jpeg',
  owner: owner,
  localPath: localPath,
  durationMs: kind == MediaViewerKind.video ? 9000 : null,
  canEnterPictureInPicture: canEnterPictureInPicture,
  protection: protection,
);

MediaPictureInPictureAuthorization _authorization({
  MediaViewerItem? item,
  MediaPictureInPicturePolicyState policyState =
      MediaPictureInPicturePolicyState.ordinary,
  bool isIncoming = true,
  bool isTransferComplete = true,
  bool routeActive = true,
}) => MediaPictureInPictureAuthorization(
  item: item ?? _item(),
  generation: 7,
  policyState: policyState,
  isIncoming: isIncoming,
  isTransferComplete: isTransferComplete,
  routeActive: routeActive,
);

class _ThrowingGateway implements PictureInPictureGateway {
  int calls = 0;

  @override
  Stream<PictureInPictureEvent> get events => const Stream.empty();

  Never _unexpected() {
    calls++;
    throw StateError('ineligible media reached native PiP');
  }

  @override
  Future<PictureInPictureCapability> capability() async => _unexpected();

  @override
  Future<PictureInPictureStartOutcome> start(
    PictureInPictureRequest request,
  ) async => _unexpected();

  @override
  Future<PictureInPictureCommandResult> activate(
    String session,
    String attachment,
  ) async => _unexpected();

  @override
  Future<PictureInPictureCommandResult> stop(
    String session,
    String attachment,
  ) async => _unexpected();

  @override
  Future<void> dispose() async {}
}

class _CapabilityGateway implements PictureInPictureGateway {
  _CapabilityGateway(this.value);

  final PictureInPictureCapability value;
  int capabilityCalls = 0;
  int startCalls = 0;

  @override
  Stream<PictureInPictureEvent> get events => const Stream.empty();

  @override
  Future<PictureInPictureCapability> capability() async {
    capabilityCalls++;
    return value;
  }

  @override
  Future<PictureInPictureStartOutcome> start(
    PictureInPictureRequest request,
  ) async {
    startCalls++;
    return PictureInPictureStartOutcome.platformFailure;
  }

  @override
  Future<PictureInPictureCommandResult> activate(
    String session,
    String attachment,
  ) async => const PictureInPictureCommandResult.rejected(
    PictureInPictureFailureReason.staleSession,
  );

  @override
  Future<PictureInPictureCommandResult> stop(
    String session,
    String attachment,
  ) async => const PictureInPictureCommandResult.rejected(
    PictureInPictureFailureReason.staleSession,
  );

  @override
  Future<void> dispose() async {}
}

class _AllowingPathAuthority implements AppOwnedMediaPathAuthority {
  @override
  Future<String?> authorize(String? candidatePath) async => candidatePath;
}

class _RecordingResumeStore implements MediaViewerResumeStore {
  final writes = <int>[];

  @override
  Future<int?> readResumePosition(MediaViewerItem item) async => null;

  @override
  Future<void> writeResumePosition(MediaViewerItem item, int positionMs) async {
    writes.add(positionMs);
  }
}

class _CountingPlaybackAdapter extends MediaPlaybackAdapter {
  int pauseCalls = 0;
  int disposeCalls = 0;

  @override
  double get aspectRatio => 1;
  @override
  Duration get duration => const Duration(seconds: 9);
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
  Duration get position => const Duration(seconds: 1);
  @override
  double get speed => 1;
  @override
  void addListener(void Function() listener) {}
  @override
  Widget buildSurface() => throw UnimplementedError();
  @override
  Future<void> dispose() async => disposeCalls++;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> pause() async => pauseCalls++;
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
