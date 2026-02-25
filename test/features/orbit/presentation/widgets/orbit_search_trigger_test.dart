import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('OrbitSearchTrigger', () {
    testWidgets('renders search icon and "Search friends..." text', (tester) async {
      // The widget's inner Row overflows in the test font (Ahem renders chars
      // at exactly fontSize width). Allow overflow so we can verify behaviour.
      final origHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = origHandler);

      await tester.pumpWidget(wrap(OrbitSearchTrigger(
        onSearchTap: () {},
        onCloseTap: () {},
      )));
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.text('Search friends...'), findsOneWidget);
    });

    testWidgets('renders close icon button', (tester) async {
      final origHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = origHandler);

      await tester.pumpWidget(wrap(OrbitSearchTrigger(
        onSearchTap: () {},
        onCloseTap: () {},
      )));
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('calls onSearchTap when search area tapped', (tester) async {
      final origHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = origHandler);

      var searchTapped = false;
      await tester.pumpWidget(wrap(OrbitSearchTrigger(
        onSearchTap: () => searchTapped = true,
        onCloseTap: () {},
      )));
      await tester.tap(find.text('Search friends...'));
      expect(searchTapped, isTrue);
    });

    testWidgets('calls onCloseTap when close button tapped', (tester) async {
      final origHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = origHandler);

      var closeTapped = false;
      await tester.pumpWidget(wrap(OrbitSearchTrigger(
        onSearchTap: () {},
        onCloseTap: () => closeTapped = true,
      )));
      await tester.tap(find.byIcon(Icons.close));
      expect(closeTapped, isTrue);
    });
  });
}
