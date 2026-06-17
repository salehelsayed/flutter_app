import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/group_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// G2: the orbit GroupRow's stuck-rejoin "Retry now" / "Leave" affordances.
OrbitGroup _group({int? rejoinAttemptCount}) {
  return OrbitGroup(
    group: GroupModel(
      id: 'group-1',
      name: 'Stuck Group',
      type: GroupType.chat,
      topicName: 'topic-1',
      createdAt: DateTime(2026, 3, 9).toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.admin,
    ),
    unreadCount: 0,
    lastActivityTimestamp: DateTime(2026, 3, 9, 9, 30),
    rejoinAttemptCount: rejoinAttemptCount,
  );
}

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  group('GroupRow G2 stuck-rejoin actions', () {
    testWidgets(
      'a stuck group (attempt >= 10) shows the give-up badge with Retry + Leave',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            GroupRow(
              group: _group(rejoinAttemptCount: 11),
              onTap: () {},
              onRetryStuckRejoin: () {},
              onLeaveStuckGroup: () {},
            ),
          ),
        );

        expect(find.text("Couldn't join — retry"), findsOneWidget);
        expect(
          find.byKey(const ValueKey('orbit-group-stuck-retry-group-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('orbit-group-stuck-leave-group-1')),
          findsOneWidget,
        );
      },
    );

    testWidgets('tapping "Retry now" invokes onRetryStuckRejoin', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        wrap(
          GroupRow(
            group: _group(rejoinAttemptCount: 10),
            onTap: () {},
            onRetryStuckRejoin: () => retried = true,
            onLeaveStuckGroup: () {},
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('orbit-group-stuck-retry-group-1')),
      );
      await tester.pump();

      expect(retried, isTrue);
    });

    testWidgets('tapping "Leave" invokes onLeaveStuckGroup', (tester) async {
      var left = false;
      await tester.pumpWidget(
        wrap(
          GroupRow(
            group: _group(rejoinAttemptCount: 10),
            onTap: () {},
            onRetryStuckRejoin: () {},
            onLeaveStuckGroup: () => left = true,
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('orbit-group-stuck-leave-group-1')),
      );
      await tester.pump();

      expect(left, isTrue);
    });

    testWidgets(
      'a non-stuck group (attempt < 10) shows the passive Joining… badge with '
      'no actions',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            GroupRow(
              group: _group(rejoinAttemptCount: 4),
              onTap: () {},
              onRetryStuckRejoin: () {},
              onLeaveStuckGroup: () {},
            ),
          ),
        );

        expect(find.text('Joining…'), findsOneWidget);
        expect(find.text("Couldn't join — retry"), findsNothing);
        expect(
          find.byKey(const ValueKey('orbit-group-stuck-retry-group-1')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('orbit-group-stuck-leave-group-1')),
          findsNothing,
        );
      },
    );
  });
}
