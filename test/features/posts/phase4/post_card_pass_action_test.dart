import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';

void main() {
  testWidgets('shows a pass-along action for eligible direct posts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(
            post: _post(audience: PostAudience.allFriends()),
            onPassAlong: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.repeat), findsOneWidget);
  });

  testWidgets('wraps action clusters on narrow cards without overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: PostCard(
                post: _post(audience: PostAudience.allFriends()),
                onOpenComments: () {},
                onPassAlong: () {},
                onPinPost: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.mode_comment_outlined), findsOneWidget);
    expect(find.byIcon(Icons.repeat), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
  });

  testWidgets('hides the pass-along action for Pick People posts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(
            post: _post(
              audience: PostAudience.pickPeople(const <String>['peer-self']),
            ),
            onPassAlong: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.repeat), findsNothing);
  });
}

PostModel _post({required PostAudience audience}) {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: 'peer-bob',
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: 'Need a ladder',
    audience: audience,
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-16T12:00:00.000Z',
  );
}
