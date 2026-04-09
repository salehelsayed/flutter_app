import 'package:flutter/material.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now().toUtc().toIso8601String();

  Text _textWidget(WidgetTester tester, String text) {
    return tester.widget<Text>(find.text(text));
  }

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
    String? displayUsername,
    VoidCallback? onAccept,
    VoidCallback? onPass,
    VoidCallback? onSendMessage,
    IntroductionStatus? ownPartyStatus,
    String? waitingForUsername,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: IntroRow(
          introduction: introduction,
          displayUsername: displayUsername ??
              introduction.introducedUsername ??
              'Unknown',
          displayPeerId: introduction.introducedId,
          showActions: showActions,
          onAccept: onAccept,
          onPass: onPass,
          onSendMessage: onSendMessage,
          ownPartyStatus: ownPartyStatus,
          waitingForUsername: waitingForUsername,
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

    testWidgets('mutualAccepted state shows Message CTA and invokes callback', (
      tester,
    ) async {
      var tapped = false;

      await tester.pumpWidget(buildWidget(
        introduction: _makeIntro(
          status: IntroductionOverallStatus.mutualAccepted,
        ),
        showActions: false,
        onSendMessage: () => tapped = true,
      ));

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Pass'), findsNothing);

      await tester.tap(find.text('Message'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('accepted own pending intro shows waiting label', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget(
        introduction: _makeIntro(
          status: IntroductionOverallStatus.pending,
        ),
        showActions: false,
        ownPartyStatus: IntroductionStatus.accepted,
        waitingForUsername: 'Charlie',
      ));

      expect(find.text('Waiting for Charlie'), findsOneWidget);
      expect(find.text('Connected'), findsNothing);
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

    testWidgets('alreadyConnected state shows status only and no actions', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget(
        introduction: _makeIntro(
          status: IntroductionOverallStatus.alreadyConnected,
        ),
        showActions: false,
      ));

      expect(find.text('Already connected'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Pass'), findsNothing);
      expect(find.text('Message'), findsNothing);
    });

    testWidgets('shows introducer attribution', (tester) async {
      await tester.pumpWidget(buildWidget(
        introduction: _makeIntro(introducerUsername: 'Alice'),
        showActions: true,
        onAccept: () {},
        onPass: () {},
      ));

      expect(find.text('Introduced by'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('displayUsername uses RTL for Arabic-first mixed text',
        (tester) async {
      const username = 'ليلى Alpha';
      await tester.pumpWidget(buildWidget(
        introduction: _makeIntro(),
        displayUsername: username,
        showActions: true,
        onAccept: () {},
        onPass: () {},
      ));

      expect(_textWidget(tester, username).textDirection, TextDirection.rtl);
    });

    testWidgets('displayUsername uses LTR for English-first mixed text',
        (tester) async {
      const username = 'Alpha ليلى';
      await tester.pumpWidget(buildWidget(
        introduction: _makeIntro(),
        displayUsername: username,
        showActions: true,
        onAccept: () {},
        onPass: () {},
      ));

      expect(_textWidget(tester, username).textDirection, TextDirection.ltr);
    });

    testWidgets('introducer attribution keeps Arabic-first username explicit',
        (tester) async {
      const introducer = 'ليلى Alpha';

      await tester.pumpWidget(buildWidget(
        introduction: _makeIntro(introducerUsername: introducer),
        showActions: true,
        onAccept: () {},
        onPass: () {},
      ));

      expect(_textWidget(tester, introducer).textDirection, TextDirection.rtl);
      expect(
        tester.getTopLeft(find.text('Introduced by')).dx,
        lessThan(tester.getTopLeft(find.text(introducer)).dx),
      );
    });

    testWidgets('introducer attribution keeps English-first username explicit',
        (tester) async {
      const introducer = 'Alpha ليلى';

      await tester.pumpWidget(buildWidget(
        introduction: _makeIntro(introducerUsername: introducer),
        showActions: true,
        onAccept: () {},
        onPass: () {},
      ));

      expect(_textWidget(tester, introducer).textDirection, TextDirection.ltr);
      expect(
        tester.getTopLeft(find.text('Introduced by')).dx,
        lessThan(tester.getTopLeft(find.text(introducer)).dx),
      );
    });
  });
}
