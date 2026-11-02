import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/features/stickers/data/sticker_recents_store.dart';
import 'package:flutter_app/features/stickers/domain/sticker_catalog.dart';
import 'package:flutter_app/features/stickers/domain/sticker_selection.dart';
import 'package:flutter_app/features/stickers/presentation/sticker_panel.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

final _catalog = StickerCatalog.parse(
  File('assets/stickers/packs.json').readAsStringSync(),
  includeTestOnly: false,
);

Future<List<String>> _pumpPanel(
  WidgetTester tester, {
  List<String> recentIds = const [],
  Locale locale = const Locale('en'),
  StickerCatalog? catalog,
}) async {
  final sent = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: StickerPanel(
            catalog: catalog ?? _catalog,
            recentIds: recentIds,
            onSend: (sticker) => sent.add(sticker.id),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return sent;
}

List<String> _visibleStickerIds(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('sticker-cell-'),
      ),
    )
    .map((w) => (w.key! as ValueKey<String>).value.substring(13))
    .toList();

void main() {
  testWidgets('opens on the first pack when Recent is empty', (tester) async {
    final sent = await _pumpPanel(tester);

    expect(find.byKey(const ValueKey('sticker-tab-recent')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sticker-tab-orbit_crew')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sticker-tab-big_mood')), findsOneWidget);
    expect(find.byKey(const ValueKey('sticker-tab-nujoom')), findsNothing);
    expect(find.byKey(const ValueKey('sticker-group-tux')), findsOneWidget);
    expect(_visibleStickerIds(tester).take(3).toList(), [
      'orbit_crew.planet.angry',
      'orbit_crew.planet.crying',
      'orbit_crew.planet.goodnight',
    ]);

    await tester.tap(
      find.byKey(const ValueKey('sticker-cell-orbit_crew.planet.crying')),
    );
    expect(sent, ['orbit_crew.planet.crying']);
  });

  testWidgets('different Planet stickers have different accessible names', (
    tester,
  ) async {
    await _pumpPanel(tester);

    expect(find.bySemanticsLabel('Planet sticker, 1 of 11'), findsOneWidget);
    expect(find.bySemanticsLabel('Planet sticker, 2 of 11'), findsOneWidget);
    expect(find.bySemanticsLabel('Planet sticker, 4 of 11'), findsOneWidget);
    expect(find.bySemanticsLabel('Planet sticker'), findsNothing);
  });

  testWidgets('a Big Mood sticker announces the words printed on it', (
    tester,
  ) async {
    await _pumpPanel(tester);
    await tester.tap(find.byKey(const ValueKey('sticker-tab-big_mood')));
    await tester.pump();

    expect(find.bySemanticsLabel('hi.'), findsOneWidget);
    expect(find.bySemanticsLabel('Huh?'), findsOneWidget);
    expect(find.bySemanticsLabel('English sticker, 1 of 8'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sticker-group-de')));
    await tester.pump();
    expect(find.bySemanticsLabel('Nicht dein Ernst!'), findsOneWidget);
  });

  testWidgets('big_mood.en.hug, which has no words, announces its place', (
    tester,
  ) async {
    await _pumpPanel(tester);
    await tester.tap(find.byKey(const ValueKey('sticker-tab-big_mood')));
    await tester.pump();

    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('sticker-cell-big_mood.en.hug')),
          )
          .label,
      'English sticker, 2 of 8',
    );
  });

  testWidgets('German and Arabic use the approved patterns', (tester) async {
    await _pumpPanel(tester, locale: const Locale('de'));
    expect(find.bySemanticsLabel('Planet-Sticker, 1 von 11'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sticker-tab-big_mood')));
    await tester.pump();
    expect(find.bySemanticsLabel('Englisch-Sticker, 2 von 8'), findsOneWidget);
    expect(find.bySemanticsLabel('hi.'), findsOneWidget);

    await _pumpPanel(tester, locale: const Locale('ar'));
    await tester.tap(find.byKey(const ValueKey('sticker-tab-orbit_crew')));
    await tester.pump();
    expect(find.bySemanticsLabel('ملصق كوكب، 2 من 11'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sticker-tab-big_mood')));
    await tester.pump();
    expect(find.bySemanticsLabel('ملصق الإنجليزية، 2 من 8'), findsOneWidget);
    expect(find.bySemanticsLabel('Huh?'), findsOneWidget);
  });

  testWidgets('a round face picks the group', (tester) async {
    await _pumpPanel(tester);

    await tester.tap(find.byKey(const ValueKey('sticker-group-capybara')));
    await tester.pump();

    expect(
      _visibleStickerIds(
        tester,
      ).every((id) => id.startsWith('orbit_crew.capybara.')),
      isTrue,
    );
    expect(_visibleStickerIds(tester), isNotEmpty);
  });

  testWidgets('swiping the grid moves to the next and previous pack', (
    tester,
  ) async {
    await _pumpPanel(tester);

    await tester.fling(
      find.byKey(const ValueKey('sticker-grid')),
      const Offset(-300, 0),
      1000,
    );
    await tester.pump();
    expect(_visibleStickerIds(tester).first, startsWith('big_mood.en.'));
    expect(find.byKey(const ValueKey('sticker-group-de')), findsOneWidget);

    await tester.fling(
      find.byKey(const ValueKey('sticker-grid')),
      const Offset(300, 0),
      1000,
    );
    await tester.pump();
    expect(_visibleStickerIds(tester).first, 'orbit_crew.planet.angry');
  });

  testWidgets('opens on Recent, newest first, when it has stickers', (
    tester,
  ) async {
    final recent = withRecentSticker(
      withRecentSticker(
        withRecentSticker(const [], 'orbit_crew.tux.approved'),
        'big_mood.en.hug',
      ),
      'orbit_crew.tux.approved',
    );
    await _pumpPanel(tester, recentIds: recent);

    expect(_visibleStickerIds(tester), [
      'orbit_crew.tux.approved',
      'big_mood.en.hug',
    ]);
    expect(find.byKey(const ValueKey('sticker-group-tux')), findsNothing);
  });

  test('Recent drops duplicates and keeps the newest 16', () {
    var recent = const <String>[];
    for (var i = 0; i < 20; i++) {
      recent = withRecentSticker(recent, 's$i');
    }
    recent = withRecentSticker(recent, 's10');

    expect(recent, [
      's10', 's19', 's18', 's17', 's16', 's15', 's14', 's13', //
      's12', 's11', 's9', 's8', 's7', 's6', 's5', 's4',
    ]);
  });

  testWidgets('mirrors in Arabic', (tester) async {
    await _pumpPanel(tester, locale: const Locale('ar'));

    final recentTab = tester.getCenter(
      find.byKey(const ValueKey('sticker-tab-recent')),
    );
    final firstPack = tester.getCenter(
      find.byKey(const ValueKey('sticker-tab-orbit_crew')),
    );
    expect(recentTab.dx, greaterThan(firstPack.dx));
    expect(find.bySemanticsLabel('ملصق كوكب، 1 من 11'), findsOneWidget);

    await tester.fling(
      find.byKey(const ValueKey('sticker-grid')),
      const Offset(300, 0),
      1000,
    );
    await tester.pump();
    expect(_visibleStickerIds(tester).first, startsWith('big_mood.en.'));
  });

  testWidgets('screen readers can activate faces, tabs and stickers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final sent = await _pumpPanel(tester);

    Future<void> activate(Finder finder) async {
      final node = tester.getSemantics(finder);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'the button has a tap action',
      );
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
    }

    await activate(find.bySemanticsLabel('Planet sticker, 2 of 11'));
    expect(sent, ['orbit_crew.planet.crying']);

    await activate(find.bySemanticsLabel('Capybara'));
    expect(
      _visibleStickerIds(tester).first,
      startsWith('orbit_crew.capybara.'),
    );

    await activate(find.bySemanticsLabel('Big Mood'));
    expect(_visibleStickerIds(tester).first, startsWith('big_mood.en.'));

    await activate(find.bySemanticsLabel('English sticker, 2 of 8'));
    expect(sent, ['orbit_crew.planet.crying', 'big_mood.en.hug']);

    await activate(find.bySemanticsLabel('Recent'));
    expect(find.byKey(const ValueKey('sticker-group-de')), findsNothing);
    semantics.dispose();
  });

  testWidgets('a sticker sent from the open picker shows in Recent at once', (
    tester,
  ) async {
    final store = StickerRecentsStore(FakeSecureKeyStore());
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BundledStickerPanel(
              recents: store,
              onSend: (sticker) => sent.add(sticker.id),
            ),
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 50 && find.byType(StickerPanel).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(_visibleStickerIds(tester).first, 'orbit_crew.planet.angry');

    await tester.tap(
      find.byKey(const ValueKey('sticker-cell-orbit_crew.planet.crying')),
    );
    await tester.tap(
      find.byKey(const ValueKey('sticker-cell-orbit_crew.planet.angry')),
    );
    await tester.tap(
      find.byKey(const ValueKey('sticker-cell-orbit_crew.planet.crying')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sticker-tab-recent')));
    await tester.pump();

    expect(sent, [
      'orbit_crew.planet.crying',
      'orbit_crew.planet.angry',
      'orbit_crew.planet.crying',
    ]);
    expect(_visibleStickerIds(tester), [
      'orbit_crew.planet.crying',
      'orbit_crew.planet.angry',
    ]);
    expect(await store.load(), [
      'orbit_crew.planet.crying',
      'orbit_crew.planet.angry',
    ]);
  });

  test('overlapping Recent writes keep every send, newest first', () async {
    final store = StickerRecentsStore(FakeSecureKeyStore());

    await Future.wait([
      store.recordSent('a'),
      store.recordSent('b'),
      store.recordSent('a'),
      store.recordSent('c'),
    ]);

    expect(await store.load(), ['c', 'a', 'b']);
  });

  testWidgets('a pack with one group shows no face row', (tester) async {
    final single = StickerCatalog.parse('''
{"version":1,"packs":[{"id":"solo","order":1,"status":"ship","groups":[
 {"id":"planet","order":1,"stickers":[
  {"id":"solo.planet.a","order":1,"file":"assets/stickers/orbit_crew/planet/angry.webp"}]}]}]}
''', includeTestOnly: false);
    await _pumpPanel(tester, catalog: single);

    expect(_visibleStickerIds(tester), ['solo.planet.a']);
    expect(find.byKey(const ValueKey('sticker-group-planet')), findsNothing);
  });
}
