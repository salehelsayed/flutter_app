import 'package:flutter/material.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_system_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget(String text) {
    return MaterialApp(
      home: Scaffold(
        body: IntroSystemMessage(text: text),
      ),
    );
  }

  group('IntroSystemMessage', () {
    testWidgets('renders "You introduced N people" text', (tester) async {
      await tester.pumpWidget(buildWidget('You introduced 3 people'));

      expect(find.text('You introduced 3 people'), findsOneWidget);
    });

    testWidgets('renders "[User-A] introduced N people to you"',
        (tester) async {
      await tester.pumpWidget(
          buildWidget('Alice introduced 2 people to you'));

      expect(
          find.text('Alice introduced 2 people to you'), findsOneWidget);
    });

    testWidgets('renders "You and [name] are now connected"', (tester) async {
      await tester.pumpWidget(
        buildWidget(
            'You and Charlie are now connected — introduced by Alice'),
      );

      expect(
        find.text(
            'You and Charlie are now connected — introduced by Alice'),
        findsOneWidget,
      );
    });

    testWidgets('renders with correct count', (tester) async {
      await tester.pumpWidget(buildWidget('You introduced 5 people'));

      expect(find.text('You introduced 5 people'), findsOneWidget);
    });

    testWidgets('renders with correct names', (tester) async {
      await tester.pumpWidget(
          buildWidget('Alice introduced Charlie, Dana to you'));

      expect(
          find.text('Alice introduced Charlie, Dana to you'), findsOneWidget);
    });

    testWidgets('renders centered', (tester) async {
      await tester.pumpWidget(buildWidget('Test message'));

      final center = find.byType(Center);
      expect(center, findsOneWidget);
    });

    testWidgets('renders with muted style', (tester) async {
      await tester.pumpWidget(buildWidget('Test message'));

      final textWidget =
          tester.widget<Text>(find.text('Test message'));
      expect(textWidget.style?.color, const Color(0x80FFFFFF));
      expect(textWidget.style?.fontSize, 12);
    });

    testWidgets('text is centered alignment', (tester) async {
      await tester.pumpWidget(buildWidget('Test message'));

      final textWidget =
          tester.widget<Text>(find.text('Test message'));
      expect(textWidget.textAlign, TextAlign.center);
    });

    testWidgets('does not have interactive actions', (tester) async {
      await tester.pumpWidget(buildWidget('Test message'));

      // No GestureDetector or InkWell wrapping the system message
      expect(find.byType(GestureDetector), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('multiple system messages render in sequence', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const IntroSystemMessage(text: 'Message 1'),
                const IntroSystemMessage(text: 'Message 2'),
                const IntroSystemMessage(text: 'Message 3'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Message 1'), findsOneWidget);
      expect(find.text('Message 2'), findsOneWidget);
      expect(find.text('Message 3'), findsOneWidget);
      expect(find.byType(IntroSystemMessage), findsNWidgets(3));
    });

    testWidgets('Arabic system text drives RTL direction', (tester) async {
      const message = 'تم تقديمك إلى خالد بواسطة ليلى';
      await tester.pumpWidget(buildWidget(message));

      final textWidget = tester.widget<Text>(find.text(message));
      expect(textWidget.textDirection, TextDirection.rtl);
    });

    testWidgets('Arabic-first mixed system text drives RTL direction',
        (tester) async {
      const message = 'ليلى introduced 2 people to you';
      await tester.pumpWidget(buildWidget(message));

      final textWidget = tester.widget<Text>(find.text(message));
      expect(textWidget.textDirection, TextDirection.rtl);
    });

    testWidgets('English-first mixed system text stays LTR direction',
        (tester) async {
      const message = 'Alice قدمت 2 people to you';
      await tester.pumpWidget(buildWidget(message));

      final textWidget = tester.widget<Text>(find.text(message));
      expect(textWidget.textDirection, TextDirection.ltr);
    });
  });
}
