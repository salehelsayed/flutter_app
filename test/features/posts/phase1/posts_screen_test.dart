import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_screen.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';

import '../../../shared/helpers/readability_test_helpers.dart';

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
          posts: <PostModel>[_post(id: 'post-1', text: 'First post')],
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

  testWidgets('daylight lagoon keeps posts and pinned content readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PostsScreen(
          username: 'Alice',
          posts: <PostModel>[
            _post(id: 'post-1', text: 'Hello مرحبا from Daylight'),
          ],
          pinnedPosts: <PostModel>[
            _post(id: 'pin-1', text: 'Pinned readable offer'),
          ],
          activeTab: 'posts',
          onSwitchView: (_) {},
          onCompose: () {},
          backgroundPreference: BackgroundPreference.daylightLagoon,
        ),
      ),
    );

    expect(find.byType(DaylightLagoonBackground), findsOneWidget);
    expect(find.text('Posts'), findsOneWidget);
    expect(find.text('Hello مرحبا from Daylight'), findsOneWidget);
    expect(find.text('Pinned posts'), findsOneWidget);

    final colors = BackgroundReadableColors.representativeLight;
    final title = tester.widget<Text>(find.text('Posts'));
    expectTextContrast(title.style!.color!, colors.surfaceBase);

    final body = tester.widget<LinkableText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is LinkableText &&
            widget.text == 'Hello مرحبا from Daylight',
      ),
    );
    expectTextContrast(body.style!.color!, colors.surfaceRaised);

    final pinnedTitle = tester.widget<Text>(find.text('Pinned posts'));
    expectTextContrast(pinnedTitle.style!.color!, colors.surfaceRaised);
  });
}

PostModel _post({required String id, required String text}) {
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
