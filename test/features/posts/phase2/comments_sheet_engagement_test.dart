import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/comments_sheet.dart';

void main() {
  testWidgets('submits comments and toggles comment hearts through callbacks', (
    tester,
  ) async {
    String? submittedText;
    (String, bool)? toggled;
    const initialComments = <PostCommentModel>[
      PostCommentModel(
        id: 'comment-1',
        eventId: 'evt-comment-1',
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        authorUsername: 'Bob',
        body: 'I can lend one.',
        commentedAt: '2026-03-15T11:00:00.000Z',
        heartCount: 2,
        viewerHasHearted: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentsSheet(
            post: _post(),
            comments: initialComments,
            focusedCommentId: 'comment-1',
            onSubmitComment: (text) async {
              submittedText = text;
              return initialComments;
            },
            onToggleCommentHeart: (comment, isActive) async {
              toggled = (comment.id, isActive);
              return initialComments;
            },
          ),
        ),
      ),
    );

    expect(find.text('2 hearts'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Count me in');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();

    expect(submittedText, 'Count me in');

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();

    expect(toggled, ('comment-1', false));
  });
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
