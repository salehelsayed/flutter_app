import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';

void main() {
  group('ExpandableFab', () {
    late List<String> tappedItems;

    setUp(() {
      tappedItems = [];
    });

    Widget buildWidget() {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              ExpandableFab(
                items: [
                  ExpandableFabItem(
                    label: 'New Group',
                    icon: Icons.group_outlined,
                    onTap: () => tappedItems.add('group'),
                  ),
                  ExpandableFabItem(
                    label: 'New Announce',
                    icon: Icons.campaign_outlined,
                    onTap: () => tappedItems.add('announce'),
                  ),
                  ExpandableFabItem(
                    label: 'New Q&A',
                    icon: Icons.quiz_outlined,
                    onTap: () => tappedItems.add('qa'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('initially shows + icon (closed state)', (tester) async {
      await tester.pumpWidget(buildWidget());

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('tapping FAB opens menu and shows × icon', (tester) async {
      await tester.pumpWidget(buildWidget());

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('shows all menu item labels when open', (tester) async {
      await tester.pumpWidget(buildWidget());

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('New Group'), findsOneWidget);
      expect(find.text('New Announce'), findsOneWidget);
      expect(find.text('New Q&A'), findsOneWidget);
    });

    testWidgets('hides menu item labels when closed', (tester) async {
      await tester.pumpWidget(buildWidget());

      expect(find.text('New Group'), findsNothing);
      expect(find.text('New Announce'), findsNothing);
      expect(find.text('New Q&A'), findsNothing);
    });

    testWidgets('calls item callback when menu item tapped', (tester) async {
      await tester.pumpWidget(buildWidget());

      // Open
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Tap 'New Announce'
      await tester.tap(find.text('New Announce'));
      await tester.pumpAndSettle();

      expect(tappedItems, ['announce']);
    });

    testWidgets('closes menu after item is tapped', (tester) async {
      await tester.pumpWidget(buildWidget());

      // Open
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('New Group'), findsOneWidget);

      // Tap an item
      await tester.tap(find.text('New Group'));
      await tester.pumpAndSettle();

      // Menu should be closed
      expect(find.text('New Group'), findsNothing);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('tapping × closes the menu', (tester) async {
      await tester.pumpWidget(buildWidget());

      // Open
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('New Group'), findsOneWidget);

      // Close via × icon
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('New Group'), findsNothing);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows scrim overlay when open', (tester) async {
      await tester.pumpWidget(buildWidget());

      // No scrim when closed
      expect(
        find.byKey(const Key('expandable_fab_scrim')),
        findsNothing,
      );

      // Open
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Scrim visible when open
      expect(
        find.byKey(const Key('expandable_fab_scrim')),
        findsOneWidget,
      );
    });
  });
}
