import 'dart:async';

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
              return <PostCommentModel>[
                ...initialComments,
                const PostCommentModel(
                  id: 'comment-2',
                  eventId: 'evt-comment-2',
                  postId: 'post-1',
                  senderPeerId: 'peer-self',
                  authorUsername: 'Alice',
                  body: 'Count me in',
                  commentedAt: '2026-03-15T11:05:00.000Z',
                ),
              ];
            },
            onToggleCommentHeart: (comment, isActive) async {
              toggled = (comment.id, isActive);
              return initialComments;
            },
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);

    await tester.enterText(find.byType(TextField), 'Count me in');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(submittedText, 'Count me in');
    expect(find.text('2 comments'), findsOneWidget);
    expect(find.text('Count me in'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();

    expect(toggled, ('comment-1', false));
  });

  testWidgets(
    'keeps in-flight submit state when parent comments refresh mid-submit',
    (tester) async {
      final submitCompleter = Completer<List<PostCommentModel>>();
      const initialComments = <PostCommentModel>[
        PostCommentModel(
          id: 'comment-1',
          eventId: 'evt-comment-1',
          postId: 'post-1',
          senderPeerId: 'peer-bob',
          authorUsername: 'Bob',
          body: 'I can lend one.',
          commentedAt: '2026-03-15T11:00:00.000Z',
        ),
      ];
      const remoteComment = PostCommentModel(
        id: 'comment-3',
        eventId: 'evt-comment-3',
        postId: 'post-1',
        senderPeerId: 'peer-cara',
        authorUsername: 'Cara',
        body: 'I can bring one over.',
        commentedAt: '2026-03-15T11:02:00.000Z',
      );
      const localComment = PostCommentModel(
        id: 'comment-2',
        eventId: 'evt-comment-2',
        postId: 'post-1',
        senderPeerId: 'peer-self',
        authorUsername: 'Alice',
        body: 'Count me in',
        commentedAt: '2026-03-15T11:01:00.000Z',
      );

      Widget buildSheet(List<PostCommentModel> comments) {
        return MaterialApp(
          home: Scaffold(
            body: CommentsSheet(
              post: _post(),
              comments: comments,
              onSubmitComment: (_) => submitCompleter.future,
            ),
          ),
        );
      }

      await tester.pumpWidget(buildSheet(initialComments));

      await tester.enterText(find.byType(TextField), 'Count me in');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      expect(_composerText(tester), 'Count me in');

      await tester.pumpWidget(
        buildSheet(const <PostCommentModel>[...initialComments, remoteComment]),
      );
      await tester.pump();

      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      expect(_composerText(tester), 'Count me in');
      expect(find.text('I can bring one over.'), findsOneWidget);
      expect(find.text('2 comments'), findsOneWidget);

      submitCompleter.complete(<PostCommentModel>[
        initialComments[0],
        remoteComment,
        localComment,
      ]);
      await tester.pump();

      expect(find.byIcon(Icons.hourglass_top), findsNothing);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(_composerText(tester), isEmpty);
      expect(find.text('3 comments'), findsOneWidget);
      expect(find.text('Count me in'), findsOneWidget);
      _expectVisualOrder(tester, <String>[
        'I can lend one.',
        'Count me in',
        'I can bring one over.',
      ]);
    },
  );

  testWidgets('scrolls to the latest comment when new comments arrive', (
    tester,
  ) async {
    final initialComments = List<PostCommentModel>.generate(
      18,
      (index) => PostCommentModel(
        id: 'comment-${index + 1}',
        eventId: 'evt-comment-${index + 1}',
        postId: 'post-1',
        senderPeerId: index.isEven ? 'peer-bob' : 'peer-cara',
        authorUsername: index.isEven ? 'Bob' : 'Cara',
        body: 'Comment ${index + 1}',
        commentedAt:
            '2026-03-15T11:${index.toString().padLeft(2, '0')}:00.000Z',
      ),
      growable: false,
    );
    final updatedComments = <PostCommentModel>[
      ...initialComments,
      const PostCommentModel(
        id: 'comment-19',
        eventId: 'evt-comment-19',
        postId: 'post-1',
        senderPeerId: 'peer-self',
        authorUsername: 'Alice',
        body: 'Latest comment',
        commentedAt: '2026-03-15T11:18:00.000Z',
      ),
    ];

    Widget buildSheet(List<PostCommentModel> comments) {
      return MaterialApp(
        home: Scaffold(
          body: CommentsSheet(
            post: _post(),
            comments: comments,
            onSubmitComment: (_) async => comments,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildSheet(initialComments));
    await tester.pump();

    expect(find.text('Comment 18'), findsOneWidget);

    await tester.pumpWidget(buildSheet(updatedComments));
    await tester.pump();

    expect(find.text('Latest comment'), findsOneWidget);
    expect(find.text('Comment 1'), findsNothing);

    final newestBottom = tester.getBottomLeft(find.text('Latest comment')).dy;
    final composerTop = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('comments-composer-pill')),
        )
        .dy;
    expect(newestBottom, lessThan(composerTop));
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

String _composerText(WidgetTester tester) {
  return tester.widget<TextField>(find.byType(TextField)).controller?.text ??
      '';
}

void _expectVisualOrder(WidgetTester tester, List<String> bodies) {
  var previousDy = -1.0;
  for (final body in bodies) {
    final dy = tester.getTopLeft(find.text(body)).dy;
    expect(dy, greaterThan(previousDy));
    previousDy = dy;
  }
}
