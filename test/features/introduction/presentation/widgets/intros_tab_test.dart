import 'package:flutter/material.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_group_header.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_row.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intros_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now().toUtc().toIso8601String();

  IntroductionModel makeIntro({
    required String id,
    String introducerId = 'peer-A',
    String recipientId = 'peer-B',
    String introducedId = 'peer-C',
    String? introducerUsername = 'Alice',
    String? introducedUsername = 'Charlie',
    IntroductionOverallStatus status = IntroductionOverallStatus.pending,
  }) {
    return IntroductionModel(
      id: id,
      introducerId: introducerId,
      recipientId: recipientId,
      introducedId: introducedId,
      introducerUsername: introducerUsername,
      introducedUsername: introducedUsername,
      createdAt: now,
      status: status,
    );
  }

  Widget buildWidget({
    required Map<String, List<IntroductionModel>> groupedIntros,
    required Map<String, String> introducerUsernames,
    void Function(String)? onAccept,
    void Function(String)? onPass,
    String ownPeerId = 'peer-B',
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: IntrosTab(
            groupedIntros: groupedIntros,
            introducerUsernames: introducerUsernames,
            onAccept: onAccept ?? (_) {},
            onPass: onPass ?? (_) {},
            ownPeerId: ownPeerId,
          ),
        ),
      ),
    );
  }

  group('IntrosTab', () {
    testWidgets('shows empty state when no introductions', (tester) async {
      await tester.pumpWidget(
        buildWidget(groupedIntros: {}, introducerUsernames: {}),
      );

      expect(find.text('No introductions yet'), findsOneWidget);
    });

    testWidgets('shows pending introductions grouped by sender', (
      tester,
    ) async {
      final intro1 = makeIntro(id: 'i1', introducedUsername: 'Charlie');
      final intro2 = makeIntro(id: 'i2', introducedUsername: 'Dana');

      await tester.pumpWidget(
        buildWidget(
          groupedIntros: {
            'peer-A': [intro1, intro2],
          },
          introducerUsernames: {'peer-A': 'Alice'},
        ),
      );

      final header = find.byType(IntroGroupHeader);
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text('From')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: header, matching: find.text('Alice')),
        findsOneWidget,
      );
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('Dana'), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('group header shows "From [username]"', (tester) async {
      final intro = makeIntro(id: 'i1');

      await tester.pumpWidget(
        buildWidget(
          groupedIntros: {
            'peer-A': [intro],
          },
          introducerUsernames: {'peer-A': 'Alice'},
        ),
      );

      final header = find.byType(IntroGroupHeader);
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text('From')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: header, matching: find.text('Alice')),
        findsOneWidget,
      );
    });

    testWidgets('each intro row shows introduced username', (tester) async {
      final intro = makeIntro(id: 'i1', introducedUsername: 'Charlie');

      await tester.pumpWidget(
        buildWidget(
          groupedIntros: {
            'peer-A': [intro],
          },
          introducerUsernames: {'peer-A': 'Alice'},
        ),
      );

      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('each intro row shows introducer attribution', (tester) async {
      final intro = makeIntro(id: 'i1', introducerUsername: 'Alice');

      await tester.pumpWidget(
        buildWidget(
          groupedIntros: {
            'peer-A': [intro],
          },
          introducerUsernames: {'peer-A': 'Alice'},
        ),
      );

      final row = find.byType(IntroRow);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Introduced by')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Alice')),
        findsOneWidget,
      );
    });

    testWidgets('accept button visible for pending intros', (tester) async {
      final intro = makeIntro(id: 'i1');

      await tester.pumpWidget(
        buildWidget(
          groupedIntros: {
            'peer-A': [intro],
          },
          introducerUsernames: {'peer-A': 'Alice'},
        ),
      );

      expect(find.text('Accept'), findsOneWidget);
    });

    testWidgets('pass button visible for pending intros', (tester) async {
      final intro = makeIntro(id: 'i1');

      await tester.pumpWidget(
        buildWidget(
          groupedIntros: {
            'peer-A': [intro],
          },
          introducerUsernames: {'peer-A': 'Alice'},
        ),
      );

      expect(find.text('Pass'), findsOneWidget);
    });

    testWidgets('accept callback triggered on tap', (tester) async {
      String? acceptedId;
      final intro = makeIntro(id: 'i1');

      await tester.pumpWidget(
        buildWidget(
          groupedIntros: {
            'peer-A': [intro],
          },
          introducerUsernames: {'peer-A': 'Alice'},
          onAccept: (id) => acceptedId = id,
        ),
      );

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(acceptedId, 'i1');
    });

    testWidgets('pass callback triggered on tap', (tester) async {
      String? passedId;
      final intro = makeIntro(id: 'i1');

      await tester.pumpWidget(
        buildWidget(
          groupedIntros: {
            'peer-A': [intro],
          },
          introducerUsernames: {'peer-A': 'Alice'},
          onPass: (id) => passedId = id,
        ),
      );

      await tester.tap(find.text('Pass'));
      await tester.pumpAndSettle();

      expect(passedId, 'i1');
    });

    testWidgets('status label shown for responded intros', (tester) async {
      final connected = makeIntro(
        id: 'i1',
        status: IntroductionOverallStatus.mutualAccepted,
      );
      final passed = makeIntro(
        id: 'i2',
        status: IntroductionOverallStatus.passed,
        introducedUsername: 'Dana',
      );

      await tester.pumpWidget(
        buildWidget(
          groupedIntros: {
            'peer-A': [connected, passed],
          },
          introducerUsernames: {'peer-A': 'Alice'},
        ),
      );

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Passed'), findsOneWidget);
      // No Accept/Pass buttons for responded intros
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Pass'), findsNothing);
    });
  });
}
