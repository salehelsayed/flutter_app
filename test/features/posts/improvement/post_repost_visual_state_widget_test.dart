import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';

void main() {
  testWidgets(
    'renders an active repeat control and viewer-local count for a reposter card',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCard(
              post: _post(viewerHasPassed: true, viewerSharedToCount: 4),
              viewerPeerId: 'peer-alice',
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
      expect(find.text('4'), findsOneWidget);
    },
  );

  testWidgets(
    'renders an active repeat control and total count for the original author card',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCard(
              post: _post(totalSharedToCount: 6),
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
      expect(find.text('6'), findsOneWidget);
    },
  );

  testWidgets(
    'renders passive receiver totals neutrally without claiming ownership',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCard(
              post: _post(
                senderPeerId: 'peer-james',
                passedByUsername: 'James',
                passedByPeerId: 'peer-james',
                passedAt: '2026-03-15T11:15:00.000Z',
                totalSharedToCount: 4,
              ),
              onPassAlong: () {},
            ),
          ),
        ),
      );

      expect(find.text('James passed this along'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('post-share-count')),
        findsOneWidget,
      );
      expect(find.text('4'), findsOneWidget);

      final repeatIcon = tester.widget<Icon>(find.byIcon(Icons.repeat));
      expect(repeatIcon.color?.opacity, closeTo(0.35, 0.01));
      expect(find.text('Bob'), findsOneWidget);
    },
  );

  testWidgets(
    'keeps passive receiver repost totals neutral without opening the repost flow',
    (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCard(
              post: _post(
                senderPeerId: 'peer-james',
                passedByUsername: 'James',
                passedByPeerId: 'peer-james',
                passedAt: '2026-03-15T11:15:00.000Z',
                totalSharedToCount: 4,
              ),
              onPassAlong: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('post-share-count')),
        findsOneWidget,
      );
      expect(find.text('4'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.repeat));
      await tester.pump();

      expect(tapped, isFalse);
    },
  );

  testWidgets(
    'keeps the action cluster wrapped on a narrow card after the repost label rules land',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: PostCard(
                  post: _post(viewerHasPassed: true, viewerSharedToCount: 7),
                  viewerPeerId: 'peer-alice',
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
      expect(find.text('7'), findsOneWidget);
    },
  );
}

PostModel _post({
  String authorPeerId = 'peer-bob',
  String authorUsername = 'Bob',
  String senderPeerId = 'peer-bob',
  int totalSharedToCount = 0,
  int viewerSharedToCount = 0,
  bool viewerHasPassed = false,
  String? passedByPeerId,
  String? passedByUsername,
  String? passedAt,
}) {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: senderPeerId,
    authorPeerId: authorPeerId,
    authorUsername: authorUsername,
    text: 'Need a ladder',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
    passedByPeerId: passedByPeerId,
    passedByUsername: passedByUsername,
    passedAt: passedAt,
    totalSharedToCount: totalSharedToCount,
    viewerSharedToCount: viewerSharedToCount,
    viewerHasPassed: viewerHasPassed,
  );
}
