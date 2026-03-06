import 'package:flutter/material.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_banner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntroBanner', () {
    testWidgets('renders banner with contact username', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntroBanner(
              contactUsername: 'Alice',
              onMakeIntroductions: () {},
              onMaybeLater: () {},
            ),
          ),
        ),
      );

      expect(find.text('Help Alice meet your circle'), findsOneWidget);
      expect(
        find.text('Introduce them to friends who might click'),
        findsOneWidget,
      );
      expect(find.text('Make introductions'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);
    });

    testWidgets('"Make introductions" button triggers callback',
        (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntroBanner(
              contactUsername: 'Bob',
              onMakeIntroductions: () => tapped = true,
              onMaybeLater: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Make introductions'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('"Maybe later" triggers callback', (tester) async {
      var dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntroBanner(
              contactUsername: 'Charlie',
              onMakeIntroductions: () {},
              onMaybeLater: () => dismissed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Maybe later'));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });
  });
}
