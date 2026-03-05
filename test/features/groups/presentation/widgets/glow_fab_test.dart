import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/presentation/widgets/glow_fab.dart';

void main() {
  group('GlowFab', () {
    testWidgets('renders + icon by default', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: GlowFab(onPressed: () {}))),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('renders custom icon when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlowFab(
              onPressed: () {},
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('calls onPressed when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GlowFab(onPressed: () => tapped = true)),
        ),
      );

      await tester.tap(find.byType(GlowFab));
      expect(tapped, isTrue);
    });

    testWidgets('defaults to 56 when no size given', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: GlowFab(onPressed: () {}))),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(GlowFab),
          matching: find.byType(Container),
        ),
      );

      expect(container.constraints?.maxWidth, 56);
      expect(container.constraints?.maxHeight, 56);
    });

    testWidgets('uses custom size when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GlowFab(onPressed: () {}, size: 40)),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(GlowFab),
          matching: find.byType(Container),
        ),
      );

      expect(container.constraints?.maxWidth, 40);
      expect(container.constraints?.maxHeight, 40);
    });

    testWidgets('has circular shape with blue border', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: GlowFab(onPressed: () {}))),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(GlowFab),
          matching: find.byType(Container),
        ),
      );

      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.border, isNotNull);
    });
  });
}
