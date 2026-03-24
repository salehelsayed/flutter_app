import 'dart:ui' show TextDirection;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/comments_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget _buildSheet({
    required PostModel post,
    required List<PostCommentModel> comments,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CommentsSheet(
          post: post,
          comments: comments,
          onSubmitComment: (_) async => comments,
        ),
      ),
    );
  }

  testWidgets('composer Arabic-only input drives RTL', (tester) async {
    await tester.pumpWidget(
      _buildSheet(
        post: _post(text: 'Need a ladder'),
        comments: const <PostCommentModel>[],
      ),
    );

    await tester.enterText(find.byType(TextField), 'مرحبا');
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.rtl,
    );
  });

  testWidgets('composer Arabic-first mixed input drives RTL', (tester) async {
    await tester.pumpWidget(
      _buildSheet(
        post: _post(text: 'Need a ladder'),
        comments: const <PostCommentModel>[],
      ),
    );

    await tester.enterText(find.byType(TextField), 'مرحبا Hello 123');
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.rtl,
    );
  });

  testWidgets('composer English-first mixed input stays LTR', (tester) async {
    await tester.pumpWidget(
      _buildSheet(
        post: _post(text: 'Need a ladder'),
        comments: const <PostCommentModel>[],
      ),
    );

    await tester.enterText(find.byType(TextField), 'Hello مرحبا 123');
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.ltr,
    );
  });

  testWidgets('post summary mixed-script text respects RTL direction', (
    tester,
  ) async {
    const mixedText = 'مرحبا Hello 123';

    await tester.pumpWidget(
      _buildSheet(
        post: _post(text: mixedText),
        comments: const <PostCommentModel>[],
      ),
    );

    expect(find.text(mixedText), findsOneWidget);
    expect(_textFor(tester, mixedText).textDirection, TextDirection.rtl);
  });

  testWidgets('comment body mixed-script text respects RTL direction', (
    tester,
  ) async {
    const mixedText = 'مرحبا Hello 123';

    await tester.pumpWidget(
      _buildSheet(
        post: _post(text: 'Need a ladder'),
        comments: <PostCommentModel>[
          const PostCommentModel(
            id: 'comment-1',
            eventId: 'evt-comment-1',
            postId: 'post-1',
            senderPeerId: 'peer-bob',
            authorUsername: 'Bob',
            body: mixedText,
            commentedAt: '2026-03-15T11:00:00.000Z',
          ),
        ],
      ),
    );

    expect(find.text(mixedText), findsOneWidget);
    expect(_textFor(tester, mixedText).textDirection, TextDirection.rtl);
  });
}

PostModel _post({required String text}) {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: 'peer-bob',
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: text,
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
  );
}

Text _textFor(WidgetTester tester, String text) {
  final finder = find.byWidgetPredicate(
    (widget) => widget is Text && widget.data == text,
    description: 'Text("$text")',
  );
  expect(finder, findsOneWidget);
  return tester.widget<Text>(finder);
}
