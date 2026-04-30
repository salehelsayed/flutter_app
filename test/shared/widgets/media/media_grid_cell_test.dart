import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
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
const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

MediaAttachment _attachment({
  required String id,
  required String mime,
  required String mediaType,
  required String downloadStatus,
  required String localPath,
  int size = 1024,
  String? contentHash,
  bool withEncryption = false,
}) {
  return MediaAttachment(
    id: id,
    messageId: 'msg-1',
    mime: mime,
    size: size,
    mediaType: mediaType,
    localPath: localPath,
    downloadStatus: downloadStatus,
    contentHash: contentHash,
    encryptionKeyBase64: withEncryption ? 'key-$id' : null,
    encryptionNonce: withEncryption ? 'nonce-$id' : null,
    encryptionScheme: withEncryption
        ? kMediaAttachmentEncryptionSchemeBlobAesGcmV1
        : null,
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

  testWidgets(
    'renders GIF attachment through MediaThumbnailImage and shows badge',
    (tester) async {
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
    },
  );

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

  testWidgets('does not show GIF badge while download is pending', (
    tester,
  ) async {
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

  testWidgets('renders failed placeholder for legacy invalid done media', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 120,
          height: 120,
          child: MediaGridCell(
            attachment: _attachment(
              id: 'legacy-svg',
              mime: 'image/svg+xml',
              mediaType: 'image',
              downloadStatus: 'done',
              localPath: jpgFile.path,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MediaThumbnailImage), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('renders failed placeholder for legacy oversized done media', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 120,
          height: 120,
          child: MediaGridCell(
            attachment: _attachment(
              id: 'legacy-oversized',
              mime: 'image/jpeg',
              mediaType: 'image',
              downloadStatus: 'done',
              localPath: jpgFile.path,
              size: kGroupMediaPerAttachmentLimitBytes + 1,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MediaThumbnailImage), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('requires content hash before group media can render or open', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 120,
          height: 120,
          child: MediaGridCell(
            requireVerifiedContentHash: true,
            onTap: () => tapped = true,
            attachment: _attachment(
              id: 'hashless-1',
              mime: 'image/jpeg',
              mediaType: 'image',
              downloadStatus: 'done',
              localPath: jpgFile.path,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MediaThumbnailImage), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);

    await tester.tap(find.byType(MediaGridCell));
    expect(tapped, isFalse);
  });

  testWidgets('integrity-failed group media renders failed placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 120,
          height: 120,
          child: MediaGridCell(
            requireVerifiedContentHash: true,
            attachment: _attachment(
              id: 'integrity-failed-1',
              mime: 'image/jpeg',
              mediaType: 'image',
              downloadStatus: kMediaDownloadStatusIntegrityFailed,
              localPath: jpgFile.path,
              contentHash: _validContentHash,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MediaThumbnailImage), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets(
    'group video thumbnails derive from verified content without remote thumbnail path',
    (tester) async {
      final videoFile = File('${tempDir.path}/clip.mp4')
        ..writeAsBytesSync(const <int>[0, 0, 0, 18, 102, 116, 121, 112]);

      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 120,
            height: 120,
            child: MediaGridCell(
              requireVerifiedContentHash: true,
              attachment: _attachment(
                id: 'video-verified-1',
                mime: 'video/mp4',
                mediaType: 'video',
                downloadStatus: 'done',
                localPath: videoFile.path,
                contentHash: _validContentHash,
                withEncryption: true,
              ),
            ),
          ),
        ),
      );

      final thumbnail = tester.widget<MediaThumbnailImage>(
        find.byType(MediaThumbnailImage),
      );
      expect(thumbnail.mediaPath, videoFile.path);
      expect(thumbnail.thumbnailPath, isNull);
      expect(find.byType(VideoThumbnailOverlay), findsOneWidget);
    },
  );

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

  testWidgets(
    'MD-012 integrity-failed image and video cells render unavailable UI and do not build MediaThumbnailImage',
    (tester) async {
      var retryCount = 0;
      var tapped = false;

      Future<void> pumpCell(MediaAttachment attachment, {bool retry = false}) {
        return tester.pumpWidget(
          wrap(
            SizedBox(
              width: 160,
              height: 160,
              child: MediaGridCell(
                requireVerifiedContentHash: true,
                attachment: attachment,
                onTap: () => tapped = true,
                onRetryUnavailableMedia: retry ? () => retryCount++ : null,
              ),
            ),
          ),
        );
      }

      final cases = [
        _attachment(
          id: 'failed-image',
          mime: 'image/jpeg',
          mediaType: 'image',
          downloadStatus: 'failed',
          localPath: jpgFile.path,
          contentHash: _validContentHash,
          withEncryption: true,
        ),
        _attachment(
          id: 'integrity-video',
          mime: 'video/mp4',
          mediaType: 'video',
          downloadStatus: kMediaDownloadStatusIntegrityFailed,
          localPath: '${tempDir.path}/clip.mp4',
          contentHash: _validContentHash,
          withEncryption: true,
        ),
        _attachment(
          id: 'missing-hash',
          mime: 'image/jpeg',
          mediaType: 'image',
          downloadStatus: 'done',
          localPath: jpgFile.path,
          withEncryption: true,
        ),
        _attachment(
          id: 'missing-encryption',
          mime: 'image/jpeg',
          mediaType: 'image',
          downloadStatus: 'done',
          localPath: jpgFile.path,
          contentHash: _validContentHash,
        ),
      ];

      for (final attachment in cases) {
        tapped = false;
        await pumpCell(attachment);
        await tester.pump();

        expect(find.text('Media unavailable'), findsOneWidget);
        expect(find.byType(MediaThumbnailImage), findsNothing);
        expect(find.byType(VideoThumbnailOverlay), findsNothing);
        expect(find.bySemanticsLabel('Retry unavailable media'), findsNothing);

        await tester.tap(find.byType(MediaGridCell));
        expect(tapped, isFalse);
      }

      await pumpCell(cases.first, retry: true);
      await tester.pump();
      expect(find.bySemanticsLabel('Retry unavailable media'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey('unavailable-media-retry-msg-1-failed-image'),
        ),
      );
      await tester.pump();

      expect(retryCount, 1);
    },
  );
}
