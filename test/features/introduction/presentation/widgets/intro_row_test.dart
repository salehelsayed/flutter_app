import 'package:flutter/material.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now().toUtc().toIso8601String();

  IntroductionModel _makeIntro({
    IntroductionOverallStatus status = IntroductionOverallStatus.pending,
    String introducerUsername = 'Alice',
  }) {
    return IntroductionModel(
      id: 'intro-1',
      introducerId: 'peer-A',
      recipientId: 'peer-B',
      introducedId: 'peer-C',
      introducerUsername: introducerUsername,
      introducedUsername: 'Charlie',
      createdAt: now,
      status: status,
    );
  }

  Widget buildWidget({
    required IntroductionModel introduction,
    required bool showActions,
    VoidCallback? onAccept,
    VoidCallback? onPass,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: IntroRow(
          introduction: introduction,
          displayUsername: introduction.introducedUsername ?? 'Unknown',
          displayPeerId: introduction.introducedId,
          showActions: showActions,
          onAccept: onAccept,
          onPass: onPass,
        ),
      ),
    );
  }

  group('IntroRow', () {
    testWidgets('pending state shows Accept and Pass buttons', (tester) async {
      await tester.pumpWidget(buildWidget(
        introduction: _makeIntro(),
        showActions: true,
        onAccept: () {},
        onPass: () {},
      ));

      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Pass'), findsOneWidget);
    });

    testWidgets('accepted state shows Connected label', (tester) async {
      await tester.pumpWidget(buildWidget(
        introduction: _makeIntro(
          status: IntroductionOverallStatus.mutualAccepted,
        ),
        showActions: false,
      ));

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Pass'), findsNothing);
    });

    testWidgets('passed state shows Passed label', (tester) async {
      await tester.pumpWidget(buildWidget(
        introduction: _makeIntro(
          status: IntroductionOverallStatus.passed,
        ),
        showActions: false,
      ));

      expect(find.text('Passed'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Pass'), findsNothing);
    });

    testWidgets('shows introducer attribution', (tester) async {
      await tester.pumpWidget(buildWidget(
        introduction: _makeIntro(introducerUsername: 'Alice'),
        showActions: true,
        onAccept: () {},
        onPass: () {},
      ));

      expect(find.text('Introduced by Alice'), findsOneWidget);
    });
  });
}
