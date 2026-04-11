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

void main() {
  late Directory tempDir;
  late File gifFile;
  late File jpgFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_thumb_test_');
    gifFile = File('${tempDir.path}/funny.gif')..writeAsBytesSync(_tinyGifBytes);
    jpgFile = File('${tempDir.path}/photo.jpg')..writeAsBytesSync(_tinyJpgBytes);
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
}
