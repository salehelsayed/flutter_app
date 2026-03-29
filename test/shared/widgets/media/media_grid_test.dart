import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/video_thumbnail_cache.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

final Uint8List _tinyPng = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xDE,
  0x00,
  0x00,
  0x00,
  0x0C,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xD7,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x00,
  0x02,
  0x00,
  0x01,
  0xE2,
  0x21,
  0xBC,
  0x33,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

MediaAttachment _makeMedia(int i) {
  return MediaAttachment(
    id: 'media-$i',
    messageId: 'msg-1',
    mime: 'image/jpeg',
    size: 1024,
    mediaType: 'image',
    downloadStatus: 'done',
    createdAt: '2024-01-01T00:00:00Z',
  );
}

MediaAttachment _makeVideoMedia(String videoPath) {
  return MediaAttachment(
    id: 'video-1',
    messageId: 'msg-1',
    mime: 'video/mp4',
    size: 2048,
    mediaType: 'video',
    localPath: videoPath,
    downloadStatus: 'done',
    createdAt: '2024-01-01T00:00:00Z',
  );
}

void main() {
  late Directory tempDir;
  late String videoPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_grid_test_');
    videoPath = '${tempDir.path}/clip.mp4';
    await File(videoPath).writeAsBytes(const [0x00, 0x00, 0x00, 0x18]);
    await File(derivedVideoThumbnailPath(videoPath)).writeAsBytes(_tinyPng);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('MediaGrid', () {
    testWidgets('renders single item with 4:3 AspectRatio', (tester) async {
      await tester.pumpWidget(wrap(MediaGrid(media: [_makeMedia(0)])));
      expect(find.byType(AspectRatio), findsOneWidget);
      final ar = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(ar.aspectRatio, closeTo(4 / 3, 0.01));
    });

    testWidgets('renders 2 items side by side', (tester) async {
      await tester.pumpWidget(
        wrap(MediaGrid(media: [_makeMedia(0), _makeMedia(1)])),
      );
      // 2 items each with 1:1 aspect ratio
      final aspects = tester.widgetList<AspectRatio>(find.byType(AspectRatio));
      expect(aspects.length, 2);
    });

    testWidgets('renders ClipRRect container', (tester) async {
      await tester.pumpWidget(wrap(MediaGrid(media: [_makeMedia(0)])));
      expect(find.byType(ClipRRect), findsWidgets);
    });

    testWidgets('renders empty SizedBox when media is empty', (tester) async {
      await tester.pumpWidget(wrap(const MediaGrid(media: [])));
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets(
      'renders generated thumbnail for downloaded video attachments',
      (tester) async {
        await tester.pumpWidget(
          wrap(MediaGrid(media: [_makeVideoMedia(videoPath)])),
        );
        await tester.pump();

        expect(find.byType(MediaThumbnailImage), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      },
    );
  });
}
