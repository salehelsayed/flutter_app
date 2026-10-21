import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../shared/fakes/fake_just_audio.dart';

void main() {
  setUp(installFakeJustAudioPlatform);
  for (final language in ['en', 'de', 'ar']) {
    for (final kind in ['image', 'video', 'voice', 'file']) {
      testWidgets(
        '$language $kind post automatic recovery stays silent and loading',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: PostCard(
                    post: _post(
                      mediaKind: kind == 'image' ? 'image_carousel' : kind,
                      media: [
                        PostMediaAttachmentModel(
                          mediaId: 'retry',
                          postId: 'post-1',
                          blobId: 'retry-blob',
                          kind: kind,
                          mime: kind == 'voice'
                              ? 'audio/mp4'
                              : kind == 'video'
                              ? 'video/mp4'
                              : kind == 'file'
                              ? 'application/pdf'
                              : 'image/jpeg',
                          sizeBytes: 100,
                          downloadStatus: 'retry_waiting',
                          createdAt: '2026-10-21T00:00:00Z',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(Scaffold)),
          )!;
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          for (final text in [
            l10n.media_retry_later,
            l10n.media_unavailable,
            l10n.media_no_longer_available,
            l10n.media_open_failed,
          ]) {
            expect(find.text(text), findsNothing);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('renders an image carousel counter badge for multi-image posts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostCard(
              post: _post(
                mediaKind: 'image_carousel',
                media: const [
                  PostMediaAttachmentModel(
                    mediaId: 'media-1',
                    postId: 'post-1',
                    blobId: 'blob-1',
                    kind: 'image',
                    mime: 'image/jpeg',
                    sizeBytes: 100,
                    localPath: '/tmp/one.jpg',
                    downloadStatus: 'done',
                    createdAt: '2026-03-15T10:20:00.000Z',
                  ),
                  PostMediaAttachmentModel(
                    mediaId: 'media-2',
                    postId: 'post-1',
                    blobId: 'blob-2',
                    kind: 'image',
                    mime: 'image/jpeg',
                    sizeBytes: 100,
                    localPath: '/tmp/two.jpg',
                    downloadStatus: 'done',
                    createdAt: '2026-03-15T10:20:01.000Z',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('renders a video duration badge for video posts', (tester) async {
    // The video overlay only renders for displayable done media (download
    // done + local file present), so the fixture needs a real file.
    final tempDir = Directory.systemTemp.createTempSync('post-card-media-');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final videoFile = File('${tempDir.path}/blob-video-1.mp4')
      ..writeAsBytesSync(<int>[0, 1, 2, 3]);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostCard(
              post: _post(
                mediaKind: 'video',
                media: [
                  PostMediaAttachmentModel(
                    mediaId: 'media-video-1',
                    postId: 'post-1',
                    blobId: 'blob-video-1',
                    kind: 'video',
                    mime: 'video/mp4',
                    sizeBytes: 100,
                    durationMs: 125000,
                    localPath: videoFile.path,
                    downloadStatus: 'done',
                    createdAt: '2026-03-15T10:20:00.000Z',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('2:05'), findsOneWidget);
  });
}

PostModel _post({
  required String mediaKind,
  required List<PostMediaAttachmentModel> media,
}) {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: 'peer-bob',
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: 'Media post',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
    mediaKind: mediaKind,
    media: media,
  );
}
