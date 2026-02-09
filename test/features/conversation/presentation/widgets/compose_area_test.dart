import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';

void main() {
  Widget buildTestWidget({
    ValueChanged<String>? onSend,
    VoidCallback? onAttach,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Spacer(),
            ComposeArea(
              onSend: onSend ?? (_) {},
              onAttach: onAttach,
            ),
          ],
        ),
      ),
    );
  }

  group('ComposeArea', () {
    testWidgets('shows placeholder text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Write something...'), findsOneWidget);
    });

    testWidgets('shows attachment button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    });

    testWidgets('shows send button with text "Send"', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      // Send button exists in tree but may be invisible
      expect(find.text('Send'), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('send button starts with zero opacity', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // The send button is wrapped in an Opacity widget that starts at 0
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      final zeroOpacity = opacityWidgets.where((o) => o.opacity == 0.0);
      expect(zeroOpacity, isNotEmpty);
    });

    testWidgets('send button becomes visible when text is entered', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();

      // After animation settles, opacity should be 1
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      final fullOpacity = opacityWidgets.where((o) => o.opacity == 1.0);
      expect(fullOpacity, isNotEmpty);
    });

    testWidgets('onSend is called with trimmed text', (tester) async {
      String? sentText;
      await tester.pumpWidget(buildTestWidget(
        onSend: (text) => sentText = text,
      ));

      await tester.enterText(find.byType(TextField), '  Hello!  ');
      await tester.pumpAndSettle();

      // Tap the send button
      await tester.tap(find.text('Send'));
      await tester.pump();

      expect(sentText, 'Hello!');
    });

    testWidgets('text field clears after send', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(find.byType(TextField), 'Hello!');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send'));
      await tester.pump();

      // TextField should be empty
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '');
    });

    testWidgets('attachment button fires onAttach callback', (tester) async {
      var attachPressed = false;
      await tester.pumpWidget(buildTestWidget(
        onAttach: () => attachPressed = true,
      ));

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      expect(attachPressed, true);
    });
  });
}
