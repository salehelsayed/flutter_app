import 'package:flutter/material.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/presentation/screens/you_page_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 11, 1, 12);

PostModel _post({Duration left = const Duration(hours: 18, minutes: 10)}) =>
    PostModel(
      id: 'post-1',
      eventId: 'event-1',
      senderPeerId: 'me',
      authorPeerId: 'me',
      authorUsername: 'Saleh',
      text: 'first coffee on the balcony',
      audience: PostAudience.allFriends(),
      createdAt: _now.subtract(const Duration(hours: 5)).toIso8601String(),
      visibleAt: _now.subtract(const Duration(hours: 5)).toIso8601String(),
      expiresAt: _now.add(left).toIso8601String(),
      isIncoming: false,
    );

YouThought _thought({
  bool reactions = true,
  bool wroteBack = true,
  Duration left = const Duration(hours: 18, minutes: 10),
}) => YouThought(
  post: _post(left: left),
  reactions: reactions
      ? [
          (
            reaction: ThoughtReaction.love,
            participants: [(peerId: 'omar', name: 'Omar')],
          ),
          (
            reaction: ThoughtReaction.applause,
            participants: [(peerId: 'layla', name: 'Layla')],
          ),
        ]
      : const [],
  wroteBack: wroteBack
      ? const [
          YouWroteBack(peerId: 'nour', name: 'Nour', hasUnread: true),
          YouWroteBack(peerId: 'sara', name: 'Sara', hasUnread: false),
          YouWroteBack(peerId: 'tarek', name: 'Tarek', hasUnread: false),
        ]
      : const [],
);

YouPageData _data({YouThought? thought}) => YouPageData(
  username: 'Saleh',
  avatarBytes: null,
  friendCount: 41,
  thought: thought,
);

Finder _keysStartingWith(String prefix) => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith(prefix),
);

void main() {
  late List<String> openedChats;
  late int composeCalls;
  late int backCalls;

  setUp(() {
    openedChats = [];
    composeCalls = 0;
    backCalls = 0;
  });

  Future<void> pumpPage(
    WidgetTester tester,
    Future<YouPageData> Function() load,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: YouPageScreen(
          load: load,
          now: () => _now,
          onBack: () => backCalls++,
          onOpenChat: (peerId) async => openedChats.add(peerId),
          onCompose: () async => composeCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('header shows the handle and the friend count', (tester) async {
    await pumpPage(tester, () async => _data());

    expect(find.text('you/ @Saleh'), findsOneWidget);
    expect(find.text('41 friends'), findsOneWidget);
  });

  testWidgets('back button calls onBack', (tester) async {
    await pumpPage(tester, () async => _data());

    await tester.tap(find.byTooltip('Back'));
    expect(backCalls, 1);
  });

  testWidgets('a live thought shows its text, reactions and replies', (
    tester,
  ) async {
    await pumpPage(tester, () async => _data(thought: _thought()));

    expect(find.text('first coffee on the balcony'), findsOneWidget);
    expect(find.text('2 reacted'), findsOneWidget);
    expect(_keysStartingWith('you-reaction-'), findsNWidgets(2));
    expect(find.text('3 wrote back · 1 new'), findsOneWidget);
    expect(_keysStartingWith('you-wrote-'), findsNWidgets(3));
    expect(find.byKey(const ValueKey('you-unread-nour')), findsOneWidget);
    expect(find.byKey(const ValueKey('you-unread-sara')), findsNothing);
    expect(find.byKey(const ValueKey('you-unread-tarek')), findsNothing);
    expect(_keysStartingWith('you-unread-'), findsOneWidget);
  });

  testWidgets('the live line rounds the hours left up', (tester) async {
    await pumpPage(tester, () async => _data(thought: _thought()));

    expect(find.text('still up for friends · gone in 19 h'), findsOneWidget);
  });

  testWidgets('tapping a wrote-back face opens that chat', (tester) async {
    await pumpPage(tester, () async => _data(thought: _thought()));

    await tester.tap(find.byKey(const ValueKey('you-wrote-sara')));
    await tester.pumpAndSettle();

    expect(openedChats, ['sara']);
  });

  testWidgets('nothing on the page says who saw the thought', (tester) async {
    await pumpPage(tester, () async => _data(thought: _thought()));

    expect(
      find.textContaining(RegExp('seen', caseSensitive: false)),
      findsNothing,
    );
  });

  testWidgets('rows with a zero count are left out', (tester) async {
    await pumpPage(
      tester,
      () async => _data(thought: _thought(reactions: false, wroteBack: false)),
    );

    expect(find.text('first coffee on the balcony'), findsOneWidget);
    expect(find.textContaining('reacted'), findsNothing);
    expect(find.textContaining('wrote back'), findsNothing);
    expect(_keysStartingWith('you-reaction-'), findsNothing);
    expect(_keysStartingWith('you-wrote-'), findsNothing);
  });

  testWidgets('replies with nothing unread show no new count', (tester) async {
    await pumpPage(
      tester,
      () async => _data(
        thought: YouThought(
          post: _post(),
          reactions: const [],
          wroteBack: const [
            YouWroteBack(peerId: 'sara', name: 'Sara', hasUnread: false),
          ],
        ),
      ),
    );

    expect(find.text('1 wrote back'), findsOneWidget);
    expect(find.textContaining('new'), findsNothing);
  });

  testWidgets('without a thought the page says nothing is shared', (
    tester,
  ) async {
    await pumpPage(tester, () async => _data());

    expect(find.text('Nothing shared right now'), findsOneWidget);
    expect(find.textContaining('still up for'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('you-composer')));
    await tester.pumpAndSettle();

    expect(composeCalls, 1);
  });

  testWidgets('the page reloads after a share', (tester) async {
    var loads = 0;
    await pumpPage(tester, () async {
      loads++;
      return _data(thought: loads > 1 ? _thought() : null);
    });
    expect(find.text('Nothing shared right now'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('you-composer')));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.text('first coffee on the balcony'), findsOneWidget);
    expect(find.text('Nothing shared right now'), findsNothing);
  });

  testWidgets('a thought with an hour or less left reads 1 h', (tester) async {
    await pumpPage(
      tester,
      () async => _data(thought: _thought(left: const Duration(minutes: 20))),
    );

    expect(find.text('still up for friends · gone in 1 h'), findsOneWidget);
  });
}
