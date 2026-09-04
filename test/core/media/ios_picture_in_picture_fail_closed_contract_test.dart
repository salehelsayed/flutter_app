import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_picture_in_picture_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_video_resume_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_app/shared/widgets/media/media_playback_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Path 3 keeps iOS PiP hidden unsupported and native-owner free', (
    tester,
  ) async {
    var channelCalls = 0;
    var authorizationLoads = 0;
    final gateway = PictureInPictureChannelGateway(
      platform: PictureInPictureHostPlatform.iOS,
      invokeMethod: (_, _) async {
        channelCalls++;
        throw StateError('iOS must not invoke the PiP method channel');
      },
      nativeEvents: const Stream<Object?>.empty(),
    );
    final playback = _IosNegativePlayback()..playing = true;
    final store = _IosNegativeResumeStore();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FullScreenTypedMediaViewer(
          items: const [
            MediaViewerItem(
              attachmentId: 'ios-hidden-video',
              messageId: 'ios-hidden-message',
              kind: MediaViewerKind.video,
              mime: 'video/mp4',
              owner: MediaOwnerLane.direct,
              localPath: '/app/Documents/media/ios-hidden-video.mp4',
              durationMs: 9000,
              canEnterPictureInPicture: true,
            ),
          ],
          playbackAdapterFactory: (_) => playback,
          resumeStore: store,
          pictureInPictureControllerFactory:
              ({required reloadCurrent, required restorePlayback}) =>
                  MediaPictureInPictureController(
                    gateway: gateway,
                    pathAuthority: _IosNegativePathAuthority(),
                    reloadCurrent: reloadCurrent,
                    resumeStore: store,
                    restorePlayback: restorePlayback,
                    pollTicks: const Stream<void>.empty(),
                  ),
          loadPictureInPictureAuthorization: (item) async {
            authorizationLoads++;
            return MediaPictureInPictureAuthorization(
              item: item,
              generation: 1,
              policyState: MediaPictureInPicturePolicyState.ordinary,
              isIncoming: true,
              isTransferComplete: true,
              routeActive: true,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('media_action_picture_in_picture')),
      findsNothing,
    );
    expect(find.byTooltip('Picture in Picture'), findsNothing);
    expect(authorizationLoads, 0, reason: 'platform fails closed first');
    expect(channelCalls, 0);
    expect(playback.pauseCalls, 0);
    expect(playback.disposeCalls, 0);
    expect(playback.isPlaying, isTrue);

    expect(
      await gateway.start(
        const PictureInPictureRequest(
          session: 'ios-session',
          attachment: 'ios-hidden-video',
          path: '/app/Documents/media/ios-hidden-video.mp4',
          positionMs: 0,
          durationMs: 9000,
        ),
      ),
      PictureInPictureStartOutcome.unsupportedPlatform,
    );
    expect(channelCalls, 0);

    final iosSource = <String>[
      for (final root in <String>[
        'ios/Runner',
        'ios/RunnerTests',
        'ios/RunnerUITests',
      ])
        for (final entity in Directory(root).listSync(recursive: true))
          if (entity is File &&
              (entity.path.endsWith('.swift') ||
                  entity.path.endsWith('.m') ||
                  entity.path.endsWith('.h')))
            entity.readAsStringSync(),
    ].join('\n');
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    for (final forbidden in <String>[
      'AVPictureInPictureController',
      'AVKit',
      'mknoon/picture_in_picture',
      'ReceivedVideoPictureInPicture',
    ]) {
      expect(iosSource, isNot(contains(forbidden)));
      expect(project, isNot(contains(forbidden)));
    }
    // UIBackgroundModes.audio is shared by the supported CallKit/WebRTC call
    // path, so it is not evidence that the unsupported iOS PiP path exists.
  });
}

class _IosNegativePathAuthority implements AppOwnedMediaPathAuthority {
  @override
  Future<String?> authorize(String? candidatePath) async => candidatePath;
}

class _IosNegativeResumeStore implements MediaViewerResumeStore {
  @override
  Future<int?> readResumePosition(MediaViewerItem item) async => null;

  @override
  Future<void> writeResumePosition(
    MediaViewerItem item,
    int positionMs,
  ) async {}
}

class _IosNegativePlayback extends MediaPlaybackAdapter {
  bool initialized = false;
  bool playing = false;
  int pauseCalls = 0;
  int disposeCalls = 0;

  @override
  double get aspectRatio => 1;

  @override
  Duration get duration => const Duration(milliseconds: 9000);

  @override
  Object? get initializationError => null;

  @override
  bool get isCompleted => false;

  @override
  bool get isInitialized => initialized;

  @override
  bool get isMuted => false;

  @override
  bool get isPlaying => playing;

  @override
  Duration get position => const Duration(milliseconds: 1000);

  @override
  double get speed => 1;

  @override
  void addListener(VoidCallback listener) {}

  @override
  Widget buildSurface() => const SizedBox();

  @override
  Future<void> dispose() async => disposeCalls++;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing = false;
  }

  @override
  Future<void> play() async => playing = true;

  @override
  void removeListener(VoidCallback listener) {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> setSpeed(double speed) async {}
}
