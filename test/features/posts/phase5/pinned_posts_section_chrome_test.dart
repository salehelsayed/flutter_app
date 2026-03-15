import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/pinned_posts_section.dart';

import 'support/post_pin_fixtures.dart';

void main() {
  testWidgets('shows overflow badge and receiver actions for pinned posts', (
    tester,
  ) async {
    PostModel post(String id, String peerId, String username) {
      return postPinBasePost(
        postId: id,
        authorPeerId: peerId,
        authorUsername: username,
        text: 'Pinned by $username',
        keepAvailable: true,
      );
    }

    PostModel? tappedPost;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PinnedPostsSection(
              posts: <PostModel>[
                post('post-1', 'peer-bob', 'Bob'),
                post('post-2', 'peer-cara', 'Cara'),
                post('post-3', 'peer-dan', 'Dan'),
                post('post-4', 'peer-eve', 'Eve'),
                post('post-5', 'peer-finn', 'Finn'),
                post('post-6', 'peer-gia', 'Gia'),
                post('post-7', 'peer-hugo', 'Hugo'),
              ],
              viewerPeerId: 'peer-receiver',
              onDismiss: (_) {},
              onMessage: (post) => tappedPost = post,
            ),
          ),
        ),
      ),
    );

    expect(find.text('+1'), findsOneWidget);

    await tester.tap(find.text('Pinned posts'));
    await tester.pump();

    expect(find.text('Message Bob'), findsOneWidget);
    expect(find.text('Dismiss'), findsWidgets);

    await tester.tap(find.text('Message Bob'));
    await tester.pump();

    expect(tappedPost?.authorUsername, 'Bob');
  });

  testWidgets('shows author management actions instead of receiver actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinnedPostsSection(
            posts: <PostModel>[
              postPinBasePost(
                authorPeerId: 'peer-bob',
                authorUsername: 'Bob',
                text: 'Need a ladder',
                keepAvailable: true,
              ),
            ],
            viewerPeerId: 'peer-bob',
            onEdit: (_) {},
            onRemove: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Pinned posts'));
    await tester.pump();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.textContaining('Message'), findsNothing);
    expect(find.text('Dismiss'), findsNothing);
  });
}
