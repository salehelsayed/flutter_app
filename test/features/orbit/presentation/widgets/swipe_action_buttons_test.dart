import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/swipe_action_buttons.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('BlockActionButton', () {
    testWidgets('renders block icon and "Block" text', (tester) async {
      await tester.pumpWidget(wrap(BlockActionButton(onTap: () {})));
      expect(find.byIcon(Icons.block), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(BlockActionButton(onTap: () => tapped = true)));
      await tester.tap(find.byType(BlockActionButton));
      expect(tapped, isTrue);
    });
  });

  group('UnblockActionButton', () {
    testWidgets('renders replay icon and "Unblock" text', (tester) async {
      await tester.pumpWidget(wrap(UnblockActionButton(onTap: () {})));
      expect(find.byIcon(Icons.replay), findsOneWidget);
      expect(find.text('Unblock'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(UnblockActionButton(onTap: () => tapped = true)));
      await tester.tap(find.byType(UnblockActionButton));
      expect(tapped, isTrue);
    });
  });

  group('DeleteActionButton', () {
    testWidgets('renders delete icon and "Delete" text', (tester) async {
      await tester.pumpWidget(wrap(DeleteActionButton(onTap: () {})));
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(DeleteActionButton(onTap: () => tapped = true)));
      await tester.tap(find.byType(DeleteActionButton));
      expect(tapped, isTrue);
    });
  });

  group('ArchiveActionButton', () {
    testWidgets('renders archive icon and "Archive" text', (tester) async {
      await tester.pumpWidget(wrap(ArchiveActionButton(onTap: () {})));
      expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(ArchiveActionButton(onTap: () => tapped = true)));
      await tester.tap(find.byType(ArchiveActionButton));
      expect(tapped, isTrue);
    });
  });

  group('UnarchiveActionButton', () {
    testWidgets('renders unarchive icon and "Unarchive" text', (tester) async {
      await tester.pumpWidget(wrap(UnarchiveActionButton(onTap: () {})));
      expect(find.byIcon(Icons.unarchive_outlined), findsOneWidget);
      expect(find.text('Unarchive'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(UnarchiveActionButton(onTap: () => tapped = true)));
      await tester.tap(find.byType(UnarchiveActionButton));
      expect(tapped, isTrue);
    });
  });
}
