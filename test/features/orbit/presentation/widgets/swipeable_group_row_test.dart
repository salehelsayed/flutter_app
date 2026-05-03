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

  Widget buildGroupSwipeableRow({
    bool isArchived = false,
    VoidCallback? onArchive,
    VoidCallback? onUnarchive,
    VoidCallback? onDelete,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SwipeableFriendRow(
          key: const ValueKey('test-group-row'),
          isArchived: isArchived,
          isBlocked: false,
          openRowNotifier: openRowNotifier,
          onArchive: onArchive,
          onUnarchive: onUnarchive,
          onDelete: onDelete,
          // onBlock/onUnblock intentionally null — groups don't support blocking
          child: Container(
            width: double.infinity,
            height: 72,
            color: Colors.green,
            child: const Text('Group Content'),
          ),
        ),
      ),
    );
  }

  group('Swipeable Group Row', () {
    testWidgets('swiping left reveals only Delete + Archive (no Block)',
        (tester) async {
      await tester.pumpWidget(buildGroupSwipeableRow(
        onArchive: () {},
        onDelete: () {},
      ));

      final center = tester.getCenter(find.text('Group Content'));
      await tester.dragFrom(center, const Offset(-250, 0));
      await tester.pumpAndSettle();

      // Delete and Archive should be visible
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);

      // Block/Unblock should NOT be visible
      expect(find.byIcon(Icons.block), findsNothing);
      expect(find.text('Block'), findsNothing);
      expect(find.byIcon(Icons.replay), findsNothing);
      expect(find.text('Unblock'), findsNothing);
    });

    testWidgets('tapping Archive fires onArchive callback', (tester) async {
      bool archiveCalled = false;

      await tester.pumpWidget(buildGroupSwipeableRow(
        onArchive: () => archiveCalled = true,
        onDelete: () {},
      ));

      final center = tester.getCenter(find.text('Group Content'));
      await tester.dragFrom(center, const Offset(-250, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(archiveCalled, isTrue);
    });

    testWidgets('tapping Delete fires onDelete callback', (tester) async {
      bool deleteCalled = false;

      await tester.pumpWidget(buildGroupSwipeableRow(
        onArchive: () {},
        onDelete: () => deleteCalled = true,
      ));

      final center = tester.getCenter(find.text('Group Content'));
      await tester.dragFrom(center, const Offset(-250, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleteCalled, isTrue);
    });

    testWidgets('group delete does not fire a neighboring friend delete', (
      tester,
    ) async {
      bool friendDeleteCalled = false;
      bool groupDeleteCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SwipeableFriendRow(
                  key: const ValueKey('friend-row'),
                  isArchived: false,
                  openRowNotifier: openRowNotifier,
                  onDelete: () => friendDeleteCalled = true,
                  child: Container(
                    width: double.infinity,
                    height: 72,
                    color: Colors.blue,
                    child: const Text('Friend Content'),
                  ),
                ),
                SwipeableFriendRow(
                  key: const ValueKey('group-row'),
                  isArchived: false,
                  openRowNotifier: openRowNotifier,
                  onArchive: () {},
                  onDelete: () => groupDeleteCalled = true,
                  child: Container(
                    width: double.infinity,
                    height: 72,
                    color: Colors.green,
                    child: const Text('Group Content'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.text('Group Content'));
      await tester.dragFrom(center, const Offset(-250, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(groupDeleteCalled, isTrue);
      expect(friendDeleteCalled, isFalse);
    });

    testWidgets('archived group shows Unarchive on swipe', (tester) async {
      bool unarchiveCalled = false;

      await tester.pumpWidget(buildGroupSwipeableRow(
        isArchived: true,
        onUnarchive: () => unarchiveCalled = true,
      ));

      final center = tester.getCenter(find.text('Group Content'));
      await tester.dragFrom(center, const Offset(-200, 0));
      await tester.pumpAndSettle();

      expect(find.text('Unarchive'), findsOneWidget);

      await tester.tap(find.text('Unarchive'));
      await tester.pumpAndSettle();
      expect(unarchiveCalled, isTrue);
    });
  });
}
