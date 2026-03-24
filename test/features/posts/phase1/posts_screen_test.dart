import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_screen.dart';

void main() {
  testWidgets('shows caught-up state when no posts exist', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PostsScreen(
          username: 'Alice',
          posts: const <PostModel>[],
          activeTab: 'posts',
          onSwitchView: (_) {},
          onCompose: () {},
        ),
      ),
    );

    expect(find.text("You're all caught up"), findsWidgets);
    expect(find.text('Create your first post'), findsOneWidget);
  });

  testWidgets('renders focused post card highlight state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PostsScreen(
          username: 'Alice',
          posts: <PostModel>[
            _post(id: 'post-1', text: 'First post'),
          ],
          activeTab: 'posts',
          onSwitchView: (_) {},
          onCompose: () {},
          focusedPostId: 'post-1',
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('post-post-1')), findsOneWidget);
    expect(find.text('First post'), findsOneWidget);
  });
}

PostModel _post({
  required String id,
  required String text,
}) {
  return PostModel(
    id: id,
    eventId: 'evt-$id',
    senderPeerId: 'peer-a',
    authorPeerId: 'peer-a',
    authorUsername: 'Alice',
    text: text,
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
  );
}
