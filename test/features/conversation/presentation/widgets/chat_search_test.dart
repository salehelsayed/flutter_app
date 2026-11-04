import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/chat_search.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> shown;
  late int closed;
  late Map<String, Completer<List<String>>> slow;

  ChatSearchController controller() => ChatSearchController(
    search: (query) {
      final pending = slow[query];
      if (pending != null) return pending.future;
      return Future.value(switch (query) {
        'dahab' => ['m3', 'm1', 'm0'],
        _ => const <String>[],
      });
    },
    onShow: shown.add,
    onClosed: () => closed++,
  );

  setUp(() {
    shown = [];
    closed = 0;
    slow = {};
  });

  Widget scene(ChatSearchController search, {Locale? locale}) => MaterialApp(
    locale: locale ?? const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      extensions: <ThemeExtension<dynamic>>[BackgroundReadableColors.dark],
    ),
    home: Scaffold(body: ChatSearchBar(controller: search)),
  );

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
  }

  IconButton button(WidgetTester tester, String tooltip) => tester.widget(
    find.ancestor(
      of: find.byTooltip(tooltip),
      matching: find.byType(IconButton),
    ),
  );

  testWidgets('typing finds matches and shows the newest first', (
    tester,
  ) async {
    final search = controller()..open();
    addTearDown(search.dispose);
    await tester.pumpWidget(scene(search));
    expect(find.text('Search…'), findsOneWidget);

    await type(tester, 'dahab');
    expect(find.text('1 of 3'), findsOneWidget);
    expect(search.currentId, 'm3');
    expect(shown, ['m3']);
  });

  testWidgets(
    'up steps to older matches, down to newer, stopping at the ends',
    (tester) async {
      final search = controller()..open();
      addTearDown(search.dispose);
      await tester.pumpWidget(scene(search));
      await type(tester, 'dahab');
      expect(button(tester, 'Next match').onPressed, isNull);

      await tester.tap(find.byTooltip('Previous match'));
      await tester.pump();
      expect(find.text('2 of 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous match'));
      await tester.pump();
      expect(find.text('3 of 3'), findsOneWidget);
      expect(button(tester, 'Previous match').onPressed, isNull);

      await tester.tap(find.byTooltip('Next match'));
      await tester.pump();
      expect(find.text('2 of 3'), findsOneWidget);
      expect(shown, ['m3', 'm1', 'm0', 'm1']);
    },
  );

  testWidgets('no matches says so in place of the arrows', (tester) async {
    final search = controller()..open();
    addTearDown(search.dispose);
    await tester.pumpWidget(scene(search));
    await type(tester, 'lighthouse tour');

    expect(find.text('No matches found'), findsOneWidget);
    expect(find.byTooltip('Previous match'), findsNothing);
    expect(find.byTooltip('Next match'), findsNothing);
    expect(shown, isEmpty);
  });

  testWidgets('clear empties the field; close ends search', (tester) async {
    final search = controller()..open();
    addTearDown(search.dispose);
    await tester.pumpWidget(scene(search));
    await type(tester, 'dahab');

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('1 of 3'), findsNothing);
    expect(search.hits, isEmpty);

    await tester.tap(find.byTooltip('Close search'));
    await tester.pump();
    expect(search.isOpen, isFalse);
    expect(closed, 1);
  });

  testWidgets('the system back gesture closes search first', (tester) async {
    final search = controller()..open();
    addTearDown(search.dispose);
    await tester.pumpWidget(scene(search));
    await type(tester, 'dahab');

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(search.isOpen, isFalse);
    expect(closed, 1);
  });

  testWidgets('a late answer for an older query is ignored', (tester) async {
    slow['dah'] = Completer<List<String>>();
    final search = controller()..open();
    addTearDown(search.dispose);
    await tester.pumpWidget(scene(search));
    await type(tester, 'dah');
    await type(tester, 'dahab');
    expect(find.text('1 of 3'), findsOneWidget);

    slow['dah']!.complete(['old']);
    await tester.pump();
    expect(find.text('1 of 3'), findsOneWidget);
    expect(search.currentId, 'm3');
  });

  for (final locale in const [Locale('en'), Locale('de'), Locale('ar')]) {
    testWidgets('the bar fits a 360 px phone with no matches '
        '(${locale.languageCode})', (tester) async {
      tester.view.physicalSize = const Size(360, 740) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final search = controller()..open();
      addTearDown(search.dispose);
      await tester.pumpWidget(scene(search, locale: locale));
      await type(tester, 'lighthouse tour');
      expect(search.noMatches, isTrue);
      expect(tester.takeException(), isNull);
      final field = tester.getRect(find.byType(TextField));
      expect(field.width, greaterThan(120), reason: 'room left to type');
    });
  }

  testWidgets('Arabic shows the count in Arabic', (tester) async {
    final search = controller()..open();
    addTearDown(search.dispose);
    await tester.pumpWidget(scene(search, locale: const Locale('ar')));
    expect(find.text('بحث…'), findsOneWidget);
    await type(tester, 'dahab');
    expect(find.text('1 من 3'), findsOneWidget);
  });
}
