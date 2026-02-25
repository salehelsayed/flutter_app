import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/presentation/widgets/brand_header.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('BrandHeader', () {
    testWidgets('renders fingerprint icon', (tester) async {
      await tester.pumpWidget(wrap(const BrandHeader()));
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    });

    testWidgets('renders "mknoon" text', (tester) async {
      await tester.pumpWidget(wrap(const BrandHeader()));
      expect(find.text('mknoon'), findsOneWidget);
    });

    testWidgets('renders tagline "Your identity, your control"', (tester) async {
      await tester.pumpWidget(wrap(const BrandHeader()));
      expect(find.text('Your identity, your control'), findsOneWidget);
    });

    testWidgets('fingerprint icon has AppColors.primaryAccent color', (tester) async {
      await tester.pumpWidget(wrap(const BrandHeader()));
      final icon = tester.widget<Icon>(find.byIcon(Icons.fingerprint));
      expect(icon.color, AppColors.primaryAccent);
    });

    testWidgets('"mknoon" text has letterSpacing 1.5', (tester) async {
      await tester.pumpWidget(wrap(const BrandHeader()));
      final text = tester.widget<Text>(find.text('mknoon'));
      expect(text.style?.letterSpacing, 1.5);
    });

    testWidgets('renders 80px circle container', (tester) async {
      await tester.pumpWidget(wrap(const BrandHeader()));
      final containers = tester.widgetList<Container>(find.byType(Container));
      final circleContainer = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
          return c.constraints?.maxWidth == 80;
        }
        return false;
      });
      expect(circleContainer, isNotEmpty);
    });

    testWidgets('renders icon inside glow container', (tester) async {
      await tester.pumpWidget(wrap(const BrandHeader()));
      // Verify the fingerprint icon exists inside the widget tree
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
      // And verify there are BoxShadow containers (glow effect)
      final containers = tester.widgetList<Container>(find.byType(Container));
      final glowContainer = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.boxShadow != null && decoration.boxShadow!.isNotEmpty;
        }
        return false;
      });
      expect(glowContainer, isNotEmpty);
    });
  });
}
