import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_playback_adapter.dart';
import 'package:video_player/video_player.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('MEDIA-022 received batch zoom swipe and Back preserve selection', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('astra-viewer-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final pixels = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAgCAIAAAAt/+nTAAAATklEQVR4nO3PUQkAIBTAwNfAfmY3jCH8OITBAtxm7fN1wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjx2AV3NKJdv7voVAAAAAElFTkSuQmCC',
    );
    final first = File('${directory.path}/first.png')..writeAsBytesSync(pixels);
    final second = File('${directory.path}/second.png')
      ..writeAsBytesSync(pixels);
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(second.readAsBytesSync());
      final frame = await codec.getNextFrame();
      expect((frame.image.width, frame.image.height), (64, 32));
      frame.image.dispose();
      codec.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FullScreenImageViewer(
                      localPath: second.path,
                      allPaths: [first.path, second.path, first.path],
                      initialIndex: 1,
                    ),
                  ),
                ),
                child: const Text('Open received batch'),
              ),
            );
          },
        ),
      ),
    );
    // Decode before the route first resolves FileImage in the fake clock.
    await tester.runAsync(() async {
      final context = tester.element(find.text('Open received batch'));
      await precacheImage(
        FileImage(first),
        context,
      ).timeout(const Duration(seconds: 10));
      await precacheImage(
        FileImage(second),
        context,
      ).timeout(const Duration(seconds: 10));
    });
    await tester.tap(find.text('Open received batch'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    final activeViewer = find.byType(InteractiveViewer).hitTestable();
    final visibleImage = find.descendant(
      of: activeViewer,
      matching: find.byType(Image),
    );
    expect(
      (tester.widget<Image>(visibleImage).image as FileImage).file.path,
      second.path,
    );
    final initialBounds = tester.getRect(visibleImage);
    final center = tester.getCenter(activeViewer);
    final left = await tester.startGesture(
      center - const Offset(30, 0),
      pointer: 1,
    );
    final right = await tester.startGesture(
      center + const Offset(30, 0),
      pointer: 2,
    );
    await tester.pump();
    await left.moveTo(center - const Offset(75, 0));
    await right.moveTo(center + const Offset(75, 0));
    await tester.pump();
    expect(
      tester.getRect(visibleImage).width,
      greaterThan(initialBounds.width * 1.2),
    );
    expect(find.text('2 / 3'), findsOneWidget);
    await left.moveTo(center - const Offset(30, 0));
    await right.moveTo(center + const Offset(30, 0));
    await left.up();
    await right.up();
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(600, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    // A viewport change must keep the exact batch item, including when two
    // entries share a path. This extends the existing gesture proof.
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(
      (tester
                  .widget<Image>(
                    find.descendant(
                      of: find.byType(InteractiveViewer).hitTestable(),
                      matching: find.byType(Image),
                    ),
                  )
                  .image
              as FileImage)
          .file
          .path,
      second.path,
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenImageViewer), findsNothing);
    expect(find.text('Open received batch'), findsOneWidget);
  });

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
