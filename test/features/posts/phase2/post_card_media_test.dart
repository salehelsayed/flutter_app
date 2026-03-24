import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
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
                media: const [
                  PostMediaAttachmentModel(
                    mediaId: 'media-video-1',
                    postId: 'post-1',
                    blobId: 'blob-video-1',
                    kind: 'video',
                    mime: 'video/mp4',
                    sizeBytes: 100,
                    durationMs: 125000,
                    downloadStatus: 'pending',
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
