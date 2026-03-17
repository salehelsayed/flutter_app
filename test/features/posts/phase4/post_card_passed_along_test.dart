import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';

void main() {
  testWidgets(
    'renders passed-along attribution on a resurfaced direct-author card without the direct-friend badge',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCard(
              post: PostModel(
                id: 'post-1',
                eventId: 'evt-direct-1',
                senderPeerId: 'peer-sarah',
                authorPeerId: 'peer-sarah',
                authorUsername: 'Sarah',
                text: 'Lost dog near Neckar bridge.',
                audience: PostAudience.peopleNearby(radiusM: 2000),
                createdAt: '2026-03-15T10:15:30.000Z',
                visibleAt: '2026-03-15T11:15:00.000Z',
                expiresAt: '2026-03-18T10:15:30.000Z',
                passedByUsername: 'James',
                passedAt: '2026-03-15T11:15:00.000Z',
              ),
            ),
          ),
        ),
      );

      expect(find.text('James passed this along'), findsOneWidget);
      expect(find.text('Sarah'), findsOneWidget);
      expect(find.text('Shared nearby'), findsOneWidget);
      expect(find.text('Friend'), findsNothing);
    },
  );
}
