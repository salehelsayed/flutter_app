import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_filter_toggle.dart';

void main() {
  Widget buildToggle({
    String activeFilter = 'all',
    int activeCount = 5,
    int archivedCount = 2,
    ValueChanged<String>? onFilterChanged,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: FriendsFilterToggle(
          activeFilter: activeFilter,
          activeCount: activeCount,
          archivedCount: archivedCount,
          onFilterChanged: onFilterChanged ?? (_) {},
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

    testWidgets('fires onFilterChanged when archived tab tapped', (tester) async {
      String? selectedFilter;
      await tester.pumpWidget(buildToggle(
        onFilterChanged: (filter) => selectedFilter = filter,
      ));

      await tester.tap(find.text('Archived'));
      expect(selectedFilter, 'archived');
    });

    testWidgets('fires onFilterChanged when all tab tapped', (tester) async {
      String? selectedFilter;
      await tester.pumpWidget(buildToggle(
        activeFilter: 'archived',
        onFilterChanged: (filter) => selectedFilter = filter,
      ));

      await tester.tap(find.text('All'));
      expect(selectedFilter, 'all');
    });
  });
}
