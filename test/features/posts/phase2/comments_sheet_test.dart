import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/comments_sheet.dart';

void main() {
  testWidgets(
    'renders the post summary, comment count, chronological comments, and composer',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentsSheet(
              post: _post(),
              comments: const <PostCommentModel>[
                PostCommentModel(
                  id: 'comment-1',
                  eventId: 'evt-comment-1',
                  postId: 'post-1',
                  senderPeerId: 'peer-bob',
                  body: 'I can lend one.',
                  commentedAt: '2026-03-15T11:00:00.000Z',
                ),
                PostCommentModel(
                  id: 'comment-2',
                  eventId: 'evt-comment-2',
                  postId: 'post-1',
                  senderPeerId: 'peer-cara',
                  body: 'I have one too.',
                  commentedAt: '2026-03-15T11:05:00.000Z',
                ),
              ],
              onSubmitComment: (_) async => const <PostCommentModel>[],
            ),
          ),
        ),
      );

      expect(find.text('Need a ladder in Kreuzberg'), findsOneWidget);
      expect(find.text('2 comments'), findsOneWidget);
      expect(find.text('I can lend one.'), findsOneWidget);
      expect(find.text('I have one too.'), findsOneWidget);
      expect(find.text('Write a comment...'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('comments-composer-pill')),
        findsOneWidget,
      );
      expect(find.byType(UserAvatar), findsNWidgets(4));
      expect(find.byIcon(Icons.close), findsOneWidget);

      final firstOffset = tester.getTopLeft(find.text('I can lend one.'));
      final secondOffset = tester.getTopLeft(find.text('I have one too.'));
      expect(firstOffset.dy, lessThan(secondOffset.dy));
    },
  );
}

PostModel _post() {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: 'peer-bob',
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: 'Need a ladder in Kreuzberg',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
  );
}
