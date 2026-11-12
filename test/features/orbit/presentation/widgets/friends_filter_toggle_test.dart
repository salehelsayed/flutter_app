import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_filter_toggle.dart';

void main() {
  Widget buildToggle({
    String activeFilter = 'all',
    int activeCount = 5,
    int archivedCount = 2,
    int introsCount = 0,
    Locale locale = const Locale('en'),
    double textScale = 1,
    EdgeInsets padding = EdgeInsets.zero,
    ValueChanged<String>? onFilterChanged,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: padding,
          child: FriendsFilterToggle(
            activeFilter: activeFilter,
            activeCount: activeCount,
            archivedCount: archivedCount,
            introsCount: introsCount,
            onFilterChanged: onFilterChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  group('FriendsFilterToggle', () {
    testWidgets('renders All and Archived labels', (tester) async {
      await tester.pumpWidget(buildToggle());

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
    });

    testWidgets('shows count badges', (tester) async {
      await tester.pumpWidget(buildToggle(activeCount: 7, archivedCount: 3));

      expect(find.text('7'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('hides archived count badge when count is 0', (tester) async {
      await tester.pumpWidget(buildToggle(archivedCount: 0));

      expect(find.text('5'), findsOneWidget); // active count
      // Archived count should not appear
      expect(find.text('0'), findsNothing);
    });

    testWidgets('fires onFilterChanged when archived tab tapped', (
      tester,
    ) async {
      String? selectedFilter;
      await tester.pumpWidget(
        buildToggle(onFilterChanged: (filter) => selectedFilter = filter),
      );

      await tester.tap(find.text('Archived'));
      expect(selectedFilter, 'archived');
    });

    testWidgets('fires onFilterChanged when all tab tapped', (tester) async {
      String? selectedFilter;
      await tester.pumpWidget(
        buildToggle(
          activeFilter: 'archived',
          onFilterChanged: (filter) => selectedFilter = filter,
        ),
      );

      await tester.tap(find.text('All'));
      expect(selectedFilter, 'all');
    });
  });

  group('German Orbit filter layout', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fits at 360 dp with text scale $scale', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? selected;
        await tester.pumpWidget(
          buildToggle(
            locale: const Locale('de'),
            textScale: scale,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            activeCount: 7,
            introsCount: 3,
            archivedCount: 2,
            onFilterChanged: (filter) => selected = filter,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        const tabs = [
          ('Alle', '7', 'all'),
          ('Vorstellungen', '3', 'intros'),
          ('Archiviert', '2', 'archived'),
        ];
        for (final (label, count, filter) in tabs) {
          final labelFinder = find.text(label);
          final countFinder = find.text(count);
          final tab = find
              .ancestor(of: labelFinder, matching: find.byType(GestureDetector))
              .first;
          final bounds = tester.getRect(tab);
          final labelBounds = tester.getRect(labelFinder);
          final countBounds = tester.getRect(countFinder);
          expect(labelBounds.left, greaterThanOrEqualTo(bounds.left));
          expect(labelBounds.right, lessThanOrEqualTo(countBounds.left));
          expect(countBounds.right, lessThanOrEqualTo(bounds.right));
          final paragraph = tester.renderObject<RenderParagraph>(labelFinder);
          if (paragraph.didExceedMaxLines) {
            expect(paragraph.overflow, TextOverflow.ellipsis);
          }
          await tester.tap(labelFinder);
          expect(selected, filter);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
