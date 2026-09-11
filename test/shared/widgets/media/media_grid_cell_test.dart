import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
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
// A real, decodable 1x1 PNG so the render-boundary test doesn't trip the
// thumbnail decode-error fallback (which itself shows "Media unavailable").
const _validPngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82, //
];
const _tinyMp4Bytes = <int>[0, 0, 0, 18, 102, 116, 121, 112];
const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

MediaAttachment _attachment({
  required String id,
  required String mime,
  required String mediaType,
  required String downloadStatus,
  required String? localPath,
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

  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets(
    '127 round-3: own-sent media with a RELATIVE localPath renders (resolved at '
    'the render gate, not via the producer)',
    (tester) async {
      // The DB persists a relative path; the render gate must resolve it
      // against the seeded documents dir. This is the durable fix — independent
      // of whichever upstream path fed the message.
      const peer = '12D3KooWPeerX';
      const blob = '70579635-999f-468a-b3e9-b07d4c698341';
      final relativePath = 'media/$peer/$blob.jpg';
      File('${tempDir.path}/$relativePath')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_validPngBytes);
      MediaFileManager.cacheDocumentsDir(tempDir.path);

      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 200,
            height: 200,
            child: MediaGridCell(
              attachment: _attachment(
                id: blob,
                mime: 'image/jpeg',
                mediaType: 'image',
                downloadStatus: 'done',
                localPath: relativePath, // RELATIVE, as persisted in the DB
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Gate resolved the relative path -> file found -> displayable thumbnail,
      // NOT the "Media unavailable" placeholder.
      expect(find.byType(MediaThumbnailImage), findsOneWidget);
      expect(find.text('Media unavailable'), findsNothing);
    },
  );

  testWidgets(
    '128 round-5: stale display path falls back to the durable owned copy '
    '(replicates the device repro: pending path deleted, owned copy present)',
    (tester) async {
      MediaGridCell.debugResetUnavailableDiagnostics();
      MediaFileManager.cacheDocumentsDir(tempDir.path);
      const peer = '12D3KooWBob';
      const blob = '19a57608-0afc-4c5a-a88f-f9d425016a2e';
      // The durable owned copy EXISTS (what the upload actually committed).
      File('${tempDir.path}/media/$peer/$blob.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_validPngBytes);
      // The displayed attachment still holds the DELETED optimistic
      // pending_uploads ABSOLUTE path (never swapped for the durable copy) —
      // exactly what the device diagnostic showed.
      final stalePending = '${tempDir.path}/pending_uploads/msg-1/$blob.jpg';
      expect(File(stalePending).existsSync(), isFalse);

      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 200,
            height: 200,
            child: MediaGridCell(
              attachment: _attachment(
                id: blob,
                mime: 'image/jpeg',
                mediaType: 'image',
                downloadStatus: 'done',
                localPath: stalePending,
              ),
              ownedMediaPeerId: peer,
            ),
          ),
        ),
      );
      await tester.pump();

      // Render gate falls back to media/<peer>/<blob>.jpg -> displayable.
      expect(find.byType(MediaThumbnailImage), findsOneWidget);
      expect(find.text('Media unavailable'), findsNothing);
    },
  );

  testWidgets(
    '128: a done image whose path does not exist emits the gate diagnostic',
    (tester) async {
      MediaGridCell.debugResetUnavailableDiagnostics();
      MediaFileManager.cacheDocumentsDir(tempDir.path);
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));

      // A deleted optimistic pending_uploads ABSOLUTE path — the stale-path
      // hazard the diagnostic must surface (resolver passes it through; gone).
      final stalePath = '${tempDir.path}/pending_uploads/msg-1/att.jpg';
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 200,
            height: 200,
            child: MediaGridCell(
              attachment: _attachment(
                id: 'diag-1',
                mime: 'image/jpeg',
                mediaType: 'image',
                downloadStatus: 'done',
                localPath: stalePath,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Media unavailable'), findsOneWidget);
      final diag = events
          .where((e) => e['event'] == 'MEDIA_RENDER_GATE_UNAVAILABLE')
          .toList();
      expect(diag, hasLength(1));
      final details = diag.single['details'] as Map<String, dynamic>;
      expect(details['existsAtResolved'], isFalse);
      expect(details['rawLocalPathKind'], 'pending-uploads-abs');
      expect(details['cacheSeeded'], isTrue);
      expect(details['downloadStatus'], 'done');
    },
  );

  testWidgets(
    '128 round-5 (group): verified group media with a stale display path falls '
    'back to the durable owned copy keyed under media/<groupId>',
    (tester) async {
      // Group parity for the sender "Media unavailable" fix. Group durable media
      // is keyed under media/<groupId>/<blob> (group_conversation_wired uses
      // relativePathForAttachment(contactPeerId: widget.group.id)). The displayed
      // attachment holds the deleted optimistic pending path; the verified-hash
      // gate is ON. The render gate must fall back to the owned copy AND still
      // honor verification (valid hash + encryption metadata supplied here).
      MediaGridCell.debugResetUnavailableDiagnostics();
      MediaFileManager.cacheDocumentsDir(tempDir.path);
      const groupId = 'group-abc123';
      const blob = '5984e08d-1a2b-4c3d-8e9f-0a1b2c3d4e5f';
      // The durable owned copy EXISTS under the group dir (what upload committed).
      File('${tempDir.path}/media/$groupId/$blob.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_validPngBytes);
      // Displayed attachment still carries the DELETED optimistic pending path.
      final stalePending = '${tempDir.path}/pending_uploads/msg-1/$blob.jpg';
      expect(File(stalePending).existsSync(), isFalse);

      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 200,
            height: 200,
            child: MediaGridCell(
              requireVerifiedContentHash: true,
              attachment: _attachment(
                id: blob,
                mime: 'image/jpeg',
                mediaType: 'image',
                downloadStatus: 'done',
                localPath: stalePending,
                contentHash: _validContentHash,
                withEncryption: true,
              ),
              ownedMediaPeerId: groupId,
            ),
          ),
        ),
      );
      await tester.pump();

      // Fallback to media/<groupId>/<blob>.jpg -> displayable verified thumbnail.
      expect(find.byType(MediaThumbnailImage), findsOneWidget);
      expect(find.text('Media unavailable'), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    },
  );

  testWidgets(
    '128 round-5 (group): WITHOUT ownedMediaPeerId the stale path stays '
    'unavailable (fallback is required; verification is never bypassed)',
    (tester) async {
      // Mutation-style guard: the SAME verified attachment + present owned copy,
      // but no ownedMediaPeerId wired -> the gate cannot find the file and must
      // render unavailable. Locks in that the owned-copy fallback is what fixes
      // this, and proves the fallback never short-circuits the missing-file gate.
      MediaGridCell.debugResetUnavailableDiagnostics();
      MediaFileManager.cacheDocumentsDir(tempDir.path);
      const groupId = 'group-abc123';
      const blob = '6a1c0bb2-7d8e-4f90-a1b2-c3d4e5f60718';
      File('${tempDir.path}/media/$groupId/$blob.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_validPngBytes);
      final stalePending = '${tempDir.path}/pending_uploads/msg-1/$blob.jpg';

      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 200,
            height: 200,
            child: MediaGridCell(
              requireVerifiedContentHash: true,
              attachment: _attachment(
                id: blob,
                mime: 'image/jpeg',
                mediaType: 'image',
                downloadStatus: 'done',
                localPath: stalePending,
                contentHash: _validContentHash,
                withEncryption: true,
              ),
              // ownedMediaPeerId intentionally omitted.
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(MediaThumbnailImage), findsNothing);
      expect(find.text('Media unavailable'), findsOneWidget);
    },
  );

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

  testWidgets('renders upload_pending media as waiting without an active spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 180,
          height: 180,
          child: MediaGridCell(
            attachment: _attachment(
              id: 'pending-upload',
              mime: 'image/jpeg',
              mediaType: 'image',
              downloadStatus: 'upload_pending',
              localPath: jpgFile.path,
              size: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Media pending upload'), findsOneWidget);
    expect(find.text('Uploading media'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(
      find.text('Recipients will receive this after the upload finishes.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
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
              // The group MIME allow-list gate only applies to verified group
              // rendering (117 Session 2). Assert the disallowed-mime gate in
              // that context (valid hash + encryption isolate it to the mime).
              contentHash: _validContentHash,
              withEncryption: true,
            ),
            requireVerifiedContentHash: true,
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
              // The group MIME/size gate only applies to verified group
              // rendering (117 Session 2). Assert it in that context.
              contentHash: _validContentHash,
              withEncryption: true,
            ),
            requireVerifiedContentHash: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MediaThumbnailImage), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets(
    '1:1 cell renders present done media with a non-allowlisted mime',
    (tester) async {
      // 117 Session 2: a 1:1 video whose real mime is the re-encode-fallback
      // container (video/x-matroska, outside the group allow-list) must still
      // render and open — the group MIME allow-list must not gate 1:1.
      final videoFile = File('${tempDir.path}/fallback-1to1.mkv')
        ..writeAsBytesSync(_tinyMp4Bytes);
      var tapped = false;

      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 120,
            height: 120,
            child: MediaGridCell(
              attachment: _attachment(
                id: 'fallback-1to1',
                mime: 'video/x-matroska',
                mediaType: 'video',
                downloadStatus: 'done',
                localPath: videoFile.path,
              ),
              onTap: () => tapped = true,
              videoThumbnailResolver: (_) async => null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Media unavailable'), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(find.byType(MediaThumbnailImage), findsOneWidget);
      expect(find.byType(VideoThumbnailOverlay), findsOneWidget);

      await tester.tap(find.byType(MediaGridCell));
      expect(tapped, isTrue);
    },
  );

  testWidgets(
    'group cell still gates a non-allowlisted mime (behavior preserved)',
    (tester) async {
      // Same non-allowlisted mime, but in verified group context the strict
      // allow-list gate must remain — even with valid hash + encryption
      // metadata, the disallowed mime keeps it unavailable.
      final videoFile = File('${tempDir.path}/fallback-group.mkv')
        ..writeAsBytesSync(_tinyMp4Bytes);

      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 120,
            height: 120,
            child: MediaGridCell(
              attachment: _attachment(
                id: 'fallback-group',
                mime: 'video/x-matroska',
                mediaType: 'video',
                downloadStatus: 'done',
                localPath: videoFile.path,
                contentHash: _validContentHash,
                withEncryption: true,
              ),
              requireVerifiedContentHash: true,
              onTap: () {},
              videoThumbnailResolver: (_) async => null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Media unavailable'), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.byType(MediaThumbnailImage), findsNothing);
    },
  );

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
        ..writeAsBytesSync(_tinyMp4Bytes);

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

  testWidgets('video thumbnail failure shows video fallback, not unavailable', (
    tester,
  ) async {
    final videoFile = File('${tempDir.path}/thumbnail-failure.mp4')
      ..writeAsBytesSync(_tinyMp4Bytes);
    var tapped = false;
    var retryCount = 0;

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 120,
          height: 120,
          child: MediaGridCell(
            attachment: _attachment(
              id: 'video-thumbnail-failure',
              mime: 'video/mp4',
              mediaType: 'video',
              downloadStatus: 'done',
              localPath: videoFile.path,
            ),
            onTap: () => tapped = true,
            onRetryUnavailableMedia: () => retryCount++,
            videoThumbnailResolver: (_) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MediaThumbnailImage), findsOneWidget);
    expect(find.byType(VideoThumbnailOverlay), findsOneWidget);
    expect(find.text('Media unavailable'), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    expect(find.bySemanticsLabel('Retry unavailable media'), findsNothing);

    await tester.tap(find.byType(MediaGridCell));
    expect(tapped, isTrue);
    expect(retryCount, 0);
  });

  testWidgets(
    '117: done video with undecodable thumbnail renders playable, not '
    'unavailable',
    (tester) async {
      // A downloaded, intact, playable video whose derived thumbnail JPG is
      // present-but-corrupt must render the video fallback + play overlay and
      // stay tappable — never the "Media unavailable" broken-image placeholder.
      final videoFile = File('${tempDir.path}/decode-failure.mp4')
        ..writeAsBytesSync(_tinyMp4Bytes);
      final corruptThumb = File('${tempDir.path}/decode-failure.thumb.jpg')
        ..writeAsBytesSync(const [1, 2, 3, 4, 5, 6, 7, 8]);
      var tapped = false;
      var retryCount = 0;

      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 120,
            height: 120,
            child: MediaGridCell(
              attachment: _attachment(
                id: 'video-decode-failure',
                mime: 'video/mp4',
                mediaType: 'video',
                downloadStatus: 'done',
                localPath: videoFile.path,
              ),
              onTap: () => tapped = true,
              onRetryUnavailableMedia: () => retryCount++,
              videoThumbnailResolver: (_) async => corruptThumb.path,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The cell does not short-circuit a present, done video to unavailable.
      expect(find.byType(MediaThumbnailImage), findsOneWidget);
      expect(find.byType(VideoThumbnailOverlay), findsOneWidget);
      expect(find.text('Media unavailable'), findsNothing);

      // Drive the thumbnail-decode failure deterministically through the inner
      // Image's errorBuilder (real Image.file decode does not run under
      // testWidgets). The wired `error` widget is the "Media unavailable"
      // placeholder; the fix must instead render the benign video placeholder.
      final image = tester.widget<Image>(find.byType(Image));
      final errorWidget = image.errorBuilder!(
        tester.element(find.byType(Image)),
        Exception('decode failed'),
        StackTrace.empty,
      );
      await tester.pumpWidget(
        wrap(SizedBox(width: 120, height: 120, child: errorWidget)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Media unavailable'), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(find.bySemanticsLabel('Retry unavailable media'), findsNothing);

      expect(tapped, isFalse);
      expect(retryCount, 0);
    },
  );

  testWidgets('failed video media still shows unavailable retry', (
    tester,
  ) async {
    final videoFile = File('${tempDir.path}/failed-video.mp4')
      ..writeAsBytesSync(_tinyMp4Bytes);
    var retryCount = 0;
    var tapped = false;

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 160,
          height: 160,
          child: MediaGridCell(
            attachment: _attachment(
              id: 'failed-video',
              mime: 'video/mp4',
              mediaType: 'video',
              downloadStatus: 'failed',
              localPath: videoFile.path,
            ),
            onTap: () => tapped = true,
            onRetryUnavailableMedia: () => retryCount++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Media unavailable'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(MediaThumbnailImage), findsNothing);
    expect(find.byType(VideoThumbnailOverlay), findsNothing);
    expect(find.bySemanticsLabel('Retry unavailable media'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('unavailable-media-retry-msg-1-failed-video')),
    );
    await tester.pump();

    expect(retryCount, 1);
    expect(tapped, isFalse);
  });

  testWidgets('missing-file done video is unavailable, not fallback', (
    tester,
  ) async {
    final missingPath = '${tempDir.path}/missing-video.mp4';
    var tapped = false;

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 120,
          height: 120,
          child: MediaGridCell(
            attachment: _attachment(
              id: 'missing-video',
              mime: 'video/mp4',
              mediaType: 'video',
              downloadStatus: 'done',
              localPath: missingPath,
            ),
            onTap: () => tapped = true,
            onRetryUnavailableMedia: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Media unavailable'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(MediaThumbnailImage), findsNothing);
    expect(find.byType(VideoThumbnailOverlay), findsNothing);
    expect(find.bySemanticsLabel('Retry unavailable media'), findsNothing);

    await tester.tap(find.byType(MediaGridCell));
    expect(tapped, isFalse);
  });

  testWidgets('pending video remains loading without retry or play', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 120,
          height: 120,
          child: MediaGridCell(
            attachment: _attachment(
              id: 'pending-video',
              mime: 'video/mp4',
              mediaType: 'video',
              downloadStatus: 'pending',
              localPath: null,
            ),
            onTap: () => tapped = true,
            onRetryUnavailableMedia: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Media unavailable'), findsNothing);
    expect(find.byType(MediaThumbnailImage), findsNothing);
    expect(find.byType(VideoThumbnailOverlay), findsNothing);
    expect(find.bySemanticsLabel('Retry unavailable media'), findsNothing);

    await tester.tap(find.byType(MediaGridCell));
    expect(tapped, isFalse);
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

  testWidgets(
    'GIRD-005 verified done image without local path shows loading instead of unavailable',
    (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 120,
            height: 120,
            child: MediaGridCell(
              requireVerifiedContentHash: true,
              onTap: () => tapped = true,
              onRetryUnavailableMedia: () {},
              attachment: _attachment(
                id: 'verified-no-path',
                mime: 'image/jpeg',
                mediaType: 'image',
                downloadStatus: kMediaDownloadStatusDone,
                localPath: null,
                contentHash: _validContentHash,
                withEncryption: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Media unavailable'), findsNothing);
      expect(find.byType(MediaThumbnailImage), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(find.bySemanticsLabel('Retry unavailable media'), findsNothing);

      await tester.tap(find.byType(MediaGridCell));
      expect(tapped, isFalse);
    },
  );

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

        // Tamper (integrity_failed) shows the distinct "couldn't verify" label;
        // every other unavailable case shows the generic one.
        final expectedLabel =
            attachment.downloadStatus == kMediaDownloadStatusIntegrityFailed
            ? "Couldn't verify this media"
            : 'Media unavailable';
        expect(find.text(expectedLabel), findsOneWidget);
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

  testWidgets(
    '143: done image cell passes a non-null sized placeholder to '
    'MediaThumbnailImage (wiring lock)',
    (tester) async {
      // Preservation lock for the empty-while-decoding fix: that fix renders
      // `MediaThumbnailImage.placeholder` during image decode, so the cell MUST
      // keep supplying a non-null sized placeholder for done image cells. If a
      // future change nulled it, the fix would render SizedBox.shrink (empty)
      // again — this test fails first.
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 120,
            height: 120,
            child: MediaGridCell(
              attachment: _attachment(
                id: 'img-ph-wiring',
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

      final mti = tester.widget<MediaThumbnailImage>(
        find.byType(MediaThumbnailImage),
      );
      expect(mti.placeholder, isNotNull);
    },
  );

  testWidgets(
    '229: evicted image video and file show removed state and explicit retry',
    (tester) async {
      const specs = [
        (id: 'evicted-image', mime: 'image/jpeg', mediaType: 'image'),
        (id: 'evicted-video', mime: 'video/mp4', mediaType: 'video'),
        (id: 'evicted-file', mime: 'application/pdf', mediaType: 'file'),
      ];
      for (final spec in specs) {
        var retryCount = 0;
        final attachment = _attachment(
          id: spec.id,
          mime: spec.mime,
          mediaType: spec.mediaType,
          downloadStatus: kMediaDownloadStatusEvicted,
          localPath: null,
        );
        await tester.pumpWidget(
          wrap(
            MediaGridCell(
              attachment: attachment,
              onRetryUnavailableMedia: () => retryCount++,
            ),
          ),
        );
        await tester.pump();

        // Truthful removed state — never an indefinite loader, never the
        // generic unavailable copy.
        expect(find.text('Local copy removed'), findsOneWidget,
            reason: '${spec.mediaType} must render the removed state');
        expect(find.byType(CircularProgressIndicator), findsNothing,
            reason: '${spec.mediaType} must not render as loading');
        expect(find.text('Media unavailable'), findsNothing);

        // Explicit, user-authoritative Retry (not budget-gated).
        final retryKey = ValueKey('evicted-media-retry-msg-1-${spec.id}');
        expect(find.byKey(retryKey), findsOneWidget);
        expect(retryCount, 0, reason: 'build must never dispatch a retry');
        await tester.tap(find.byKey(retryKey));
        await tester.pump();
        expect(retryCount, 1,
            reason: '${spec.mediaType} retry fires exactly once per tap');
      }

      // Without a retry callback the removed state stays truthful but
      // renders no dead button.
      await tester.pumpWidget(
        wrap(
          MediaGridCell(
            attachment: _attachment(
              id: 'evicted-no-cb',
              mime: 'image/jpeg',
              mediaType: 'image',
              downloadStatus: kMediaDownloadStatusEvicted,
              localPath: null,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Local copy removed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('evicted-media-retry-msg-1-evicted-no-cb')),
        findsNothing,
      );
    },
  );
}
