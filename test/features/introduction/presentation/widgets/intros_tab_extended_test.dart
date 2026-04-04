import 'package:flutter/material.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intros_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntrosTab extended', () {
    testWidgets('multiple introducers render multiple group headers', (
      tester,
    ) async {
      final grouped = {
        'peer-A': [
          IntroductionModel(
            id: 'intro-1',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            createdAt: DateTime.now().toUtc().toIso8601String(),
            introducedUsername: 'Sarah',
          ),
        ],
        'peer-D': [
          IntroductionModel(
            id: 'intro-2',
            introducerId: 'peer-D',
            recipientId: 'peer-B',
            introducedId: 'peer-E',
            createdAt: DateTime.now().toUtc().toIso8601String(),
            introducedUsername: 'Dana',
          ),
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntrosTab(
              groupedIntros: grouped,
              introducerUsernames: {'peer-A': 'Noor', 'peer-D': 'Fatima'},
              onAccept: (_) {},
              onPass: (_) {},
              ownPeerId: 'peer-B',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Noor'), findsWidgets);
      expect(find.textContaining('Fatima'), findsWidgets);
    });

    testWidgets('expired status shows non-pending UI', (tester) async {
      final grouped = {
        'peer-A': [
          IntroductionModel(
            id: 'intro-expired',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            status: IntroductionOverallStatus.expired,
            createdAt: DateTime.now()
                .toUtc()
                .subtract(const Duration(days: 31))
                .toIso8601String(),
            introducedUsername: 'Sarah',
          ),
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntrosTab(
              groupedIntros: grouped,
              introducerUsernames: {'peer-A': 'Noor'},
              onAccept: (_) {},
              onPass: (_) {},
              ownPeerId: 'peer-B',
            ),
          ),
        ),
      );
      await tester.pump();

      // Expired intro should not show Accept/Pass buttons
      // (IntroRow only shows actions when isPending == true)
      expect(find.text('Accept'), findsNothing);
    });

    testWidgets('empty state shows placeholder text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntrosTab(
              groupedIntros: const {},
              introducerUsernames: const {},
              onAccept: (_) {},
              onPass: (_) {},
              ownPeerId: 'peer-B',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No introductions yet'), findsOneWidget);
    });

    testWidgets('blank or null usernames fall back to peer ids', (
      tester,
    ) async {
      final grouped = {
        'peer-A': [
          IntroductionModel(
            id: 'intro-fallback',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            introducedUsername: null,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntrosTab(
              groupedIntros: grouped,
              introducerUsernames: const {'peer-A': '   '},
              onAccept: (_) {},
              onPass: (_) {},
              ownPeerId: 'peer-B',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('peer-A'), findsOneWidget);
      expect(find.text('peer-C'), findsOneWidget);
    });

    testWidgets('very long usernames still render with actions intact', (
      tester,
    ) async {
      const longIntroducer =
          'A remarkably long introducer display name that should still render';
      const longIntroduced =
          'An equally long introduced username that should stay visible in the row';

      final grouped = {
        'peer-A': [
          IntroductionModel(
            id: 'intro-long',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            introducedUsername: longIntroduced,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntrosTab(
              groupedIntros: grouped,
              introducerUsernames: const {'peer-A': longIntroducer},
              onAccept: (_) {},
              onPass: (_) {},
              ownPeerId: 'peer-B',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(longIntroducer), findsOneWidget);
      expect(find.text(longIntroduced), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Pass'), findsOneWidget);
    });
  });
}
