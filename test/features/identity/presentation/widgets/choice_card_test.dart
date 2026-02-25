import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/presentation/widgets/choice_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ChoiceCard', () {
    testWidgets('renders icon, title, and description', (tester) async {
      await tester.pumpWidget(wrap(ChoiceCard(
        icon: Icons.add,
        title: 'Test Title',
        description: 'Test Description',
        onTap: () {},
      )));
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Test Description'), findsOneWidget);
    });

    testWidgets('renders forward arrow icon', (tester) async {
      await tester.pumpWidget(wrap(ChoiceCard(
        icon: Icons.add,
        title: 'Test',
        description: 'Desc',
        onTap: () {},
      )));
      expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(ChoiceCard(
        icon: Icons.add,
        title: 'Test',
        description: 'Desc',
        onTap: () => tapped = true,
      )));
      // Simulate full tap gesture (onTapDown + onTapUp)
      final center = tester.getCenter(find.byType(ChoiceCard));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('renders GlassmorphicContainer with ClipRRect and BackdropFilter',
        (tester) async {
      await tester.pumpWidget(wrap(ChoiceCard(
        icon: Icons.add,
        title: 'Test',
        description: 'Desc',
        onTap: () {},
      )));
      // GlassmorphicContainer uses ClipRRect wrapping a BackdropFilter
      expect(find.byType(ClipRRect), findsWidgets);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });
}
