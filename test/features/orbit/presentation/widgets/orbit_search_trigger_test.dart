import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('OrbitSearchTrigger', () {
    testWidgets('renders a 28px circle container', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchTrigger(
        onSearchTap: () {},
      )));

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.constraints?.maxWidth, 28);
      expect(container.constraints?.maxHeight, 28);
    });

    testWidgets('renders search icon', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchTrigger(
        onSearchTap: () {},
      )));
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('calls onSearchTap when tapped', (tester) async {
      var searchTapped = false;
      await tester.pumpWidget(wrap(OrbitSearchTrigger(
        onSearchTap: () => searchTapped = true,
      )));
      await tester.tap(find.byType(OrbitSearchTrigger));
      expect(searchTapped, isTrue);
    });
  });
}
