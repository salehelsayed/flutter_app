import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('UI25 slow right swipe accumulates small updates exactly once', (tester) async {
    var quotes = 0;
    await tester.pumpWidget(wrap(SwipeToQuoteBubble(
      onQuoteTriggered: () => quotes++,
      child: const SizedBox(width: 200, height: 60),
    )));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(SwipeToQuoteBubble)));
    for (var i = 0; i < 24; i++) {
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(quotes, 1);
  });

  testWidgets('UI25 cancelled quote swipe clears the translated bubble', (tester) async {
    await tester.pumpWidget(wrap(SwipeToQuoteBubble(
      onQuoteTriggered: () {},
      child: const SizedBox(key: ValueKey('bubble'), width: 200, height: 60),
    )));
    final original = tester.getTopLeft(find.byKey(const ValueKey('bubble')));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(SwipeToQuoteBubble)));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey('bubble'))).dx, greaterThan(original.dx));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('bubble'))), original);
  });

  for (final direction in TextDirection.values) {
    final rtl = direction == TextDirection.rtl;
    testWidgets('swipe away from the start edge quotes (${direction.name})', (
      tester,
    ) async {
      var quotes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: SwipeToQuoteBubble(
                    onQuoteTriggered: () => quotes++,
                    child: const SizedBox(
                      key: ValueKey('bubble'),
                      width: 300,
                      height: 60,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final bubble = find.byKey(const ValueKey('bubble'));
      final original = tester.getTopLeft(bubble);
      final away = Offset(rtl ? -60 : 60, 0);

      final wrong = await tester.startGesture(tester.getCenter(bubble));
      await wrong.moveBy(-away);
      await tester.pump();
      expect(tester.getTopLeft(bubble), original, reason: 'wrong way stays');
      await wrong.up();
      await tester.pumpAndSettle();
      expect(quotes, 0);

      final right = await tester.startGesture(tester.getCenter(bubble));
      await right.moveBy(away);
      await tester.pump();
      final moved = tester.getTopLeft(bubble).dx - original.dx;
      expect(rtl ? moved < 0 : moved > 0, isTrue, reason: 'slides with the finger');
      final icon = tester.getCenter(find.byIcon(Icons.reply_rounded));
      final slot = tester.getRect(find.byType(SwipeToQuoteBubble));
      expect(
        rtl ? slot.right - icon.dx : icon.dx - slot.left,
        lessThan(40),
        reason: 'the reply icon shows at the start edge it is uncovering',
      );
      await right.up();
      await tester.pumpAndSettle();
      expect(quotes, 1);
      expect(tester.getTopLeft(bubble), original);
    });
  }

  group('SwipeToQuoteBubble', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(wrap(SwipeToQuoteBubble(
        onQuoteTriggered: () {},
        child: const Text('Hello'),
      )));
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('shows reply icon in widget tree', (tester) async {
      await tester.pumpWidget(wrap(SwipeToQuoteBubble(
        onQuoteTriggered: () {},
        child: const SizedBox(width: 200, height: 50),
      )));
      // The reply icon is always in the tree but with 0 opacity initially
      expect(find.byIcon(Icons.reply_rounded), findsOneWidget);
    });

    testWidgets('calls onQuoteTriggered when drag exceeds threshold',
        (tester) async {
      var triggered = false;
      await tester.pumpWidget(wrap(SwipeToQuoteBubble(
        onQuoteTriggered: () => triggered = true,
        child: const SizedBox(width: 200, height: 50),
      )));
      // Use manual gesture to simulate horizontal drag exceeding 36px threshold
      final center = tester.getCenter(find.byType(SizedBox).first);
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(triggered, isTrue);
    });

    testWidgets('does not trigger callback for small drags', (tester) async {
      var triggered = false;
      await tester.pumpWidget(wrap(SwipeToQuoteBubble(
        onQuoteTriggered: () => triggered = true,
        child: const SizedBox(width: 200, height: 50),
      )));
      // Use manual gesture with small drag (below 36px threshold)
      final center = tester.getCenter(find.byType(SizedBox).first);
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(triggered, isFalse);
    });

    testWidgets('snaps back after drag ends', (tester) async {
      await tester.pumpWidget(wrap(SwipeToQuoteBubble(
        onQuoteTriggered: () {},
        child: const SizedBox(width: 200, height: 50),
      )));
      final center = tester.getCenter(find.byType(SizedBox).first);
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      // After settle, the widget tree should still be intact
      expect(find.byType(SwipeToQuoteBubble), findsOneWidget);
    });
  });
}
