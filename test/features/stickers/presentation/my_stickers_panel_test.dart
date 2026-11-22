import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/features/stickers/data/sticker_recents_store.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';
import 'package:flutter_app/features/stickers/domain/sticker_catalog.dart';
import 'package:flutter_app/features/stickers/presentation/sticker_panel.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../fake_custom_sticker_library.dart';

final _catalog = StickerCatalog.parse(
  File('assets/stickers/packs.json').readAsStringSync(),
  includeTestOnly: false,
);

class _Harness {
  final sent = <String>[];
  var creates = 0;
}

Future<_Harness> _pump(
  WidgetTester tester,
  FakeCustomStickerLibrary library, {
  Locale locale = const Locale('en'),
}) async {
  final harness = _Harness();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: StickerPanel(
            catalog: _catalog,
            recentIds: const ['orbit_crew.tux.approved'],
            onSend: (_) {},
            myStickers: MyStickersSource(
              library: library,
              onSend: harness.sent.add,
              onCreate: () => harness.creates++,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return harness;
}

/// The My stickers grid, in reading order: 'create' and sticker ids.
List<String> _myGrid(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate((w) {
        final key = w.key;
        if (key is! ValueKey<String>) return false;
        return key.value.startsWith('my-sticker-') &&
            !key.value.startsWith('my-sticker-delete-');
      }),
    )
    .map((w) => (w.key! as ValueKey<String>).value.substring(11))
    .toList();

Finder _sticker(String id) => find.byKey(ValueKey('my-sticker-$id'));

Finder get _deleteBadges => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('my-sticker-delete-'),
);

Future<void> _customAction(
  WidgetTester tester,
  Finder finder,
  String label,
) async {
  final node = tester.getSemantics(finder);
  final id = CustomSemanticsAction.getIdentifier(
    CustomSemanticsAction(label: label),
  );
  expect(
    node.getSemanticsData().customSemanticsActionIds,
    contains(id),
    reason: 'the sticker offers "$label"',
  );
  node.owner!.performAction(node.id, SemanticsAction.customAction, id);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('with the flag off the picker has no My stickers tab', (
    tester,
  ) async {
    expect(kCustomStickersEnabled, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BundledStickerPanel(
              recents: StickerRecentsStore(FakeSecureKeyStore()),
              onSend: (_) {},
              myStickers: MyStickersSource(
                library: FakeCustomStickerLibrary(ids: ['a', 'b']),
                onSend: (_) {},
                onCreate: () {},
              ),
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

    expect(find.byType(StickerPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('sticker-tab-mine')), findsNothing);
    expect(find.byKey(const ValueKey('my-sticker-create')), findsNothing);
    final recent = tester.getCenter(
      find.byKey(const ValueKey('sticker-tab-recent')),
    );
    final pack = tester.getCenter(
      find.byKey(const ValueKey('sticker-tab-orbit_crew')),
    );
    expect(recent.dx, lessThan(pack.dx));
  });

  testWidgets('My stickers is the first tab and opens with Create first', (
    tester,
  ) async {
    final library = FakeCustomStickerLibrary(ids: ['a', 'b', 'c']);
    await _pump(tester, library);

    final mine = tester.getCenter(
      find.byKey(const ValueKey('sticker-tab-mine')),
    );
    final recent = tester.getCenter(
      find.byKey(const ValueKey('sticker-tab-recent')),
    );
    expect(mine.dx, lessThan(recent.dx));
    expect(find.bySemanticsLabel('My stickers'), findsOneWidget);
    expect(_myGrid(tester), ['create', 'a', 'b', 'c']);
    expect(find.bySemanticsLabel('Sticker 2 of 3'), findsOneWidget);
  });

  testWidgets('tapping a sticker sends its id; Create calls onCreate', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      FakeCustomStickerLibrary(ids: ['a', 'b', 'c']),
    );

    await tester.tap(_sticker('b'));
    await tester.tap(find.byKey(const ValueKey('my-sticker-create')));
    await tester.pump();

    expect(harness.sent, ['b']);
    expect(harness.creates, 1);
  });

  testWidgets('an empty library shows only Create and keeps Recent first', (
    tester,
  ) async {
    final harness = await _pump(tester, FakeCustomStickerLibrary());

    expect(find.byKey(const ValueKey('sticker-tab-mine')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sticker-cell-orbit_crew.tux.approved')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('sticker-tab-mine')));
    await tester.pump();

    expect(_myGrid(tester), ['create']);
    await tester.tap(find.byKey(const ValueKey('my-sticker-create')));
    expect(harness.creates, 1);
  });

  testWidgets('a sticker added while the panel is open appears first', (
    tester,
  ) async {
    final library = FakeCustomStickerLibrary(ids: ['a']);
    await _pump(tester, library);

    await tester.runAsync(() => library.admit(fakeStickerAsset('new')));
    await tester.pump();
    await tester.pump();

    expect(_myGrid(tester), ['create', 'custom-2', 'a']);
  });

  testWidgets('a custom WebP animates only in the visible grid', (
    tester,
  ) async {
    const bound = Duration(seconds: 3);
    final root = Directory.systemTemp.createTempSync('my-stickers-animation-');
    addTearDown(() => root.deleteSync(recursive: true));
    final frame = img.Image(width: 8, height: 8, frameDuration: 80)
      ..clear(img.ColorRgb8(255, 0, 0))
      ..addFrame(
        img.Image(width: 8, height: 8, frameDuration: 80)
          ..clear(img.ColorRgb8(0, 0, 255)),
      );
    final webp = img.WebPEncoder().encode(frame);
    final animation = File('${root.path}/sticker.webp')..writeAsBytesSync(webp);
    final library = FakeCustomStickerLibrary(
      ids: List.generate(8, (i) => 'filler-$i'),
    );
    final sticker = await library
        .admit(
          NormalizedStickerAsset(
            filePath: animation.path,
            sha256Hex: 'animation',
            mime: 'image/webp',
            byteLength: webp.length,
            width: 8,
            height: 8,
            frameCount: 2,
            durationMs: 160,
          ),
        )
        .timeout(bound);
    final harness = await _pump(tester, library).timeout(bound);
    final tile = _sticker(sticker.id);
    expect(tile.hitTestable(), findsOneWidget);

    final provider = tester
        .widget<Image>(find.descendant(of: tile, matching: find.byType(Image)))
        .image;
    final key = await provider
        .obtainKey(ImageConfiguration.empty)
        .timeout(bound);
    final cache = PaintingBinding.instance.imageCache;
    final raw = find.descendant(of: tile, matching: find.byType(RawImage));
    RawImage? renderedImage() => tester.widgetList<RawImage>(raw).firstOrNull;

    Future<void> pumpUntil(bool Function() condition) async {
      final elapsed = Stopwatch()..start();
      while (!condition() && elapsed.elapsed < bound) {
        await tester
            .runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            )
            .timeout(bound);
        await tester.pump(const Duration(milliseconds: 20)).timeout(bound);
      }
      expect(condition(), isTrue);
    }

    Future<void> expectAnimation() async {
      await pumpUntil(() => renderedImage()?.image != null);
      final firstFrame = renderedImage()!.image;
      await pumpUntil(() {
        final image = renderedImage()?.image;
        return image != null && !identical(image, firstFrame);
      });
      expect(cache.statusForKey(key).live, isTrue);
    }

    await expectAnimation();
    final thumbnail = find.descendant(
      of: find.byKey(const ValueKey('sticker-tab-mine')),
      matching: find.byType(RawImage),
    );
    final thumbnailFrame = tester.widget<RawImage>(thumbnail).image;
    expect(thumbnailFrame, isNotNull);

    final grid = find.byType(GridView);
    final scroller = tester.state<ScrollableState>(
      find.descendant(of: grid, matching: find.byType(Scrollable)),
    );
    scroller.position.jumpTo(tester.getSize(tile).height + 12);
    await tester.pump().timeout(bound);
    expect(tile.hitTestable(), findsNothing);
    expect(
      find.byKey(ValueKey('my-sticker-${sticker.id}'), skipOffstage: false),
      findsNothing,
      reason: 'the hidden tile leaves the widget tree',
    );
    expect(cache.statusForKey(key).live, isFalse);
    expect(tester.widget<RawImage>(thumbnail).image, same(thumbnailFrame));

    scroller.position.jumpTo(0);
    await tester.pump().timeout(bound);
    expect(tile.hitTestable(), findsOneWidget);
    await expectAnimation();
    expect(tester.widget<RawImage>(thumbnail).image, same(thumbnailFrame));
    await tester.tap(tile).timeout(bound);
    expect(harness.sent, [sticker.id]);
    await tester.pumpWidget(const SizedBox.shrink()).timeout(bound);
  });

  testWidgets('long-press enters manage mode; delete removes the sticker', (
    tester,
  ) async {
    final library = FakeCustomStickerLibrary(ids: ['a', 'b', 'c']);
    final harness = await _pump(tester, library);

    await tester.longPress(_sticker('b'));
    await tester.pump();

    expect(_deleteBadges, findsNWidgets(3));
    expect(find.text('Drag to reorder'), findsOneWidget);
    expect(find.byKey(const ValueKey('my-stickers-done')), findsOneWidget);
    expect(_myGrid(tester), ['a', 'b', 'c']);
    await tester.tap(_sticker('a'));
    expect(harness.sent, isEmpty);

    await tester.tap(find.byKey(const ValueKey('my-sticker-delete-b')));
    await tester.pump();
    await tester.pump();

    expect(library.ids, ['a', 'c']);
    expect(_myGrid(tester), ['a', 'c']);
    expect(_deleteBadges, findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('my-stickers-done')));
    await tester.pump();
    expect(_deleteBadges, findsNothing);
    expect(_myGrid(tester), ['create', 'a', 'c']);
  });

  testWidgets('manage mode exposes each localized Delete as a button', (
    tester,
  ) async {
    const bound = Duration(seconds: 3);
    final semantics = tester.ensureSemantics();
    try {
      for (final locale in const [Locale('en'), Locale('de'), Locale('ar')]) {
        final library = FakeCustomStickerLibrary(ids: ['a', 'b', 'c']);
        final harness = await _pump(
          tester,
          library,
          locale: locale,
        ).timeout(bound);
        await tester.longPress(_sticker('b')).timeout(bound);
        await tester.pump().timeout(bound);

        final context = tester.element(find.byType(StickerPanel));
        final l10n = AppLocalizations.of(context)!;
        expect(Localizations.localeOf(context), locale);
        expect(find.bySemanticsLabel(l10n.stickers_delete), findsNWidgets(3));
        expect(
          find.bySemanticsLabel(l10n.stickers_mine_semantics(2, 3)),
          findsOneWidget,
        );

        final badge = find.byKey(const ValueKey('my-sticker-delete-b'));
        final node = tester.getSemantics(badge);
        final data = node.getSemanticsData();
        expect(node.id, isNot(tester.getSemantics(_sticker('b')).id));
        expect(data.label, l10n.stickers_delete);
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);

        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pump().timeout(bound);
        await tester.pump().timeout(bound);

        expect(library.ids, ['a', 'c']);
        expect(harness.sent, isEmpty);
        expect(find.bySemanticsLabel(l10n.stickers_delete), findsNWidgets(2));
        expect(find.byKey(const ValueKey('my-stickers-done')), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink()).timeout(bound);
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'a brief press on the sticker delete badge removes that sticker',
    (tester) async {
      const bound = Duration(seconds: 3);
      final library = FakeCustomStickerLibrary(ids: ['a', 'b', 'c']);
      final harness = await _pump(tester, library).timeout(bound);
      final sticker = _sticker('b');

      await tester.longPress(sticker).timeout(bound);
      await tester.pump().timeout(bound);
      final badge = find.byKey(const ValueKey('my-sticker-delete-b'));
      expect(badge.hitTestable(), findsOneWidget);

      final touch = await tester
          .startGesture(tester.getCenter(badge))
          .timeout(bound);
      await tester.pump(const Duration(milliseconds: 250)).timeout(bound);
      expect(sticker, findsOneWidget);
      await touch.up().timeout(bound);
      await tester.pump().timeout(bound);
      await tester.pump().timeout(bound);

      expect(
        sticker,
        findsNothing,
        reason:
            'releasing a stationary touch on the visible X removes the tile',
      );
      expect(_myGrid(tester), ['a', 'c']);
      expect(library.ids, ['a', 'c']);
      expect(library.reorderCalls, isEmpty);
      expect(harness.sent, isEmpty);
    },
  );

  testWidgets('dragging a sticker onto another reorders the library', (
    tester,
  ) async {
    final library = FakeCustomStickerLibrary(ids: ['a', 'b', 'c']);
    await _pump(tester, library);
    await tester.longPress(_sticker('a'));
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(_sticker('c')));
    await tester.pump(const Duration(milliseconds: 600));
    final target = tester.getCenter(_sticker('a'));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(
        Offset.lerp(tester.getCenter(_sticker('c')), target, i / 10)!,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(library.reorderCalls, [
      ['c', 'a', 'b'],
    ]);
    expect(library.ids, ['c', 'a', 'b']);
    expect(_myGrid(tester), ['c', 'a', 'b']);
  });

  testWidgets('screen readers can move and delete stickers without drags', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final library = FakeCustomStickerLibrary(ids: ['a', 'b', 'c']);
    await _pump(tester, library);
    await tester.longPress(_sticker('a'));
    await tester.pump();

    await _customAction(tester, _sticker('a'), 'Move later');
    expect(library.ids, ['b', 'a', 'c']);

    await _customAction(tester, _sticker('c'), 'Move earlier');
    expect(library.ids, ['b', 'c', 'a']);
    expect(library.reorderCalls, [
      ['b', 'a', 'c'],
      ['b', 'c', 'a'],
    ]);

    await _customAction(tester, _sticker('c'), 'Delete');
    expect(library.ids, ['b', 'a']);
    expect(_myGrid(tester), ['b', 'a']);
    semantics.dispose();
  });

  testWidgets('a stale reorder reloads quietly and stays in manage mode', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final library = FakeCustomStickerLibrary(ids: ['a', 'b', 'c']);
    await _pump(tester, library);
    await tester.longPress(_sticker('a'));
    await tester.pump();
    final listsBefore = library.listCalls;

    library.failNextReorder = true;
    await _customAction(tester, _sticker('a'), 'Move later');

    expect(library.reorderCalls, [
      ['b', 'a', 'c'],
    ]);
    expect(library.ids, ['a', 'b', 'c']);
    expect(library.listCalls, listsBefore + 1);
    expect(_myGrid(tester), ['a', 'b', 'c']);
    expect(find.byKey(const ValueKey('my-stickers-done')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('tabs and grid mirror in Arabic', (tester) async {
    await _pump(
      tester,
      FakeCustomStickerLibrary(ids: ['a', 'b']),
      locale: const Locale('ar'),
    );

    final mine = tester.getCenter(
      find.byKey(const ValueKey('sticker-tab-mine')),
    );
    final recent = tester.getCenter(
      find.byKey(const ValueKey('sticker-tab-recent')),
    );
    expect(mine.dx, greaterThan(recent.dx));
    expect(find.bySemanticsLabel('ملصقاتي'), findsOneWidget);
    final create = tester.getCenter(
      find.byKey(const ValueKey('my-sticker-create')),
    );
    expect(create.dx, greaterThan(tester.getCenter(_sticker('a')).dx));
    expect(
      tester.getCenter(_sticker('a')).dx,
      greaterThan(tester.getCenter(_sticker('b')).dx),
    );
  });

  Widget panelWith(MyStickersSource? source) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: StickerPanel(
          catalog: _catalog,
          recentIds: const ['orbit_crew.tux.approved'],
          onSend: (_) {},
          myStickers: source,
        ),
      ),
    ),
  );

  MyStickersSource sourceFor(FakeCustomStickerLibrary library) =>
      MyStickersSource(library: library, onSend: (_) {}, onCreate: () {});

  testWidgets(
    'a load still pending when My stickers is removed changes nothing',
    (tester) async {
      final old = FakeCustomStickerLibrary(ids: ['a1'])
        ..listGate = Completer<void>();
      await tester.pumpWidget(panelWith(sourceFor(old)));
      await tester.pump();

      await tester.pumpWidget(panelWith(null));
      await tester.pump();
      old.listGate!.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('sticker-tab-mine')), findsNothing);
      expect(_myGrid(tester), isEmpty);
    },
  );

  testWidgets(
    'a load still pending when the library is replaced never shows its rows',
    (tester) async {
      final old = FakeCustomStickerLibrary(ids: ['a1'])
        ..listGate = Completer<void>();
      final replacement = FakeCustomStickerLibrary(ids: ['b1']);
      await tester.pumpWidget(panelWith(sourceFor(old)));
      await tester.pump();

      await tester.pumpWidget(panelWith(sourceFor(replacement)));
      await tester.pump();
      await tester.pump();
      old.listGate!.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_myGrid(tester), ['create', 'b1']);
    },
  );
}
