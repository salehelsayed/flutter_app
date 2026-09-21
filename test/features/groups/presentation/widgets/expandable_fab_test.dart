import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/groups/presentation/widgets/glow_fab.dart';

void main() {
  group('ExpandableFab', () {
    late List<String> tappedItems;

    setUp(() {
      tappedItems = [];
    });

    List<ExpandableFabItem> items() => [
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
    ];

    Widget buildWidget({
      ExpandableFabAnchor anchor = ExpandableFabAnchor.bottomRight,
      double fabSize = 56,
      EdgeInsets? safeAreaPadding,
      bool named = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              ExpandableFab(
                items: items(),
                fabSemanticLabel: named ? 'Create group' : null,
                openFabSemanticLabel: named ? 'Close create menu' : null,
                fabSemanticIdentifier: named ? 'fixture-fab' : null,
                anchor: anchor,
                fabSize: fabSize,
                safeAreaPadding: safeAreaPadding,
              ),
            ],
          ),
        ),
      );
    }

    for (final anchor in ExpandableFabAnchor.values) {
      testWidgets(
        'A02 named FAB retains identity through selection and dismissal $anchor',
        (tester) async {
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(buildWidget(anchor: anchor, named: true));
          final finder = find.bySemanticsIdentifier('fixture-fab');
          final id = tester.getSemantics(finder).id;
          void activate() => tester
              .binding
              .renderViews
              .single
              .owner!
              .semanticsOwner!
              .performAction(
                tester.getSemantics(finder).id,
                ui.SemanticsAction.tap,
              );
          activate();
          await tester.pumpAndSettle();
          expect(tester.getSemantics(finder).label, 'Close create menu');
          expect(tester.getSemantics(finder).id, id);
          await tester.tap(find.text('New Announce'));
          await tester.pumpAndSettle();
          expect(tappedItems, ['announce']);
          expect(tester.getSemantics(finder).label, 'Create group');
          expect(tester.getSemantics(finder).id, id);
          activate();
          await tester.pumpAndSettle();
          await tester.tapAt(const Offset(10, 300));
          await tester.pumpAndSettle();
          expect(tappedItems, ['announce']);
          expect(tester.getSemantics(finder).label, 'Create group');
          expect(tester.getSemantics(finder).id, id);
          handle.dispose();
        },
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
    });

    testWidgets('hides menu item labels when closed', (tester) async {
      await tester.pumpWidget(buildWidget());

      expect(find.text('New Group'), findsNothing);
      expect(find.text('New Announce'), findsNothing);
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
      expect(find.byKey(const Key('expandable_fab_scrim')), findsNothing);

      // Open
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Scrim visible when open
      expect(find.byKey(const Key('expandable_fab_scrim')), findsOneWidget);
    });

    testWidgets('defaults to bottom-right positioning', (tester) async {
      await tester.pumpWidget(buildWidget());

      final positioned = tester.widget<Positioned>(
        find
            .ancestor(
              of: find.byType(GlowFab),
              matching: find.byType(Positioned),
            )
            .last,
      );

      expect(positioned.bottom, 16);
      expect(positioned.right, 16);
      expect(positioned.top, isNull);
    });

    testWidgets('positions at top-right when anchor is topRight', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildWidget(anchor: ExpandableFabAnchor.topRight),
      );

      final positioned = tester.widget<Positioned>(
        find
            .ancestor(
              of: find.byType(GlowFab),
              matching: find.byType(Positioned),
            )
            .last,
      );

      expect(positioned.top, isNotNull);
      expect(positioned.right, 16);
      expect(positioned.bottom, isNull);
    });

    testWidgets('menu items appear below FAB when anchor is topRight', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildWidget(anchor: ExpandableFabAnchor.topRight),
      );

      // Open
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // FAB should be above the first menu item
      final fabCenter = tester.getCenter(find.byType(GlowFab));
      final menuItemCenter = tester.getCenter(find.text('New Group'));
      expect(fabCenter.dy, lessThan(menuItemCenter.dy));
    });

    testWidgets('passes fabSize to GlowFab', (tester) async {
      await tester.pumpWidget(buildWidget(fabSize: 40));

      final glowFab = tester.widget<GlowFab>(find.byType(GlowFab));
      expect(glowFab.size, 40);
    });
  });
}
