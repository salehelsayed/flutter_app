import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';

void main() {
  Widget buildTestWidget({
    VoidCallback? onBack,
    VoidCallback? onOverflow,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ConversationHeader(
          contactPeerId: '12D3KooWTestPeerId1234567890',
          contactUsername: 'Alice',
          connectionDate: 'February 9, 2026',
          onBack: onBack ?? () {},
          onOverflow: onOverflow,
        ),
      ),
    );
  }

  group('ConversationHeader', () {
    testWidgets('displays contact username', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('displays connection date', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Connected February 9, 2026'), findsOneWidget);
    });

    testWidgets('shows back chevron icon', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    });

    testWidgets('shows overflow menu icon', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('back button fires onBack callback', (tester) async {
      var backPressed = false;
      await tester.pumpWidget(buildTestWidget(
        onBack: () => backPressed = true,
      ));

      await tester.tap(find.byIcon(Icons.chevron_left));
      expect(backPressed, true);
    });

    testWidgets('overflow button fires onOverflow callback', (tester) async {
      var overflowPressed = false;
      await tester.pumpWidget(buildTestWidget(
        onOverflow: () => overflowPressed = true,
      ));

      await tester.tap(find.byIcon(Icons.more_vert));
      expect(overflowPressed, true);
    });

    testWidgets('renders RingAvatar with 36px size', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // RingAvatar renders a SizedBox with CustomPaint
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      // Find one that is 36x36
      final avatar36 = sizedBoxes.where(
        (sb) => sb.width == 36 && sb.height == 36,
      );
      expect(avatar36, isNotEmpty);
    });
  });
}
