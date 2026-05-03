import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';

void main() {
  Widget wrap(Widget child, {BackgroundReadableColors? readableColors}) =>
      MaterialApp(
        theme: ThemeData(
          extensions: [readableColors ?? BackgroundReadableColors.dark],
        ),
        home: Scaffold(body: child),
      );

  group('OrbitSearchTrigger', () {
    testWidgets('renders a 44px circle container', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchTrigger(onSearchTap: () {})));

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.constraints?.maxWidth, 44);
      expect(container.constraints?.maxHeight, 44);
    });

    testWidgets('renders search icon', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchTrigger(onSearchTap: () {})));
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('calls onSearchTap when tapped', (tester) async {
      var searchTapped = false;
      await tester.pumpWidget(
        wrap(OrbitSearchTrigger(onSearchTap: () => searchTapped = true)),
      );
      await tester.tap(find.byType(OrbitSearchTrigger));
      expect(searchTapped, isTrue);
    });

    testWidgets('uses readable glass and icon color on daylight', (
      tester,
    ) async {
      const colors = BackgroundReadableColors.representativeLight;

      await tester.pumpWidget(
        wrap(OrbitSearchTrigger(onSearchTap: () {}), readableColors: colors),
      );

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      final icon = tester.widget<Icon>(find.byIcon(Icons.search));

      expect(decoration.color, colors.glassSurface);
      expect((decoration.border as Border).top.color, colors.glassBorder);
      expect(icon.color, colors.iconPrimary);
    });
  });
}
