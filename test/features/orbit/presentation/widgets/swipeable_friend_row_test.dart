import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/swipeable_friend_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  late ValueNotifier<Key?> openRowNotifier;

  setUp(() {
    openRowNotifier = ValueNotifier(null);
  });

  tearDown(() {
    openRowNotifier.dispose();
  });

  Widget buildSwipeableRow({
    Locale locale = const Locale('en'),
    bool isArchived = false,
    bool isBlocked = false,
    VoidCallback? onArchive,
    VoidCallback? onUnarchive,
    VoidCallback? onBlock,
    VoidCallback? onUnblock,
    VoidCallback? onDelete,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SwipeableFriendRow(
          key: const ValueKey('test-row'),
          isArchived: isArchived,
          isBlocked: isBlocked,
          openRowNotifier: openRowNotifier,
          onArchive: onArchive,
          onUnarchive: onUnarchive,
          onBlock: onBlock,
          onUnblock: onUnblock,
          onDelete: onDelete,
          child: Container(
            width: double.infinity,
            height: 72,
            color: Colors.blue,
            child: const Text('Friend Content'),
          ),
        ),
      ),
    );
  }

  group('Orbit row actions', () {
    for (final language in ['en', 'de', 'ar']) {
      testWidgets('long press exposes the existing actions in $language', (
        tester,
      ) async {
        final actions = <String>[];
        await tester.pumpWidget(
          buildSwipeableRow(
            locale: Locale(language),
            onBlock: () => actions.add('block'),
            onDelete: () => actions.add('delete'),
            onArchive: () => actions.add('archive'),
          ),
        );
        final row = find.text('Friend Content');
        final l10n = AppLocalizations.of(tester.element(row))!;

        await tester.longPress(row);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 3),
        );

        expect(find.text(l10n.orbit_block_action), findsOneWidget);
        expect(find.text(l10n.orbit_archive_action), findsOneWidget);
        expect(find.text(l10n.orbit_unblock_action), findsNothing);
        final delete = find.text(l10n.orbit_delete_action);
        expect(delete, findsOneWidget);
        expect(actions, isEmpty);

        await tester.tap(delete);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 3),
        );
        expect(actions, ['delete']);
      });
    }

    testWidgets('the blocked row exposes working Arabic custom actions', (
      tester,
    ) async {
      final actions = <String>[];
      await tester.pumpWidget(
        buildSwipeableRow(
          locale: const Locale('ar'),
          isBlocked: true,
          onUnblock: () => actions.add('unblock'),
          onArchive: () => actions.add('archive'),
          onDelete: () => actions.add('delete'),
        ),
      );
      final row = find.byKey(const ValueKey('test-row'));
      final l10n = AppLocalizations.of(tester.element(row))!;
      final node = tester.getSemantics(row);
      int actionId(String label) => CustomSemanticsAction.getIdentifier(
        CustomSemanticsAction(label: label),
      );
      final unblock = actionId(l10n.orbit_unblock_action);
      expect(
        node.getSemanticsData().customSemanticsActionIds,
        unorderedEquals([
          unblock,
          actionId(l10n.orbit_archive_action),
          actionId(l10n.orbit_delete_action),
        ]),
      );

      node.owner!.performAction(node.id, SemanticsAction.customAction, unblock);
      await tester.pump();
      expect(actions, ['unblock']);
    });

    testWidgets('Arabic opens the action at the visual left on a right swipe', (
      tester,
    ) async {
      var archives = 0;
      await tester.pumpWidget(
        buildSwipeableRow(
          locale: const Locale('ar'),
          onArchive: () => archives++,
        ),
      );
      final row = find.text('Friend Content');
      final l10n = AppLocalizations.of(tester.element(row))!;
      final action = find.text(l10n.orbit_archive_action);
      final original = tester.getTopLeft(row).dx;
      Future<void> settle() => tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );

      await tester.dragFrom(tester.getCenter(row), const Offset(-250, 0));
      await settle();
      expect(action, findsNothing);
      await tester.dragFrom(tester.getCenter(row), const Offset(250, 0));
      await settle();
      expect(tester.getTopLeft(row).dx, greaterThan(original));
      expect(action, findsOneWidget);
      expect(tester.getCenter(action).dx, lessThan(tester.getTopLeft(row).dx));
      await tester.tap(action);
      await settle();
      expect(archives, 1);
    });

    testWidgets('swipe labels are at least 13 pt on readable solid fills', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSwipeableRow(onBlock: () {}, onArchive: () {}, onDelete: () {}),
      );
      await tester.drag(find.text('Friend Content'), const Offset(-250, 0));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );
      for (final label in ['Block', 'Archive', 'Delete']) {
        final text = find.text(label);
        final style = tester.widget<Text>(text).style!;
        expect(style.fontSize, greaterThanOrEqualTo(13), reason: label);
        Color? fill;
        tester.element(text).visitAncestorElements((ancestor) {
          if (ancestor.widget case DecoratedBox(
            decoration: BoxDecoration(color: final Color color),
          )) {
            fill = color;
            return false;
          }
          return true;
        });
        expect(fill, isNotNull, reason: label);
        expect(fill!.a, 1, reason: label);
        final contrast =
            (style.color!.computeLuminance() + .05) /
            (fill!.computeLuminance() + .05);
        expect(contrast, greaterThanOrEqualTo(4.5), reason: label);
      }
    });
  });

  testWidgets('UI25 cancelled row swipe settles closed without an action', (tester) async {
    var archives = 0;
    await tester.pumpWidget(buildSwipeableRow(onArchive: () => archives++));
    final original = tester.getTopLeft(find.text('Friend Content'));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Friend Content')));
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Friend Content')).dx, lessThan(original.dx));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Friend Content')), original);
    expect(openRowNotifier.value, isNull);
    expect(archives, 0);
  });

  group('SwipeableFriendRow', () {
    testWidgets('renders child content at rest', (tester) async {
      await tester.pumpWidget(buildSwipeableRow());
      expect(find.text('Friend Content'), findsOneWidget);
    });

    testWidgets(
      'reveals Block, Delete, Archive on swipe left (active, not blocked)',
      (tester) async {
        await tester.pumpWidget(
          buildSwipeableRow(
            onBlock: () {},
            onDelete: () {},
            onArchive: () {},
          ),
        );

        // Perform a left swipe
        final center = tester.getCenter(find.text('Friend Content'));
        await tester.dragFrom(center, const Offset(-250, 0));
        await tester.pumpAndSettle();

        // Action buttons should be revealed
        expect(find.byIcon(Icons.block), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);
        expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
        expect(find.text('Block'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        expect(find.text('Archive'), findsOneWidget);
      },
    );

    testWidgets(
      'reveals Unblock, Delete, Archive on swipe left (active, blocked)',
      (tester) async {
        await tester.pumpWidget(
          buildSwipeableRow(
            isBlocked: true,
            onUnblock: () {},
            onDelete: () {},
            onArchive: () {},
          ),
        );

        // Perform a left swipe
        final center = tester.getCenter(find.text('Friend Content'));
        await tester.dragFrom(center, const Offset(-250, 0));
        await tester.pumpAndSettle();

        // Unblock button (instead of Block)
        expect(find.byIcon(Icons.replay), findsOneWidget);
        expect(find.text('Unblock'), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);
        expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
      },
    );

    testWidgets('reveals only Delete when delete is the only action', (
      tester,
    ) async {
      await tester.pumpWidget(buildSwipeableRow(onDelete: () {}));

      final center = tester.getCenter(find.text('Friend Content'));
      await tester.dragFrom(center, const Offset(-140, 0));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Block'), findsNothing);
      expect(find.text('Unblock'), findsNothing);
    });

    testWidgets('fires onBlock callback', (tester) async {
      bool blockCalled = false;

      await tester.pumpWidget(
        buildSwipeableRow(onBlock: () => blockCalled = true),
      );

      final center = tester.getCenter(find.text('Friend Content'));
      await tester.dragFrom(center, const Offset(-250, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      expect(blockCalled, isTrue);
    });

    testWidgets('fires onDelete callback', (tester) async {
      bool deleteCalled = false;

      await tester.pumpWidget(
        buildSwipeableRow(onDelete: () => deleteCalled = true),
      );

      final center = tester.getCenter(find.text('Friend Content'));
      await tester.dragFrom(center, const Offset(-250, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleteCalled, isTrue);
    });

    testWidgets('reveals Unarchive on swipe left (archived)', (tester) async {
      bool unarchiveCalled = false;

      await tester.pumpWidget(
        buildSwipeableRow(
          isArchived: true,
          onUnarchive: () => unarchiveCalled = true,
        ),
      );

      // Perform a left swipe
      final center = tester.getCenter(find.text('Friend Content'));
      await tester.dragFrom(center, const Offset(-200, 0));
      await tester.pumpAndSettle();

      // Unarchive button should be revealed
      expect(find.text('Unarchive'), findsOneWidget);

      // Tap unarchive
      await tester.tap(find.text('Unarchive'));
      await tester.pumpAndSettle();
      expect(unarchiveCalled, isTrue);
    });

    testWidgets('snaps back on short swipe', (tester) async {
      await tester.pumpWidget(buildSwipeableRow());

      // Perform a very short left swipe (less than threshold)
      final center = tester.getCenter(find.text('Friend Content'));
      await tester.dragFrom(center, const Offset(-30, 0));
      await tester.pumpAndSettle();

      // Action buttons should not be visible
      expect(find.byIcon(Icons.block), findsNothing);
      expect(openRowNotifier.value, isNull);
    });

    testWidgets('right swipe closes an open row and clears the notifier', (
      tester,
    ) async {
      await tester.pumpWidget(buildSwipeableRow(onArchive: () {}));

      final center = tester.getCenter(find.text('Friend Content'));
      await tester.dragFrom(center, const Offset(-250, 0));
      await tester.pumpAndSettle();

      expect(find.text('Archive'), findsOneWidget);
      expect(openRowNotifier.value, const ValueKey('test-row'));

      await tester.dragFrom(center, const Offset(220, 0));
      await tester.pumpAndSettle();

      expect(find.text('Archive'), findsNothing);
      expect(openRowNotifier.value, isNull);
    });
  });
}
