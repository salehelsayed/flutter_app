import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/swipeable_friend_row.dart';

void main() {
  late ValueNotifier<Key?> openRowNotifier;

  setUp(() {
    openRowNotifier = ValueNotifier(null);
  });

  tearDown(() {
    openRowNotifier.dispose();
  });

  Widget buildSwipeableRow({
    bool isArchived = false,
    bool isBlocked = false,
    VoidCallback? onArchive,
    VoidCallback? onUnarchive,
    VoidCallback? onBlock,
    VoidCallback? onUnblock,
    VoidCallback? onDelete,
  }) {
    return MaterialApp(
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

  group('SwipeableFriendRow', () {
    testWidgets('renders child content at rest', (tester) async {
      await tester.pumpWidget(buildSwipeableRow());
      expect(find.text('Friend Content'), findsOneWidget);
    });

    testWidgets(
      'reveals Block, Delete, Archive on swipe left (active, not blocked)',
      (tester) async {
        bool blockCalled = false;
        bool deleteCalled = false;
        bool archiveCalled = false;

        await tester.pumpWidget(
          buildSwipeableRow(
            onBlock: () => blockCalled = true,
            onDelete: () => deleteCalled = true,
            onArchive: () => archiveCalled = true,
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
