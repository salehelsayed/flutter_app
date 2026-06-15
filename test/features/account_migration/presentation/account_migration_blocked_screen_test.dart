import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_blocked_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('blocks normal account UI and requires confirmation to erase', (
    tester,
  ) async {
    var eraseCalls = 0;

    await tester.pumpWidget(
      wrap(
        AccountMigrationBlockedScreen(
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

    await tester.tap(find.text('Erase local data'));
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
  });

  testWidgets('erase action is disabled when no cleanup callback is supplied', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const AccountMigrationBlockedScreen()));

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('account-migration-erase-action')),
    );

    expect(button.onPressed, isNull);
  });
}
