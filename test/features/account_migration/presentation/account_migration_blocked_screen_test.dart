import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_blocked_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  const unfinishedMoveTitle = 'Account move not finished';
  const unfinishedMoveMessage =
      'This phone imported your account, but the final handoff with the old '
      'phone did not finish. Keep both phones and do not erase either copy.';

  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  testWidgets(
    'shows unfinished-move copy for migrationVerifiedWaitingForCutover',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          const AccountMigrationBlockedScreen(
            record: AccountMigrationAuthorityRecord(
              state: AccountMigrationAuthorityState
                  .migrationVerifiedWaitingForCutover,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('account-migration-blocked-title')),
        findsOneWidget,
      );
      expect(find.text(unfinishedMoveTitle), findsOneWidget);
      expect(find.text(unfinishedMoveMessage), findsOneWidget);
      expect(find.text('Account moved to another phone'), findsNothing);
    },
  );

  testWidgets('new-phone waiting arm hides the erase action', (tester) async {
    var eraseCalls = 0;

    await tester.pumpWidget(
      wrap(
        AccountMigrationBlockedScreen(
          record: const AccountMigrationAuthorityRecord(
            state: AccountMigrationAuthorityState
                .migrationVerifiedWaitingForCutover,
          ),
          onEraseAccount: () async {
            eraseCalls += 1;
          },
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('account-migration-erase-action')),
      findsNothing,
    );
    expect(eraseCalls, 0);
  });

  testWidgets('fail-closed record falls back to default copy', (tester) async {
    await tester.pumpWidget(
      wrap(
        AccountMigrationBlockedScreen(
          record: AccountMigrationAuthorityRecord.failClosed(),
        ),
      ),
    );

    expect(find.text('Account moved to another phone'), findsOneWidget);
    expect(
      find.textContaining('blocked from opening the account'),
      findsOneWidget,
    );
    expect(find.text(unfinishedMoveTitle), findsNothing);
    expect(
      find.byKey(const ValueKey('account-migration-erase-action')),
      findsNothing,
    );
  });

  testWidgets('normal-start authority never exposes account erasure', (
    tester,
  ) async {
    for (final state in [
      AccountMigrationAuthorityState.noAccount,
      AccountMigrationAuthorityState.active,
      AccountMigrationAuthorityState.migrationFailedActiveRestored,
    ]) {
      await tester.pumpWidget(
        wrap(
          AccountMigrationBlockedScreen(
            record: AccountMigrationAuthorityRecord(state: state),
            onEraseAccount: () async {},
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('account-migration-erase-action')),
        findsNothing,
        reason: state.wireName,
      );
    }
  });

  testWidgets(
    'migratedOut blocks normal account UI and requires confirmation to erase',
    (tester) async {
      var eraseCalls = 0;

      await tester.pumpWidget(
        wrap(
          AccountMigrationBlockedScreen(
            record: const AccountMigrationAuthorityRecord(
              state: AccountMigrationAuthorityState.migratedOut,
            ),
            onEraseAccount: () async {
              eraseCalls += 1;
            },
          ),
        ),
      );

      expect(find.text('Account moved to another phone'), findsOneWidget);
      expect(
        find.textContaining('blocked from opening the account'),
        findsOneWidget,
      );
      expect(find.text('Feed'), findsNothing);
      expect(find.text("I'm new here"), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('account-migration-erase-action')),
      );
      await tester.pump();

      expect(eraseCalls, 0);
      expect(find.text('Erase this device?'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('account-migration-erase-confirm')),
      );
      await tester.pump();
      await tester.pump();

      expect(eraseCalls, 1);
      expect(find.text('Local account data erased'), findsOneWidget);
    },
  );

  testWidgets('erase action is disabled when no cleanup callback is supplied', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const AccountMigrationBlockedScreen(
          record: AccountMigrationAuthorityRecord(
            state: AccountMigrationAuthorityState.migratedOut,
          ),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('account-migration-erase-action')),
    );

    expect(button.onPressed, isNull);
  });
}
