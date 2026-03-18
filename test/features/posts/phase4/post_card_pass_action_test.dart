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

  testWidgets(
    'shows an active repeat control and viewer-local count on a reposter card',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCard(
              post: _post(
                audience: PostAudience.allFriends(),
                viewerHasPassed: true,
                viewerSharedToCount: 3,
              ),
              viewerPeerId: 'peer-bob',
              onPassAlong: () {},
            ),
          ),
        ),
      );

      final repeatIcon = tester.widget<Icon>(find.byIcon(Icons.repeat));
      expect(repeatIcon.color, const Color(0xFF1DB954));
      expect(
        find.byKey(const ValueKey<String>('post-share-count')),
        findsOneWidget,
      );
      expect(find.text('3'), findsOneWidget);
    },
  );

  testWidgets(
    'keeps the repeat control neutral and unlabeled on a passed-along card',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCard(
              post: _post(
                audience: PostAudience.allFriends(),
                passedByPeerId: 'peer-james',
                passedByUsername: 'James',
                passedAt: '2026-03-15T11:15:00.000Z',
              ),
              onPassAlong: () {},
            ),
          ),
        ),
      );

      final repeatIcon = tester.widget<Icon>(find.byIcon(Icons.repeat));
      expect(repeatIcon.color?.opacity, closeTo(0.35, 0.01));
      expect(find.text('James passed this along'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('post-share-count')),
        findsNothing,
      );
    },
  );

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

PostModel _post({
  required PostAudience audience,
  String? passedByPeerId,
  String? passedByUsername,
  String? passedAt,
  int shareCount = 0,
  int totalSharedToCount = 0,
  int viewerSharedToCount = 0,
  bool viewerHasPassed = false,
}) {
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
    passedByPeerId: passedByPeerId,
    passedByUsername: passedByUsername,
    passedAt: passedAt,
    shareCount: shareCount,
    totalSharedToCount: totalSharedToCount,
    viewerSharedToCount: viewerSharedToCount,
    viewerHasPassed: viewerHasPassed,
  );
}
