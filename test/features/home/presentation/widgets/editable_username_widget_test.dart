import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/widgets/editable_username_widget.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('EditableUsernameWidget', () {
    testWidgets('renders username in display mode', (tester) async {
      await tester.pumpWidget(
        wrap(const EditableUsernameWidget(username: 'alice')),
      );
      expect(find.text('@alice'), findsOneWidget);
    });

    testWidgets('renders "mknoon/" prefix', (tester) async {
      await tester.pumpWidget(
        wrap(const EditableUsernameWidget(username: 'alice')),
      );
      expect(find.text('mknoon/'), findsOneWidget);
    });

    testWidgets('enters edit mode on tap', (tester) async {
      await tester.pumpWidget(
        wrap(const EditableUsernameWidget(username: 'alice')),
      );
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows TextField with maxLength 20 in edit mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const EditableUsernameWidget(username: 'alice')),
      );
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLength, 20);
    });

    testWidgets('edit mode avoids IntrinsicWidth layout', (tester) async {
      await tester.pumpWidget(
        wrap(const EditableUsernameWidget(username: 'alice')),
      );
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();

      expect(find.byType(IntrinsicWidth), findsNothing);
    });

    testWidgets('calls onUsernameChanged when editing completes', (
      tester,
    ) async {
      String? newUsername;
      await tester.pumpWidget(
        wrap(
          EditableUsernameWidget(
            username: 'alice',
            onUsernameChanged: (value) => newUsername = value,
          ),
        ),
      );
      // Enter edit mode
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      // Clear and type new username
      await tester.enterText(find.byType(TextField), 'bob');
      // Submit
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(newUsername, 'bob');
    });
  });
}
