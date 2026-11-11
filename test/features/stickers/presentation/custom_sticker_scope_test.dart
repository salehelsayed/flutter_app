import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/stickers/domain/sticker_catalog.dart';
import 'package:flutter_app/features/stickers/presentation/custom_sticker_scope.dart';
import 'package:flutter_app/features/stickers/presentation/sticker_panel.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_custom_sticker_library.dart';

final _catalog = StickerCatalog.parse(
  File('assets/stickers/packs.json').readAsStringSync(),
  includeTestOnly: false,
);

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: home),
);

void main() {
  testWidgets('without a scope there is no My stickers source', (tester) async {
    MyStickersSource? source;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            source = myStickersFromScope(context, onSend: (_) {});
            return const SizedBox();
          },
        ),
      ),
    );

    expect(source, isNull);
  });

  testWidgets('Create in the scoped My stickers tab opens the source sheet', (
    tester,
  ) async {
    final library = FakeCustomStickerLibrary();
    final sent = <String>[];
    await tester.pumpWidget(
      _app(
        CustomStickerScope(
          library: library,
          child: Builder(
            builder: (context) {
              final source = myStickersFromScope(context, onSend: sent.add)!;
              expect(source.library, same(library));
              return Align(
                alignment: Alignment.bottomCenter,
                child: StickerPanel(
                  catalog: _catalog,
                  recentIds: const ['orbit_crew.tux.approved'],
                  onSend: (_) {},
                  myStickers: source,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sticker-tab-mine')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('my-sticker-create')));
    await tester.pumpAndSettle();

    expect(find.text('New sticker'), findsOneWidget);
    expect(find.text('Record clip'), findsOneWidget);
  });
}
