import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/features/stickers/domain/sticker_catalog.dart';
import 'package:flutter_app/features/stickers/presentation/sticker_panel.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fixtures/ios_semantics_frames.dart';
import '../fake_custom_sticker_library.dart';

const _bound = Duration(seconds: 3);
const _iphone13 = Size(390, 844);
const _dpr = 3.0;

Finder _tile(String id) => find.byKey(ValueKey('my-sticker-$id'));
Finder _delete(String id) => find.byKey(ValueKey('my-sticker-delete-$id'));

bool _sameFrame(Rect a, Rect b) =>
    (a.left - b.left).abs() < .01 &&
    (a.top - b.top).abs() < .01 &&
    (a.right - b.right).abs() < .01 &&
    (a.bottom - b.bottom).abs() < .01;

void main() {
  final binding = IosSemanticsRecordingBinding();
  final catalog = StickerCatalog.parse(
    File('assets/stickers/packs.json').readAsStringSync(),
    includeTestOnly: false,
  );

  for (final accessible in [false, true]) {
    testWidgets('My Stickers keeps iOS frames through Manage, reorder and Done '
        '(accessibleNavigation: $accessible)', (tester) async {
      tester.view.physicalSize = _iphone13 * _dpr;
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(accessibleNavigation: accessible);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final semantics = tester.ensureSemantics();
      binding.clearSemanticsUpdates();

      const original = ['a', 'b', 'c'];
      const moved = ['c', 'a', 'b'];
      final library = FakeCustomStickerLibrary(ids: original);
      final done = find.byKey(const ValueKey('my-stickers-done'));
      final create = find.byKey(const ValueKey('my-sticker-create'));
      final mismatches = <String>[];

      void checkPaintedOrder(List<String> ids) {
        final centers = [for (final id in ids) tester.getCenter(_tile(id)).dx];
        expect(centers, orderedEquals([...centers]..sort()));
      }

      void capture(String stage, {required bool managing}) {
        final nativeFrames = [
          ('recorded', binding.replayIosFrames(_dpr)),
          ('reverse', binding.replayIosFrames(_dpr, reverseNodeOrder: true)),
        ];

        Rect check(Finder finder, String name) {
          expect(finder, findsOneWidget);
          final node = tester.getSemantics(finder);
          final semantics = flutterSemanticsFrame(node, _dpr);
          final paint = tester.getRect(finder);
          if (!_sameFrame(semantics, paint)) {
            mismatches.add('$stage $name Flutter $semantics, paint $paint');
          }
          for (final (order, byId) in nativeFrames) {
            final native = byId[node.id];
            if (native == null || !_sameFrame(native, semantics)) {
              mismatches.add(
                '$stage $name iOS ($order) $native, Flutter $semantics',
              );
            }
          }
          return paint;
        }

        for (final id in library.ids) {
          check(_tile(id), 'tile $id');
          if (managing) {
            check(_delete(id), 'delete badge $id');
          } else {
            expect(_delete(id), findsNothing);
          }
        }
        if (managing) {
          final frame = check(done, 'Done');
          final screen = Offset.zero & _iphone13;
          expect(frame.isEmpty, isFalse);
          expect(frame.intersect(screen), frame);
          expect(done.hitTestable(), findsOneWidget);
          expect(
            tester
                .getSemantics(done)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );
        } else {
          expect(done, findsNothing);
        }
      }

      try {
        await tester
            .pumpWidget(
              MaterialApp(
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: StickerPanel(
                      catalog: catalog,
                      recentIds: const ['orbit_crew.tux.approved'],
                      onSend: (_) {},
                      myStickers: MyStickersSource(
                        library: library,
                        onSend: (_) {},
                        onCreate: () {},
                      ),
                    ),
                  ),
                ),
              ),
            )
            .timeout(_bound);
        await tester.pump().timeout(_bound);
        await tester.pump().timeout(_bound);
        expect(create, findsOneWidget);
        checkPaintedOrder(original);
        capture('normal', managing: false);

        await tester.longPress(_tile('a')).timeout(_bound);
        await tester.pump().timeout(_bound);
        await tester.pump(const Duration(milliseconds: 250)).timeout(_bound);
        expect(create, findsNothing);
        capture('manage', managing: true);

        final start = tester.getCenter(_tile('c'));
        final target = tester.getCenter(_tile('a'));
        final drag = await tester.startGesture(start).timeout(_bound);
        try {
          await tester.pump(const Duration(milliseconds: 600)).timeout(_bound);
          for (var step = 1; step <= 10; step++) {
            await drag
                .moveTo(Offset.lerp(start, target, step / 10)!)
                .timeout(_bound);
            await tester.pump(const Duration(milliseconds: 16)).timeout(_bound);
          }
          expect(library.reorderCalls, isEmpty);
          capture('drag', managing: true);
        } finally {
          await drag.up().timeout(_bound);
        }
        await tester.pump().timeout(_bound);
        await tester.pump().timeout(_bound);
        expect(library.reorderCalls, [moved]);
        final saved = await library.list().timeout(_bound);
        expect(saved.map((row) => row.id), orderedEquals(moved));
        checkPaintedOrder(moved);
        capture('drop', managing: true);

        await tester.tap(done).timeout(_bound);
        await tester.pump().timeout(_bound);
        await tester.pump(const Duration(milliseconds: 250)).timeout(_bound);
        expect(create, findsOneWidget);
        checkPaintedOrder(moved);
        capture('done', managing: false);
        expect(mismatches, isEmpty);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink()).timeout(_bound);
      }
    });
  }
}
