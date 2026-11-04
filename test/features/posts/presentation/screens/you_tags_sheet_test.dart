import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/load_own_thought_tags_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/screens/you_page_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

final _now = DateTime.utc(2026, 11, 4, 12);

OwnThoughtTag _tag(String key, int daysAgo, {String? label}) => OwnThoughtTag(
  key: key,
  label: label ?? '#$key',
  lastUsed: _now.subtract(Duration(days: daysAgo)),
);

YouThought _thought(String text) => YouThought(
  post: PostModel(
    id: 'post-1',
    eventId: 'event-1',
    senderPeerId: 'me',
    authorPeerId: 'me',
    authorUsername: 'Saleh',
    text: text,
    audience: PostAudience.allFriends(),
    createdAt: _now.subtract(const Duration(hours: 2)).toIso8601String(),
    visibleAt: _now.subtract(const Duration(hours: 2)).toIso8601String(),
    expiresAt: _now.add(const Duration(hours: 22)).toIso8601String(),
    isIncoming: false,
  ),
  reactions: const [],
  wroteBack: const [],
);

void main() {
  late List<String?> loadedTags;
  late int noteSeen;

  setUp(() {
    loadedTags = [];
    noteSeen = 0;
  });

  Future<void> pump(
    WidgetTester tester,
    List<OwnThoughtTag> tags, {
    bool tagsNoteSeen = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: YouPageScreen(
          load: (limit, tag) async {
            loadedTags.add(tag);
            return YouPageData(
              username: 'Saleh',
              avatarBytes: null,
              friendCount: 41,
              thought: _thought('sunset at the falls #walks'),
              past: const [],
              tag: tag,
              tagCount: tag == null ? 0 : 4,
              tags: tags,
            );
          },
          now: () => _now,
          onBack: () {},
          onOpenChat: (_) async {},
          onCompose: (_) async {},
          tagsNoteSeen: tagsNoteSeen,
          onTagsNoteSeen: () => noteSeen++,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder icon() => find.byTooltip('Your tags');
  Finder row(String key) => find.byKey(ValueKey('you-tags-row-$key'));

  Future<void> open(WidgetTester tester) async {
    await tester.tap(icon());
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const ValueKey('you-tags-search')),
      query,
    );
    await tester.pump();
  }

  testWidgets('no tags yet, no # in the header', (tester) async {
    await pump(tester, const []);
    expect(icon(), findsNothing);
  });

  testWidgets('# opens your tags: the last three, then all of them A to Z '
      'with when each was last used', (tester) async {
    await pump(tester, [
      _tag('walks', 2),
      _tag('sea', 9),
      _tag('coffee', 16),
      _tag('books', 30),
      _tag('rain', 44),
    ]);
    await open(tester);

    expect(find.text('your tags'), findsOneWidget);
    expect(find.text('recent'), findsOneWidget);
    expect(find.byKey(const ValueKey('you-tags-recent-walks')), findsOneWidget);
    expect(find.byKey(const ValueKey('you-tags-recent-coffee')), findsOne);
    expect(find.byKey(const ValueKey('you-tags-recent-books')), findsNothing);
    final rows = [
      for (final key in ['books', 'coffee', 'rain', 'sea', 'walks'])
        tester.getTopLeft(row(key)).dy,
    ];
    expect(rows, orderedEquals([...rows]..sort()));
    expect(
      find.descendant(of: row('walks'), matching: find.text('2 d ago')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('you-tags-rail')), findsNothing);
  });

  testWidgets('typing narrows: matches at the start first, accents and '
      'Arabic marks ignored', (tester) async {
    await pump(tester, [
      _tag('sidewalk', 1),
      _tag('walks', 2),
      _tag('waves', 3),
      _tag('früh', 4),
      _tag('أمي', 5),
      _tag('sea', 6),
    ]);
    await open(tester);

    await search(tester, 'WA');
    expect(row('sea'), findsNothing);
    final walks = tester.getTopLeft(row('walks')).dy;
    final waves = tester.getTopLeft(row('waves')).dy;
    final sidewalk = tester.getTopLeft(row('sidewalk')).dy;
    expect(walks, lessThan(sidewalk));
    expect(waves, lessThan(sidewalk));

    await search(tester, 'fruh');
    expect(row('früh'), findsOneWidget);
    await search(tester, '#امي');
    expect(row('أمي'), findsOneWidget);
  });

  testWidgets('no match says so', (tester) async {
    await pump(tester, [_tag('walks', 2)]);
    await open(tester);
    await search(tester, 'hike');

    expect(find.text('no tag like #hike'), findsOneWidget);
    expect(find.text('tags come from your own Thoughts'), findsOneWidget);
  });

  testWidgets('picking a tag opens its tag view', (tester) async {
    await pump(tester, [_tag('walks', 2, label: '#Walks'), _tag('sea', 9)]);
    await open(tester);
    await tester.tap(row('walks'));
    await tester.pumpAndSettle();

    expect(find.text('your tags'), findsNothing);
    expect(find.byKey(const ValueKey('you-tag-bar')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('you-tag-bar')),
        matching: find.text('#Walks'),
      ),
      findsOneWidget,
    );
    expect(loadedTags.last, 'walks');
  });

  testWidgets('a recent pill opens its tag view too', (tester) async {
    await pump(tester, [_tag('walks', 2), _tag('sea', 9)]);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('you-tags-recent-sea')));
    await tester.pumpAndSettle();
    expect(loadedTags.last, 'sea');
  });

  testWidgets('the first time, a note points at #; opening it is enough', (
    tester,
  ) async {
    await pump(tester, [_tag('walks', 2)], tagsNoteSeen: false);
    expect(find.text('All your tags live here.'), findsOneWidget);

    await open(tester);
    expect(noteSeen, 1);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('All your tags live here.'), findsNothing);
  });

  testWidgets('a note already seen does not come back', (tester) async {
    await pump(tester, [_tag('walks', 2)]);
    expect(find.text('All your tags live here.'), findsNothing);
  });

  testWidgets('30 tags or more get a letter rail', (tester) async {
    await pump(tester, [
      for (var i = 0; i < 30; i++)
        _tag('${String.fromCharCode(97 + i % 26)}tag$i', i),
    ]);
    await open(tester);
    expect(find.byKey(const ValueKey('you-tags-rail')), findsOneWidget);
  });
}
