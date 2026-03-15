import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';

void main() {
  testWidgets('renders post heart state, counts, and expiry footer', (
    tester,
  ) async {
    var toggled = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(
            post: PostModel(
              id: 'post-1',
              eventId: 'evt-post-1',
              senderPeerId: 'peer-bob',
              authorPeerId: 'peer-bob',
              authorUsername: 'Bob',
              text: 'Need a ladder',
              audience: PostAudience.allFriends(),
              createdAt: '2026-03-15T10:15:30.000Z',
              visibleAt: '2026-03-15T10:15:30.000Z',
              expiresAt: '2026-03-16T12:00:00.000Z',
              commentCount: 3,
              heartCount: 2,
              viewerHasHearted: true,
            ),
            onToggleHeart: () {
              toggled += 1;
            },
            nowProvider: () => DateTime.parse('2026-03-16T10:00:00.000Z'),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('post-heart-count')))
          .data,
      '2',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('post-comment-count')),
          )
          .data,
      '3',
    );
    expect(find.byType(UserAvatar), findsOneWidget);
    expect(find.text('Friend'), findsOneWidget);
    expect(find.text('expires in 2h'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();

    expect(toggled, 1);
  });
}
