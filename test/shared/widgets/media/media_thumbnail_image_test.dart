import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';

const _tinyGifBytes = <int>[
  0x47,
  0x49,
  0x46,
  0x38,
  0x39,
  0x61,
  0x01,
  0x00,
  0x01,
  0x00,
  0x80,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0xFF,
  0xFF,
  0xFF,
  0x21,
  0xF9,
  0x04,
  0x01,
  0x00,
  0x00,
  0x00,
  0x00,
  0x2C,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0x02,
  0x02,
  0x44,
  0x01,
  0x00,
  0x3B,
];

const _tinyJpgBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0];
const _tinyMp4Bytes = <int>[0, 0, 0, 18, 102, 116, 121, 112];

void main() {
  late Directory tempDir;
  late File gifFile;
  late File jpgFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_thumb_test_');
    gifFile = File('${tempDir.path}/funny.gif')
      ..writeAsBytesSync(_tinyGifBytes);
    jpgFile = File('${tempDir.path}/photo.jpg')
      ..writeAsBytesSync(_tinyJpgBytes);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('ignores cacheWidth/cacheHeight for GIF paths', (tester) async {
    await tester.pumpWidget(
      wrap(
        MediaThumbnailImage(
          mediaPath: gifFile.path,
          mediaType: 'image',
          cacheWidth: 400,
          cacheHeight: 400,
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FileImage>());
  });

  testWidgets('retains cacheWidth/cacheHeight for JPEG paths', (tester) async {
    await tester.pumpWidget(
      wrap(
        MediaThumbnailImage(
          mediaPath: jpgFile.path,
          mediaType: 'image',
          cacheWidth: 400,
          cacheHeight: 400,
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    expect(provider.width, 400);
    expect(provider.height, 400);
  });

  testWidgets(
    'uses placeholder when video thumbnail is null but source exists',
    (tester) async {
      final videoFile = File('${tempDir.path}/clip.mp4')
        ..writeAsBytesSync(_tinyMp4Bytes);

      await tester.pumpWidget(
        wrap(
          MediaThumbnailImage(
            mediaPath: videoFile.path,
            mediaType: 'video',
            placeholder: const Text('video fallback'),
            error: const Text('video unavailable'),
            videoThumbnailResolver: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('video fallback'), findsOneWidget);
      expect(find.text('video unavailable'), findsNothing);
    },
  );

  testWidgets('uses error when video thumbnail is null and source is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MediaThumbnailImage(
          mediaPath: '${tempDir.path}/missing.mp4',
          mediaType: 'video',
          placeholder: const Text('video fallback'),
          error: const Text('video unavailable'),
          videoThumbnailResolver: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('video fallback'), findsNothing);
    expect(find.text('video unavailable'), findsOneWidget);
  });

  // The Image.file decode path does real async I/O that does not complete in
  // the testWidgets fake-async zone, so we drive the decode-failure branch
  // deterministically by invoking the built Image's errorBuilder directly and
  // rendering its result.
  Widget renderErrorBuilder(WidgetTester tester) {
    final image = tester.widget<Image>(find.byType(Image));
    return image.errorBuilder!(
      tester.element(find.byType(Image)),
      Exception('decode failed'),
      StackTrace.empty,
    );
  }

  testWidgets(
    '117: undecodable thumbnail for a present video falls back to placeholder',
    (tester) async {
      // The video source is intact and playable, but the derived thumbnail
      // JPG is present-but-corrupt (decode fails). This must NOT collapse to
      // the "unavailable" error widget — the video is still openable.
      final videoFile = File('${tempDir.path}/intact.mp4')
        ..writeAsBytesSync(_tinyMp4Bytes);
      final corruptThumb = File('${tempDir.path}/intact.thumb.jpg')
        ..writeAsBytesSync(const [1, 2, 3, 4, 5, 6, 7, 8]);

      await tester.pumpWidget(
        wrap(
          MediaThumbnailImage(
            mediaPath: videoFile.path,
            mediaType: 'video',
            placeholder: const Text('video fallback'),
            error: const Text('video unavailable'),
            videoThumbnailResolver: (_) async => corruptThumb.path,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final errorWidget = renderErrorBuilder(tester);
      await tester.pumpWidget(wrap(errorWidget));
      await tester.pumpAndSettle();

      expect(find.text('video fallback'), findsOneWidget);
      expect(find.text('video unavailable'), findsNothing);
    },
  );

  testWidgets(
    '117: undecodable image (non-video) still shows error',
    (tester) async {
      // A genuinely-corrupt image (not a video) SHOULD still surface the
      // error widget — the placeholder fallback is video-specific.
      final corruptImage = File('${tempDir.path}/corrupt.jpg')
        ..writeAsBytesSync(const [1, 2, 3, 4, 5, 6, 7, 8]);

      await tester.pumpWidget(
        wrap(
          MediaThumbnailImage(
            mediaPath: corruptImage.path,
            mediaType: 'image',
            placeholder: const Text('image fallback'),
            error: const Text('image unavailable'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final errorWidget = renderErrorBuilder(tester);
      await tester.pumpWidget(wrap(errorWidget));
      await tester.pumpAndSettle();

      expect(find.text('image unavailable'), findsOneWidget);
      expect(find.text('image fallback'), findsNothing);
    },
  );
}
