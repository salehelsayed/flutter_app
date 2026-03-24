import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  testWidgets('renders post heart state, counts, and expiry footer', (
    tester,
  ) async {
    var toggled = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    expect(toggled, 1);
  });

  testWidgets('shows inline delivery state and disables sending actions', (
    tester,
  ) async {
    var heartTaps = 0;
    var commentTaps = 0;
    var passTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                PostCard(
                  post: _post(deliveryStatus: 'sending'),
                  onToggleHeart: () {
                    heartTaps += 1;
                  },
                  onOpenComments: () {
                    commentTaps += 1;
                  },
                  onPassAlong: () {
                    passTaps += 1;
                  },
                ),
                PostCard(
                  post: _post(id: 'post-2', deliveryStatus: 'partial'),
                ),
                PostCard(
                  post: _post(id: 'post-3', deliveryStatus: 'failed'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Sending...'), findsOneWidget);
    expect(find.text('Partially sent'), findsOneWidget);
    expect(find.text('Send failed'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.tap(find.byIcon(Icons.mode_comment_outlined).first);
    await tester.tap(find.byIcon(Icons.repeat).first);
    await tester.pump();

    expect(heartTaps, 0);
    expect(commentTaps, 0);
    expect(passTaps, 0);
  });

  testWidgets(
    'renders an explicit placeholder and upload label for media skeleton posts',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PostCard(
              post: PostModel(
                id: 'post-media-skeleton',
                eventId: 'evt-post-media-skeleton',
                senderPeerId: 'peer-bob',
                authorPeerId: 'peer-bob',
                authorUsername: 'Bob',
                text: '',
                audience: PostAudience.allFriends(),
                createdAt: '2026-03-15T10:15:30.000Z',
                visibleAt: '2026-03-15T10:15:30.000Z',
                expiresAt: '2026-03-16T12:00:00.000Z',
                mediaKind: 'image',
                deliveryStatus: 'sending',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Uploading media...'), findsOneWidget);
      expect(find.text('Photo pending upload'), findsOneWidget);
    },
  );
}

PostModel _post({String id = 'post-1', String deliveryStatus = 'available'}) {
  return PostModel(
    id: id,
    eventId: 'evt-$id',
    senderPeerId: 'peer-bob',
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: 'Need a ladder',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-16T12:00:00.000Z',
    deliveryStatus: deliveryStatus,
  );
}
