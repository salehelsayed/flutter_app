import 'package:flutter/material.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_group_header.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_row.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intros_tab.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now().toUtc().toIso8601String();

  IntroductionModel makeIntro({
    required String id,
    String introducerId = 'peer-A',
    String recipientId = 'peer-B',
    String introducedId = 'peer-C',
    String? introducerUsername = 'Alice',
    String? recipientUsername,
    String? introducedUsername = 'Charlie',
    String? createdAt,
    IntroductionOverallStatus status = IntroductionOverallStatus.pending,
  }) {
    return IntroductionModel(
      id: id,
      introducerId: introducerId,
      recipientId: recipientId,
      introducedId: introducedId,
      introducerUsername: introducerUsername,
      recipientUsername: recipientUsername,
      introducedUsername: introducedUsername,
      createdAt: createdAt ?? now,
      status: status,
    );
  }

  Widget buildWidget({
    required Map<String, List<IntroductionModel>> groupedIntros,
    required Map<String, String> introducerUsernames,
    void Function(String)? onAccept,
    void Function(String)? onPass,
    String ownPeerId = 'peer-B',
    List<FoldedIntroductionReviewItem>? foldedReviewItems,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: IntrosTab(
            groupedIntros: groupedIntros,
            introducerUsernames: introducerUsernames,
            onAccept: onAccept ?? (_) {},
            onPass: onPass ?? (_) {},
            ownPeerId: ownPeerId,
            foldedReviewItems: foldedReviewItems,
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

    testWidgets(
      'renders duplicate aboza introductions as one folded review row',
      (tester) async {
        final older = DateTime.parse(
          now,
        ).subtract(const Duration(minutes: 1)).toUtc().toIso8601String();
        final intro1 = makeIntro(
          id: 'intro-noor',
          introducerId: 'peer-noor',
          recipientId: 'peer-me',
          introducedId: 'peer-aboza',
          introducerUsername: 'Noor',
          recipientUsername: 'Me',
          introducedUsername: 'aboza',
          createdAt: older,
        );
        final intro2 = makeIntro(
          id: 'intro-layla',
          introducerId: 'peer-layla',
          recipientId: 'peer-me',
          introducedId: 'peer-aboza',
          introducerUsername: 'Layla',
          recipientUsername: 'Me',
          introducedUsername: 'aboza',
          createdAt: now,
        );
        final folded = foldIntroductionsForReview(
          introductions: [intro1, intro2],
          ownPeerId: 'peer-me',
        );

        await tester.pumpWidget(
          buildWidget(
            groupedIntros: {
              'peer-noor': [intro1],
              'peer-layla': [intro2],
            },
            introducerUsernames: const {
              'peer-noor': 'Noor',
              'peer-layla': 'Layla',
            },
            ownPeerId: 'peer-me',
            foldedReviewItems: folded,
          ),
        );

        final row = find.byType(IntroRow);
        expect(row, findsOneWidget);
        expect(find.text('aboza'), findsOneWidget);
        expect(find.text('Accept'), findsOneWidget);
        expect(find.text('Pass'), findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.textContaining('Noor')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.textContaining('Layla')),
          findsOneWidget,
        );
        expect(find.byType(IntroGroupHeader), findsNothing);
      },
    );
  });
}
