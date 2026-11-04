import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/features/posts/presentation/widgets/thought_audience.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

ContactModel _friend(String name) => ContactModel(
  peerId: 'peer-$name',
  publicKey: 'pk-$name',
  rendezvous: 'rendezvous',
  username: name,
  signature: 'signature',
  scannedAt: '2026-11-01T00:00:00.000Z',
);

final _friends = [_friend('layla'), _friend('omar'), _friend('nour')];

void main() {
  late FakeSecureKeyStore store;
  late ThoughtRecentPicks recent;
  late List<ComposePostResult> shared;

  setUp(() {
    store = FakeSecureKeyStore();
    recent = ThoughtRecentPicks(store);
    shared = [];
  });

  Widget scene({
    ComposePostResult? initialDraft,
    ValueChanged<ComposePostResult?>? onClosed,
    List<ContactModel>? contacts,
    Locale locale = const Locale('en'),
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ComposePostSheet(
        thoughtsOnly: true,
        eligibleContacts: contacts ?? _friends,
        recentPicks: recent,
        initialDraft: initialDraft,
        onClosed: onClosed,
        onSubmitWithOutcome: (result) async {
          shared.add(result);
          return ComposePostSubmitOutcome.keepSheetOpen;
        },
      ),
    ),
  );

  Finder chip() => find.byKey(const ValueKey('thought-audience-chip'));
  Finder rule() => find.byKey(const ValueKey('thought-composer-lifetime'));

  Future<void> write(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(ComposePostSheet),
        matching: find.byType(TextField),
      ),
      text,
    );
    await tester.pump();
  }

  Future<void> tapShare(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, List<String> names) async {
    await tester.tap(chip());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thought-audience-select')));
    await tester.pumpAndSettle();
    for (final name in names) {
      await tester.tap(find.byKey(ValueKey('thought-pick-peer-$name')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('thought-pick-done')));
    await tester.pumpAndSettle();
  }

  testWidgets('a thought goes to friends by default, with no tap', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(scene());
    expect(find.text('all friends'), findsOneWidget);
    expect(find.text('· 24 h'), findsOneWidget);
    expect(find.text('All your friends see this for 24 hours'), findsNothing);
    expect(
      find.bySemanticsLabel('All your friends see this for 24 hours'),
      findsOneWidget,
    );
    final chipRect = tester.getRect(chip());
    final ruleRect = tester.getRect(rule());
    expect(ruleRect.center.dy, moreOrLessEquals(chipRect.center.dy, epsilon: 1));
    expect(ruleRect.left, greaterThanOrEqualTo(chipRect.right));
    semantics.dispose();

    await write(tester, 'back in dahab');
    await tapShare(tester);

    expect(shared.single.audience.kind, PostAudienceKind.allFriends);
  });

  testWidgets('the audience menu has only friends and select people', (
    tester,
  ) async {
    await tester.pumpWidget(scene());
    await tester.tap(chip());
    await tester.pumpAndSettle();

    expect(find.text('all friends'), findsNWidgets(2), reason: 'chip and row');
    expect(find.text('everyone in your orbit'), findsOneWidget);
    expect(find.text('select people…'), findsOneWidget);
    expect(find.text('just this once'), findsOneWidget);
    expect(find.byType(PopupMenuItem<ThoughtAudienceChoice>), findsNWidgets(2));
  });

  testWidgets('picked people get the thought and the rule line names them', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(scene());
    await tester.tap(chip());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thought-audience-select')));
    await tester.pumpAndSettle();

    expect(find.text('Who sees this'), findsOneWidget);
    expect(
      find.text(
        'just this thought. nothing is created, nobody sees who else was '
        'picked',
      ),
      findsOneWidget,
    );
    ElevatedButton done() =>
        tester.widget(find.byKey(const ValueKey('thought-pick-done')));
    expect(done().onPressed, isNull, reason: 'nobody picked yet');

    await tester.tap(find.byKey(const ValueKey('thought-pick-peer-layla')));
    await tester.tap(find.byKey(const ValueKey('thought-pick-peer-nour')));
    await tester.pump();
    expect(find.text('Done · 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('thought-pick-done')));
    await tester.pumpAndSettle();

    expect(find.text('to 2 people'), findsOneWidget);
    expect(find.text('· 24 h'), findsOneWidget);
    expect(
      find.bySemanticsLabel('layla and nour see this for 24 hours'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('All your friends see this for 24 hours'),
      findsNothing,
    );
    semantics.dispose();

    await write(tester, 'back in dahab');
    await tapShare(tester);
    expect(shared.single.audience.kind, PostAudienceKind.pickPeople);
    expect(shared.single.audience.selectedPeerIds, ['peer-layla', 'peer-nour']);
  });

  testWidgets('choosing friends again undoes the pick', (tester) async {
    await tester.pumpWidget(scene());
    await pick(tester, ['omar']);
    expect(find.text('to 1 person'), findsOneWidget);

    await tester.tap(chip());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thought-audience-friends')));
    await tester.pumpAndSettle();

    expect(find.text('all friends'), findsOneWidget);
    await write(tester, 'for everyone');
    await tapShare(tester);
    expect(shared.single.audience.kind, PostAudienceKind.allFriends);
  });

  testWidgets('cancel keeps the audience it had', (tester) async {
    await tester.pumpWidget(scene());
    await tester.tap(chip());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thought-audience-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thought-pick-peer-omar')));
    await tester.tap(find.byKey(const ValueKey('thought-pick-cancel')));
    await tester.pumpAndSettle();

    expect(find.text('all friends'), findsOneWidget);
  });

  testWidgets('a shared pick shows as one tap under recent picks', (
    tester,
  ) async {
    await tester.pumpWidget(scene());
    await pick(tester, ['omar', 'nour']);
    await write(tester, 'reef');
    await tapShare(tester);
    expect(await recent.load(), [
      ['peer-omar', 'peer-nour'],
    ]);

    await tester.tap(chip());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thought-audience-select')));
    await tester.pumpAndSettle();
    expect(find.text('recent picks'), findsOneWidget);
    await tester.tap(find.text('omar, nour'));
    await tester.pump();
    expect(find.text('Done · 2'), findsOneWidget);
  });

  testWidgets('search narrows the list and X takes a person back out', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(scene());
    await tester.tap(chip());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thought-audience-select')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('thought-pick-search')),
      'LA',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('thought-pick-peer-layla')), findsOne);
    expect(find.byKey(const ValueKey('thought-pick-peer-omar')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('thought-pick-peer-layla')));
    await tester.pump();
    final remove = find.byKey(const ValueKey('thought-pick-remove-peer-layla'));
    expect(
      tester.getSemantics(remove),
      isSemantics(
        label: 'Remove layla',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(remove);
    await tester.pump();
    expect(find.text('Done · 0'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('thought-pick-search')),
      'zz',
    );
    await tester.pump();
    expect(find.text('no one by that name'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a swiped-away draft keeps its picked people', (tester) async {
    final semantics = tester.ensureSemantics();
    ComposePostResult? handedBack;
    await tester.pumpWidget(scene(onClosed: (draft) => handedBack = draft));
    await pick(tester, ['layla']);
    await write(tester, 'later');
    await tester.pumpWidget(const SizedBox());

    expect(handedBack?.audience.selectedPeerIds, ['peer-layla']);

    await tester.pumpWidget(scene(initialDraft: handedBack));
    await tester.pumpAndSettle();
    expect(find.text('to 1 person'), findsOneWidget);
    expect(find.bySemanticsLabel('layla sees this for 24 hours'), findsOne);
    semantics.dispose();
  });

  testWidgets('a new thought after a picked share starts at all friends', (
    tester,
  ) async {
    await tester.pumpWidget(scene());
    await pick(tester, ['omar']);
    await write(tester, 'just omar');
    await tapShare(tester);
    expect(shared.single.audience.kind, PostAudienceKind.pickPeople);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(scene());
    await tester.pumpAndSettle();
    expect(find.text('all friends'), findsOneWidget);
    await write(tester, 'for everyone');
    await tapShare(tester);
    expect(shared.last.audience.kind, PostAudienceKind.allFriends);
  });

  testWidgets('in Arabic at 390 px the chip and the rule share one row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(scene(locale: const Locale('ar')));
    expect(find.text('كل الأصدقاء'), findsOneWidget);
    expect(find.text('· 24 س'), findsOneWidget);
    final chipRect = tester.getRect(chip());
    final ruleRect = tester.getRect(rule());
    expect(ruleRect.center.dy, moreOrLessEquals(chipRect.center.dy, epsilon: 1));
    expect(ruleRect.right, lessThanOrEqualTo(chipRect.left));
    expect(ruleRect.left, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a draft whose only picked friend is gone shares with nobody '
      'until the user chooses again', (tester) async {
    ComposePostResult? handedBack;
    await tester.pumpWidget(
      scene(
        contacts: [_friends[1]],
        onClosed: (draft) => handedBack = draft,
        initialDraft: ComposePostResult(
          text: 'for layla only',
          audience: PostAudience.pickPeople(['peer-layla']),
        ),
      ),
    );
    await tester.pumpAndSettle();

    ElevatedButton shareButton() =>
        tester.widget(find.byKey(const ValueKey('thought-composer-share')));
    expect(shareButton().onPressed, isNull);
    expect(find.text('to 0 people'), findsOneWidget);
    expect(find.text('All your friends see this for 24 hours'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    expect(handedBack?.audience.kind, PostAudienceKind.pickPeople);
    expect(handedBack?.audience.selectedPeerIds, isEmpty);
    expect(shared, isEmpty);
  });

  testWidgets('choosing friends after the pick is gone shares with friends', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(
        contacts: [_friends[1]],
        initialDraft: ComposePostResult(
          text: 'for layla only',
          audience: PostAudience.pickPeople(['peer-layla']),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(chip());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thought-audience-friends')));
    await tester.pumpAndSettle();
    await tapShare(tester);
    expect(shared.single.audience.kind, PostAudienceKind.allFriends);
  });

  testWidgets('a picked friend who is gone by reopening is left out', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(
        contacts: [_friends[1]],
        initialDraft: ComposePostResult(
          text: 'later',
          audience: PostAudience.pickPeople(['peer-layla', 'peer-omar']),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('omar sees this for 24 hours'), findsOneWidget);
    await tapShare(tester);
    expect(shared.single.audience.selectedPeerIds, ['peer-omar']);
  });
}
