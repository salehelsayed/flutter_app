import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/replied_indicator.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('RepliedIndicator', () {
    testWidgets('renders "You replied" with relative time', (tester) async {
      final recentTime = DateTime.now().subtract(const Duration(minutes: 5));
      await tester.pumpWidget(wrap(RepliedIndicator(repliedAt: recentTime)));
      expect(find.textContaining('You replied'), findsOneWidget);
      expect(find.textContaining('5m ago'), findsOneWidget);
    });

    testWidgets('renders reply icon', (tester) async {
      await tester.pumpWidget(wrap(RepliedIndicator(repliedAt: DateTime.now())));
      expect(find.byIcon(Icons.reply_rounded), findsOneWidget);
    });

    testWidgets('shows "Active now" for very recent timestamps', (tester) async {
      await tester.pumpWidget(wrap(RepliedIndicator(repliedAt: DateTime.now())));
      expect(find.textContaining('Active now'), findsOneWidget);
    });
  });
}
