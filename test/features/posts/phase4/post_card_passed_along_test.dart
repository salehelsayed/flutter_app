import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
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

  testWidgets(
    "renders the original author's avatar from Posts-owned snapshot bytes on a passed-along card",
    (tester) async {
      final docsDir = Directory.systemTemp.createTempSync(
        'post-card-passed-avatar-',
      );
      addTearDown(() => docsDir.deleteSync(recursive: true));
      UserAvatar.setDocumentsDir(docsDir.path);
      final avatarBytes = _avatarSnapshotBytes();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCard(
              post: PostModel(
                id: 'post-1',
                eventId: 'evt-pass-1',
                senderPeerId: 'peer-hisam',
                authorPeerId: 'peer-solz',
                authorUsername: 'Solz',
                text: 'Avatar snapshot should win over contact lookup.',
                audience: PostAudience.allFriends(),
                createdAt: '2026-03-15T10:15:30.000Z',
                visibleAt: '2026-03-15T11:15:00.000Z',
                expiresAt: '2026-03-18T10:15:30.000Z',
                passedByPeerId: 'peer-hisam',
                passedByUsername: 'Hisam',
                passedAt: '2026-03-15T11:15:00.000Z',
                originalAuthorAvatarBytes: avatarBytes,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
      expect(avatar.avatarBytes, orderedEquals(avatarBytes));
      expect(find.byType(RingAvatar), findsNothing);
    },
  );

  testWidgets(
    'renders the original author with a fallback ring avatar on a passed-along card when no avatar snapshot exists',
    (tester) async {
      final docsDir = Directory.systemTemp.createTempSync(
        'post-card-passed-avatar-',
      );
      addTearDown(() => docsDir.deleteSync(recursive: true));
      UserAvatar.setDocumentsDir(docsDir.path);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostCard(
              post: PostModel(
                id: 'post-1',
                eventId: 'evt-pass-1',
                senderPeerId: 'peer-hisam',
                authorPeerId: 'peer-solz',
                authorUsername: 'Solz',
                text: 'Broken avatar snapshot repro.',
                audience: PostAudience.allFriends(),
                createdAt: '2026-03-15T10:15:30.000Z',
                visibleAt: '2026-03-15T11:15:00.000Z',
                expiresAt: '2026-03-18T10:15:30.000Z',
                passedByPeerId: 'peer-hisam',
                passedByUsername: 'Hisam',
                passedAt: '2026-03-15T11:15:00.000Z',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hisam passed this along'), findsOneWidget);
      expect(find.text('Solz'), findsOneWidget);
      expect(find.byType(RingAvatar), findsOneWidget);
    },
  );
}

Uint8List _avatarSnapshotBytes() {
  return Uint8List.fromList(const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x62,
    0x00,
    0x00,
    0x00,
    0x02,
    0x00,
    0x01,
    0xE5,
    0x27,
    0xDE,
    0xFC,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
}
