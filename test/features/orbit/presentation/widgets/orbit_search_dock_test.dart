import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_dock.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('OrbitSearchDock', () {
    late TextEditingController controller;
    late FocusNode focusNode;

    setUp(() {
      controller = TextEditingController();
      focusNode = FocusNode();
    });

    tearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('renders search icon and TextField', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchDock(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) {},
        onClear: () {},
        onClose: () {},
        query: '',
      )));
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders close button', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchDock(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) {},
        onClear: () {},
        onClose: () {},
        query: '',
      )));
      // The close button has Icons.close icon (at least one in the outer close button)
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('hides clear button when query is empty', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchDock(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) {},
        onClear: () {},
        onClose: () {},
        query: '',
      )));
      // Only one close icon (the outer close button), not the clear button
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('shows clear button when query is not empty', (tester) async {
      await tester.pumpWidget(wrap(OrbitSearchDock(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) {},
        onClear: () {},
        onClose: () {},
        query: 'hello',
      )));
      // Two close icons: one for clear, one for close button
      expect(find.byIcon(Icons.close), findsNWidgets(2));
    });

    testWidgets('calls onClose when close button tapped', (tester) async {
      var closeTapped = false;
      await tester.pumpWidget(wrap(OrbitSearchDock(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) {},
        onClear: () {},
        onClose: () => closeTapped = true,
        query: '',
      )));
      await tester.tap(find.byIcon(Icons.close));
      expect(closeTapped, isTrue);
    });
  });
}
