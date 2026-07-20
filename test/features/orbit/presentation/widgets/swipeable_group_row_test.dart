import 'package:flutter/material.dart';
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

  Widget buildGroupSwipeableRow({
    bool isArchived = false,
    VoidCallback? onArchive,
    VoidCallback? onUnarchive,
    VoidCallback? onLeave,
    VoidCallback? onDelete,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SwipeableFriendRow(
          key: const ValueKey('test-group-row'),
          isArchived: isArchived,
          isBlocked: false,
          openRowNotifier: openRowNotifier,
          onArchive: onArchive,
          onUnarchive: onUnarchive,
          onLeave: onLeave,
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
    testWidgets('Leave and Delete expose distinct button semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var leaveCalls = 0;
      var deleteCalls = 0;
      await tester.pumpWidget(
        buildGroupSwipeableRow(onArchive: () {}, onLeave: () => leaveCalls++),
      );

      final center = tester.getCenter(find.text('Group Content'));
      await tester.dragFrom(center, const Offset(-250, 0));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.logout), findsOneWidget);
      expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(find.byIcon(Icons.block), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Leave')),
        matchesSemantics(label: 'Leave', isButton: true, hasTapAction: true),
      );
      await tester.tap(find.text('Leave'));
      expect(leaveCalls, 1);
      expect(deleteCalls, 0);

      await tester.pumpWidget(
        buildGroupSwipeableRow(onArchive: () {}, onDelete: () => deleteCalls++),
      );
      await tester.dragFrom(
        tester.getCenter(find.text('Group Content')),
        const Offset(-250, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Leave'), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Delete')),
        matchesSemantics(label: 'Delete', isButton: true, hasTapAction: true),
      );
      await tester.tap(find.text('Delete'));
      expect(deleteCalls, 1);
      expect(leaveCalls, 1);
      semantics.dispose();
    });

    testWidgets('tapping Archive fires onArchive callback', (tester) async {
      bool archiveCalled = false;

      await tester.pumpWidget(
        buildGroupSwipeableRow(
          onArchive: () => archiveCalled = true,
          onDelete: () {},
        ),
      );

      final center = tester.getCenter(find.text('Group Content'));
      await tester.dragFrom(center, const Offset(-250, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(archiveCalled, isTrue);
    });

    testWidgets('tapping Leave fires onLeave callback', (tester) async {
      bool leaveCalled = false;

      await tester.pumpWidget(
        buildGroupSwipeableRow(
          onArchive: () {},
          onLeave: () => leaveCalled = true,
        ),
      );

      final center = tester.getCenter(find.text('Group Content'));
      await tester.dragFrom(center, const Offset(-250, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(leaveCalled, isTrue);
    });

    testWidgets('group delete does not fire a neighboring friend delete', (
      tester,
    ) async {
      bool friendDeleteCalled = false;
      bool groupDeleteCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

      await tester.pumpWidget(
        buildGroupSwipeableRow(
          isArchived: true,
          onArchive: () {},
          onUnarchive: () => unarchiveCalled = true,
          onLeave: () => fail('archived row must not leave'),
          onDelete: () => fail('archived row must not delete'),
        ),
      );

      final center = tester.getCenter(find.text('Group Content'));
      await tester.dragFrom(center, const Offset(-200, 0));
      await tester.pumpAndSettle();

      expect(find.text('Unarchive'), findsOneWidget);
      expect(find.text('Leave'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Archive'), findsNothing);

      await tester.tap(find.text('Unarchive'));
      await tester.pumpAndSettle();
      expect(unarchiveCalled, isTrue);
    });
  });
}
