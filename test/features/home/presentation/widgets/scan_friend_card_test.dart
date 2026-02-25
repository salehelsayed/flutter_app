import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/widgets/scan_friend_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: child,
          ),
        ),
      );

  group('ScanFriendCard', () {
    testWidgets('renders "Scan a friend\'s code" title text',
        (tester) async {
      await tester.pumpWidget(wrap(ScanFriendCard(onTap: () {})));
      expect(find.text("Scan a friend's code"), findsOneWidget);
    });

    testWidgets('renders subtitle text', (tester) async {
      await tester.pumpWidget(wrap(ScanFriendCard(onTap: () {})));
      expect(find.text('Add someone to your circle'), findsOneWidget);
    });

    testWidgets('renders scan icon (Icons.crop_free)', (tester) async {
      await tester.pumpWidget(wrap(ScanFriendCard(onTap: () {})));
      expect(find.byIcon(Icons.crop_free), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester
          .pumpWidget(wrap(ScanFriendCard(onTap: () => tapped = true)));
      // Use tapDown + tapUp gesture to match GestureDetector.onTapUp
      final center = tester.getCenter(find.byType(ScanFriendCard));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });
}
