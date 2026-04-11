import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';
import 'package:flutter_app/shared/widgets/media/video_thumbnail_overlay.dart';

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

MediaAttachment _attachment({
  required String id,
  required String mime,
  required String mediaType,
  required String downloadStatus,
  required String localPath,
}) {
  return MediaAttachment(
    id: id,
    messageId: 'msg-1',
    mime: mime,
    size: 1024,
    mediaType: mediaType,
    localPath: localPath,
    downloadStatus: downloadStatus,
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}

void main() {
  late Directory tempDir;
  late File gifFile;
  late File jpgFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_grid_cell_');
    gifFile = File('${tempDir.path}/cell.gif')..writeAsBytesSync(_tinyGifBytes);
    jpgFile = File('${tempDir.path}/cell.jpg')..writeAsBytesSync(_tinyJpgBytes);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders GIF attachment through MediaThumbnailImage and shows badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 120,
          height: 120,
          child: MediaGridCell(
            attachment: _attachment(
              id: 'gif-1',
              mime: 'image/gif',
              mediaType: 'image',
              downloadStatus: 'done',
              localPath: gifFile.path,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MediaThumbnailImage), findsOneWidget);
    expect(find.text('GIF'), findsOneWidget);
    expect(find.byType(VideoThumbnailOverlay), findsNothing);
  });

  testWidgets('does not show GIF badge for JPEG attachments', (tester) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 120,
          height: 120,
          child: MediaGridCell(
            attachment: _attachment(
              id: 'jpg-1',
              mime: 'image/jpeg',
              mediaType: 'image',
              downloadStatus: 'done',
              localPath: jpgFile.path,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('GIF'), findsNothing);
  });

  testWidgets('does not show GIF badge while download is pending', (tester) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 120,
          height: 120,
          child: MediaGridCell(
            attachment: _attachment(
              id: 'gif-pending',
              mime: 'image/gif',
              mediaType: 'image',
              downloadStatus: 'pending',
              localPath: gifFile.path,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('GIF'), findsNothing);
  });

  testWidgets('tapping a GIF cell fires onTap', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 120,
          height: 120,
          child: MediaGridCell(
            attachment: _attachment(
              id: 'gif-tap',
              mime: 'image/gif',
              mediaType: 'image',
              downloadStatus: 'done',
              localPath: gifFile.path,
            ),
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(MediaGridCell));
    expect(tapped, isTrue);
  });
}
