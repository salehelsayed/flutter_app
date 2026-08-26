import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_playback_adapter.dart';
import 'package:video_player/video_player.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets(
    'production video factory receives notification-safe playback options',
    (tester) async {
      const videoPath = '/tmp/notification-safe.mp4';
      File? capturedFile;
      VideoPlayerOptions? capturedOptions;

      await tester.pumpWidget(
        wrap(
          FullScreenImageViewer(
            localPath: videoPath,
            videoPlayerControllerFactory: (file, options) {
              capturedFile = file;
              capturedOptions = options;
              return _NoopVideoPlayerController();
            },
          ),
        ),
      );
      await tester.pump();

      expect(capturedFile?.path, videoPath);
      expect(
        capturedOptions?.mixWithOthers,
        userInitiatedMediaVideoPlayerOptions().mixWithOthers,
      );
      expect(capturedOptions?.allowBackgroundPlayback, isFalse);
    },
  );

  testWidgets('uses the video page builder for video paths', (tester) async {
    const videoPath = '/tmp/sample.mp4';

    await tester.pumpWidget(
      wrap(
        FullScreenImageViewer(
          localPath: videoPath,
          videoPageBuilder: (path, isActive) => Container(
            key: ValueKey('video-page-$path'),
            child: Text(isActive ? 'active-video' : 'inactive-video'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('video-page-/tmp/sample.mp4')),
      findsOneWidget,
    );
    expect(find.text('active-video'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('uses the image viewer branch for image paths', (tester) async {
    const imagePath = '/tmp/sample.jpg';

    await tester.pumpWidget(
      wrap(const FullScreenImageViewer(localPath: imagePath)),
    );
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('renders GIF paths without ResizeImage cache hints', (
    tester,
  ) async {
    const gifPath = '/tmp/sample.gif';

    await tester.pumpWidget(
      wrap(const FullScreenImageViewer(localPath: gifPath)),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isNot(isA<ResizeImage>()));
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('swipes between GIF and JPEG pages', (tester) async {
    const gifPath = '/tmp/sample.gif';
    const jpgPath = '/tmp/sample.jpg';

    await tester.pumpWidget(
      wrap(
        const FullScreenImageViewer(
          localPath: gifPath,
          allPaths: [gifPath, jpgPath],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1 / 2'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
  });
}

class _NoopVideoPlayerController extends VideoPlayerController {
  _NoopVideoPlayerController()
    : super.networkUrl(Uri.parse('https://example.invalid/noop.mp4'));

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}
}
