import 'dart:async';
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

  testWidgets(
    'P269 render semantics appears only after a decoded image or thumbnail frame',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          MediaThumbnailImage(
            mediaPath: jpgFile.path,
            mediaType: 'image',
            renderedSemanticsLabel: 'P269 receiver JPEG rendered',
          ),
        ),
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel('P269 receiver JPEG rendered'),
        findsNothing,
      );

      final image = tester.widget<Image>(find.byType(Image));
      final decodedImage = image.frameBuilder!(
        tester.element(find.byType(Image)),
        const SizedBox(),
        0,
        false,
      );
      await tester.pumpWidget(wrap(decodedImage));
      expect(
        find.bySemanticsLabel('P269 receiver JPEG rendered'),
        findsOneWidget,
      );

      final videoFile = File('${tempDir.path}/proof.mp4')
        ..writeAsBytesSync(_tinyMp4Bytes);
      final thumbnailFile = File('${tempDir.path}/proof.jpg')
        ..writeAsBytesSync(_tinyJpgBytes);
      await tester.pumpWidget(
        wrap(
          MediaThumbnailImage(
            mediaPath: videoFile.path,
            mediaType: 'video',
            placeholder: const Text('video fallback'),
            renderedSemanticsLabel: 'P269 receiver MP4 rendered',
            videoThumbnailResolver: (_) async => thumbnailFile.path,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final videoImage = tester.widget<Image>(find.byType(Image));
      final decodedVideoThumbnail = videoImage.frameBuilder!(
        tester.element(find.byType(Image)),
        const SizedBox(),
        0,
        false,
      );
      await tester.pumpWidget(wrap(decodedVideoThumbnail));
      expect(
        find.bySemanticsLabel('P269 receiver MP4 rendered'),
        findsOneWidget,
      );

      await tester.pumpWidget(
        wrap(
          MediaThumbnailImage(
            mediaPath: videoFile.path,
            mediaType: 'video',
            placeholder: const Text('video fallback'),
            renderedSemanticsLabel: 'P269 fallback MP4 rendered',
            videoThumbnailResolver: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('P269 fallback MP4 rendered'), findsNothing);

      await tester.pumpWidget(
        wrap(
          MediaThumbnailImage(
            mediaPath: '${tempDir.path}/missing-proof.mp4',
            mediaType: 'video',
            placeholder: const Text('video fallback'),
            error: const Text('video unavailable'),
            renderedSemanticsLabel: 'P269 missing MP4 rendered',
            videoThumbnailResolver: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('P269 missing MP4 rendered'), findsNothing);
      semantics.dispose();
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

  testWidgets('117: undecodable image (non-video) still shows error', (
    tester,
  ) async {
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
  });

  // 143: The real Image.file decode runs async I/O that does not complete in
  // the testWidgets fake-async zone (same constraint the errorBuilder tests
  // above call out). So we assert the decode-LOADING state deterministically
  // by invoking the built Image's `frameBuilder` directly — exactly how the
  // tests above invoke `errorBuilder`. While the first frame is undecoded the
  // builder must return the supplied placeholder, never a transparent box.
  testWidgets(
    'image shows the supplied placeholder while the first frame is undecoded '
    '(frame == null)',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          MediaThumbnailImage(
            mediaPath: jpgFile.path,
            mediaType: 'image',
            placeholder: const SizedBox(key: Key('ph-sentinel')),
          ),
        ),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.frameBuilder,
        isNotNull,
        reason:
            '_buildImage must supply a frameBuilder so the decode gap renders '
            'the sized placeholder instead of a transparent/empty box.',
      );

      final ctx = tester.element(find.byType(Image));
      final built = image.frameBuilder!(
        ctx,
        const SizedBox(key: Key('child')),
        null, // first frame not yet decoded
        false, // not synchronously loaded
      );
      expect(
        built.key,
        const Key('ph-sentinel'),
        reason: 'undecoded image must show the placeholder, not the child',
      );
      expect(built.key, isNot(const Key('child')));
    },
  );

  testWidgets(
    'image shows the decoded child once a frame is available or synchronously '
    'loaded',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          MediaThumbnailImage(
            mediaPath: jpgFile.path,
            mediaType: 'image',
            placeholder: const SizedBox(key: Key('ph-sentinel')),
          ),
        ),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      final ctx = tester.element(find.byType(Image));
      const child = SizedBox(key: Key('child'));

      // A decoded frame (frame != null) shows the image child.
      final decoded = image.frameBuilder!(ctx, child, 0, false);
      expect(decoded.key, const Key('child'));

      // A synchronously-loaded image (frame == null but wasSynchronouslyLoaded)
      // also shows the child immediately — no placeholder flash.
      final synchronous = image.frameBuilder!(ctx, child, null, true);
      expect(synchronous.key, const Key('child'));
    },
  );

  testWidgets('null placeholder falls back to SizedBox.shrink (no crash)', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MediaThumbnailImage(
          mediaPath: jpgFile.path,
          mediaType: 'image',
          // no placeholder supplied
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    final ctx = tester.element(find.byType(Image));
    final built = image.frameBuilder!(
      ctx,
      const SizedBox(key: Key('child')),
      null,
      false,
    );
    expect(built, isA<SizedBox>());
    expect(built.key, isNot(const Key('child')));
    final box = built as SizedBox;
    expect(box.width, 0, reason: 'must degrade to SizedBox.shrink');
    expect(box.height, 0);
  });

  testWidgets(
    'video thumbnail path unchanged (FutureBuilder placeholder while resolving)',
    (tester) async {
      // A never-completing resolver pins the video branch in
      // ConnectionState.waiting. The FutureBuilder must keep showing the
      // placeholder and build NO Image yet — the _buildImage frameBuilder edit
      // must not perturb the video waiting state.
      final pending = Completer<String?>();
      final videoFile = File('${tempDir.path}/waiting.mp4')
        ..writeAsBytesSync(_tinyMp4Bytes);

      await tester.pumpWidget(
        wrap(
          MediaThumbnailImage(
            mediaPath: videoFile.path,
            mediaType: 'video',
            placeholder: const SizedBox(key: Key('video-ph')),
            videoThumbnailResolver: (_) => pending.future,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('video-ph')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets(
    'resolved video thumbnail also gets the decode placeholder (frameBuilder is '
    'not image-only)',
    (tester) async {
      // The resolved-video-thumbnail path flows through _buildImage too (build()
      // calls _buildImage(thumbnailPath) once the resolver completes), so the
      // frameBuilder must apply there as well — a future change that scoped it
      // to mediaType=='image' only would flash a transparent box during
      // thumbnail decode. Lock it by driving frameBuilder on a video widget.
      final videoFile = File('${tempDir.path}/clip-thumb.mp4')
        ..writeAsBytesSync(_tinyMp4Bytes);
      final thumb = File('${tempDir.path}/clip-thumb.jpg')
        ..writeAsBytesSync(_tinyJpgBytes);

      await tester.pumpWidget(
        wrap(
          MediaThumbnailImage(
            mediaPath: videoFile.path,
            mediaType: 'video',
            placeholder: const SizedBox(key: Key('video-ph')),
            videoThumbnailResolver: (_) async => thumb.path,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.frameBuilder, isNotNull);

      final ctx = tester.element(find.byType(Image));
      final built = image.frameBuilder!(
        ctx,
        const SizedBox(key: Key('child')),
        null,
        false,
      );
      expect(built.key, const Key('video-ph'));
    },
  );
}
