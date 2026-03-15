import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';

void main() {
  testWidgets('renders the nearby distance label on nearby-scoped cards', (
    tester,
  ) async {
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
              text: 'Lost dog near the bridge.',
              audience: PostAudience.peopleNearby(radiusM: 2000),
              createdAt: '2026-03-15T10:15:30.000Z',
              visibleAt: '2026-03-15T10:15:30.000Z',
              expiresAt: '2026-03-18T10:15:30.000Z',
              nearbyDistanceLabel: '350m away',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Shared nearby'), findsOneWidget);
    expect(find.text('350m away'), findsOneWidget);
  });
}
