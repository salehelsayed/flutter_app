import 'package:flutter/material.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/presentation/screens/you_page_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 11, 1, 12);

PostModel _post(
  String id, {
  Duration age = const Duration(hours: 5),
  Duration lifetime = const Duration(hours: 24),
}) {
  final created = _now.subtract(age);
  return PostModel(
    id: id,
    eventId: 'event-$id',
    senderPeerId: 'me',
    authorPeerId: 'me',
    authorUsername: 'Saleh',
    text: 'thought $id',
    audience: PostAudience.allFriends(),
    createdAt: created.toIso8601String(),
    visibleAt: created.toIso8601String(),
    expiresAt: created.add(lifetime).toIso8601String(),
    isIncoming: false,
  );
}

/// p0 is Sara, seen most recently; each next friend a minute earlier.
List<YouViewer> _viewers(int count) => [
  for (var i = 0; i < count; i++)
    YouViewer(
      peerId: 'p$i',
      name: i == 0 ? 'Sara' : 'Friend $i',
      viewedAt: _now.subtract(Duration(minutes: i + 1)),
    ),
];

const _reactors = ['p30', 'p10', 'p20'];

YouThought _live({int seen = 80}) => YouThought(
  post: _post('live'),
  seenCount: seen,
  reactions: [
    (
      reaction: ThoughtReaction.love,
      participants: [
        for (final peer in _reactors) (peerId: peer, name: 'Friend $peer'),
      ],
    ),
  ],
  wroteBack: const [],
);

YouPageData _data({YouThought? thought, List<YouThought> past = const []}) =>
    YouPageData(
      username: 'Saleh',
      avatarBytes: null,
      friendCount: 112,
      thought: thought,
      past: past,
    );

Finder _rowsIn(Finder scope) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('you-viewer-'),
  ),
);

List<String> _rowKeysTopDown(WidgetTester tester, Finder rows) {
  final elements = rows.evaluate().toList()
    ..sort(
      (a, b) => tester
          .getTopLeft(find.byWidget(a.widget))
          .dy
          .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
    );
  return [for (final e in elements) (e.widget.key! as ValueKey<String>).value];
}

final _sheet = find.byKey(const ValueKey('you-viewers-sheet'));

void main() {
  late List<String> viewerLoads;

  setUp(() => viewerLoads = []);

  Future<void> pumpPage(
    WidgetTester tester,
    YouPageData data, {
    List<YouViewer> viewers = const [],
    Locale locale = const Locale('en'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: YouPageScreen(
          load: (_, _) async => data,
          loadViewers: (postId) async {
            viewerLoads.add(postId);
            return viewers;
          },
          now: () => _now,
          onBack: () {},
          onOpenChat: (_) async {},
          onCompose: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSeen(WidgetTester tester, String postId) async {
    await tester.tap(find.byKey(ValueKey('you-seen-$postId')));
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester, int count) async {
    await tester.tap(find.text('See all $count'));
    await tester.pumpAndSettle();
  }

  testWidgets('the chip counts viewers and loads the list only when opened', (
    tester,
  ) async {
    await pumpPage(tester, _data(thought: _live()), viewers: _viewers(80));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('you-seen-live')),
        matching: find.text('Seen by 80 friends'),
      ),
      findsOneWidget,
    );
    expect(viewerLoads, isEmpty);

    await openSeen(tester, 'live');

    expect(viewerLoads, ['live']);
  });

  testWidgets('80 viewers show 5 rows, reacted first, then "See all 80"', (
    tester,
  ) async {
    await pumpPage(tester, _data(thought: _live()), viewers: _viewers(80));
    await openSeen(tester, 'live');

    final rows = _rowsIn(find.byKey(const ValueKey('you-thought-live')));
    expect(rows, findsNWidgets(5));
    expect(_rowKeysTopDown(tester, rows), [
      'you-viewer-p10',
      'you-viewer-p20',
      'you-viewer-p30',
      'you-viewer-p0',
      'you-viewer-p1',
    ]);
    expect(find.text('See all 80'), findsOneWidget);
    expect(find.text('11 min ago'), findsOneWidget);
    expect(find.text('2 min ago'), findsOneWidget);
    expect(find.text('3 min ago'), findsNothing);
  });

  testWidgets('5 viewers fit inline with no "See all" row', (tester) async {
    await pumpPage(
      tester,
      _data(thought: _live(seen: 5)),
      viewers: _viewers(5),
    );
    await openSeen(tester, 'live');

    expect(_rowsIn(find.byType(YouPageScreen)), findsNWidgets(5));
    expect(find.textContaining('See all'), findsNothing);
  });

  testWidgets('"See all" opens the sheet and search filters its rows', (
    tester,
  ) async {
    await pumpPage(tester, _data(thought: _live()), viewers: _viewers(80));
    await openSeen(tester, 'live');
    await openSheet(tester, 80);

    expect(_sheet, findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(_rowsIn(_sheet), findsWidgets);
    expect(
      find.descendant(of: _sheet, matching: find.text('Friend 1')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('you-viewers-search')),
      'sara',
    );
    await tester.pumpAndSettle();

    expect(_rowKeysTopDown(tester, _rowsIn(_sheet)), ['you-viewer-p0']);
    expect(
      find.descendant(of: _sheet, matching: find.text('Friend 1')),
      findsNothing,
    );
  });

  testWidgets('the Reactions pill shows only friends who reacted', (
    tester,
  ) async {
    await pumpPage(tester, _data(thought: _live()), viewers: _viewers(80));
    await openSeen(tester, 'live');
    await openSheet(tester, 80);

    await tester.tap(find.byKey(const ValueKey('you-viewers-reacted')));
    await tester.pumpAndSettle();

    expect(_rowKeysTopDown(tester, _rowsIn(_sheet)), [
      'you-viewer-p10',
      'you-viewer-p20',
      'you-viewer-p30',
    ]);

    await tester.tap(find.byKey(const ValueKey('you-viewers-all')));
    await tester.pumpAndSettle();

    expect(_rowKeysTopDown(tester, _rowsIn(_sheet)).take(2), [
      'you-viewer-p0',
      'you-viewer-p1',
    ]);
  });

  testWidgets('20 viewers get no search field', (tester) async {
    await pumpPage(
      tester,
      _data(thought: _live(seen: 20)),
      viewers: _viewers(20),
    );
    await openSeen(tester, 'live');
    await openSheet(tester, 20);

    expect(_sheet, findsOneWidget);
    expect(find.byKey(const ValueKey('you-viewers-search')), findsNothing);
  });

  testWidgets('21 viewers get a search field', (tester) async {
    await pumpPage(
      tester,
      _data(thought: _live(seen: 21)),
      viewers: _viewers(21),
    );
    await openSeen(tester, 'live');
    await openSheet(tester, 21);

    expect(find.byKey(const ValueKey('you-viewers-search')), findsOneWidget);
  });

  for (final rtl in [false, true]) {
    testWidgets(
      'the chip and the rows are mirrored in ${rtl ? 'Arabic' : 'English'}',
      (tester) async {
        await pumpPage(
          tester,
          _data(thought: _live()),
          viewers: _viewers(80),
          locale: Locale(rtl ? 'ar' : 'en'),
        );
        final chip = find.byKey(const ValueKey('you-seen-live'));
        final eye = find.descendant(
          of: chip,
          matching: find.byIcon(Icons.visibility_outlined),
        );
        final label = find.descendant(of: chip, matching: find.byType(Text));
        final half = tester.getSize(find.byType(YouPageScreen)).width / 2;

        expect(eye, findsOneWidget);
        expect(label, findsOneWidget);
        if (rtl) {
          expect(
            tester.getCenter(eye).dx,
            greaterThan(tester.getCenter(label).dx),
          );
          expect(tester.getTopLeft(chip).dx, greaterThan(half));
        } else {
          expect(
            tester.getCenter(eye).dx,
            lessThan(tester.getCenter(label).dx),
          );
          expect(tester.getTopRight(chip).dx, lessThan(half));
        }

        await openSeen(tester, 'live');
        final row = find.byKey(const ValueKey('you-viewer-p0'));
        final name = find.descendant(of: row, matching: find.text('Sara'));
        final face = find.descendant(
          of: row,
          matching: find.byKey(const ValueKey('you-viewer-face-p0')),
        );
        final ago = find.descendant(
          of: row,
          matching: find.text(rtl ? 'قبل دقيقة' : '1 min ago'),
        );

        expect(name, findsOneWidget);
        expect(face, findsOneWidget);
        if (rtl) {
          expect(
            tester.getCenter(face).dx,
            greaterThan(tester.getCenter(name).dx),
          );
          expect(
            tester.getCenter(name).dx,
            greaterThan(tester.getCenter(ago).dx),
          );
        } else {
          expect(
            tester.getCenter(face).dx,
            lessThan(tester.getCenter(name).dx),
          );
          expect(tester.getCenter(name).dx, lessThan(tester.getCenter(ago).dx));
        }
      },
    );
  }

  testWidgets('past Thoughts say why they ended; a live one says nothing', (
    tester,
  ) async {
    final expired = YouThought(
      post: _post('expired', age: const Duration(hours: 30)),
      reactions: const [],
      wroteBack: const [],
    );
    final replaced = YouThought(
      post: _post(
        'replaced',
        age: const Duration(hours: 30),
        lifetime: const Duration(hours: 2),
      ),
      reactions: const [],
      wroteBack: const [],
    );
    await pumpPage(tester, _data(thought: _live(), past: [expired, replaced]));
    Finder inCard(String id, Finder f) => find.descendant(
      of: find.byKey(ValueKey('you-thought-$id')),
      matching: f,
    );

    expect(
      inCard('expired', find.byIcon(Icons.hourglass_bottom_rounded)),
      findsOneWidget,
    );
    expect(
      inCard('expired', find.byIcon(Icons.swap_horiz_rounded)),
      findsNothing,
    );
    expect(inCard('expired', find.bySemanticsLabel('Expired')), findsOneWidget);
    expect(inCard('expired', find.byTooltip('Expired')), findsOneWidget);

    expect(
      inCard('replaced', find.byIcon(Icons.swap_horiz_rounded)),
      findsOneWidget,
    );
    expect(
      inCard('replaced', find.byIcon(Icons.hourglass_bottom_rounded)),
      findsNothing,
    );
    expect(
      inCard('replaced', find.bySemanticsLabel('replaced by a newer Thought')),
      findsOneWidget,
    );
    expect(
      inCard('replaced', find.byTooltip('replaced by a newer Thought')),
      findsOneWidget,
    );

    expect(
      inCard('live', find.byIcon(Icons.hourglass_bottom_rounded)),
      findsNothing,
    );
    expect(inCard('live', find.byIcon(Icons.swap_horiz_rounded)), findsNothing);

    expect(
      find.byKey(const ValueKey('you-seen-expired')),
      findsOneWidget,
      reason: 'past Thoughts keep their seen chip',
    );
    expect(inCard('expired', find.text('No views yet')), findsOneWidget);
  });

  testWidgets('the Arabic past icon carries the Arabic words', (tester) async {
    final replaced = YouThought(
      post: _post(
        'replaced',
        age: const Duration(hours: 30),
        lifetime: const Duration(hours: 2),
      ),
      reactions: const [],
      wroteBack: const [],
    );
    await pumpPage(tester, _data(past: [replaced]), locale: const Locale('ar'));

    expect(find.bySemanticsLabel('استُبدلت بخاطرة أحدث'), findsOneWidget);
  });
}
