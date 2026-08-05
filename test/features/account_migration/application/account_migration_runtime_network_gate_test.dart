import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';

class _FakeAuthorityRepository implements AccountMigrationAuthorityRepository {
  AccountMigrationAuthorityRecord? record;

  @override
  Future<AccountMigrationAuthorityRecord?> loadAuthority() async => record;

  @override
  Future<void> saveAuthority(AccountMigrationAuthorityRecord record) async {
    this.record = record;
  }

  @override
  Future<void> clearAuthority() async {
    record = null;
  }
}

void main() {
  test(
    'runtime startup steps resume after failure without replaying completed work',
    () async {
      final steps = AccountMigrationRuntimeStartupSteps();
      var stepACalls = 0;
      var stepBAttempts = 0;
      var stepBCompletions = 0;
      var stepCCalls = 0;

      Future<void> start() async {
        await steps.runAsync('step-a', () async {
          stepACalls += 1;
        });
        steps.runSync('step-b', () {
          stepBAttempts += 1;
          if (stepBAttempts == 1) {
            throw StateError('step B failed');
          }
          stepBCompletions += 1;
        });
        await steps.runAsync('step-c', () async {
          stepCCalls += 1;
        });
      }

      await expectLater(start(), throwsA(isA<StateError>()));
      expect(stepACalls, 1);
      expect(stepBAttempts, 1);
      expect(stepBCompletions, 0);
      expect(stepCCalls, 0);

      await start();
      await start();

      expect(stepACalls, 1);
      expect(stepBAttempts, 2);
      expect(stepBCompletions, 1);
      expect(stepCCalls, 1);
    },
  );

  test(
    'runtime startup latch coalesces in flight then retries after a no-start',
    () async {
      final firstOutcome = Completer<bool>();
      var startCalls = 0;
      var syncOnStartedCalls = 0;

      Future<bool> startRuntime() {
        startCalls += 1;
        if (startCalls == 1) {
          return firstOutcome.future;
        }
        return Future<bool>.value(true);
      }

      final latch = AccountMigrationRuntimeStartupLatch(
        startRuntime: startRuntime,
        onStarted: () {
          syncOnStartedCalls += 1;
        },
      );

      final first = latch.ensureStarted();
      final concurrent = latch.ensureStarted();

      expect(
        startCalls,
        1,
        reason: 'the in-flight future must be published synchronously',
      );

      firstOutcome.complete(false);
      await Future.wait<void>([first, concurrent]);

      final retry = latch.ensureStarted();
      expect(
        startCalls,
        2,
        reason: 'a gated no-start must clear the completed latch',
      );
      await retry;

      await latch.ensureStarted();
      expect(
        startCalls,
        2,
        reason: 'a successful start remains latched for later callers',
      );
      expect(
        syncOnStartedCalls,
        1,
        reason: 'existing synchronous startup callbacks remain supported',
      );

      var failingStartCalls = 0;
      final errorLatch = AccountMigrationRuntimeStartupLatch(
        startRuntime: () {
          failingStartCalls += 1;
          if (failingStartCalls == 1) {
            return Future<bool>.error(StateError('runtime start failed'));
          }
          return Future<bool>.value(true);
        },
      );

      await expectLater(errorLatch.ensureStarted(), throwsA(isA<StateError>()));
      await errorLatch.ensureStarted();
      await errorLatch.ensureStarted();
      expect(
        failingStartCalls,
        2,
        reason:
            'an errored start must clear the latch, while its successful '
            'retry remains cached',
      );
    },
  );

  test('runtime startup latch awaits async onStarted completion', () async {
    final onStartedBarrier = Completer<void>();
    var ensureStartedCompleted = false;

    final latch = AccountMigrationRuntimeStartupLatch(
      startRuntime: () async => true,
      onStarted: () => onStartedBarrier.future,
    );

    final startup = latch.ensureStarted()
      ..then((_) {
        ensureStartedCompleted = true;
      });
    await Future<void>.delayed(Duration.zero);

    expect(
      ensureStartedCompleted,
      isFalse,
      reason: 'runtime dependents must wait for post-start recovery work',
    );

    onStartedBarrier.complete();
    await startup;

    expect(ensureStartedCompleted, isTrue);
  });

  group('AccountMigrationRuntimeNetworkGate', () {
    late _FakeAuthorityRepository repository;
    late AccountMigrationRuntimeNetworkGate gate;

    setUp(() {
      repository = _FakeAuthorityRepository();
      gate = AccountMigrationRuntimeNetworkGate(
        authorityRepository: repository,
      );
    });

    test('allows missing legacy authority records', () async {
      expect(
        await gate.allowsAccountNetworkSideEffects(operation: 'test'),
        isTrue,
      );
    });

    test('allows active and restored-active authority', () async {
      for (final state in [
        AccountMigrationAuthorityState.active,
        AccountMigrationAuthorityState.migrationFailedActiveRestored,
      ]) {
        repository.record = AccountMigrationAuthorityRecord(state: state);

        expect(
          await gate.allowsAccountNetworkSideEffects(operation: state.wireName),
          isTrue,
        );
      }
    });

    test('blocks migrated-out and in-progress migration states', () async {
      final blockedStates = AccountMigrationAuthorityState.values.where(
        (state) =>
            state != AccountMigrationAuthorityState.noAccount &&
            state != AccountMigrationAuthorityState.active &&
            state !=
                AccountMigrationAuthorityState.migrationFailedActiveRestored,
      );

      for (final state in blockedStates) {
        repository.record = AccountMigrationAuthorityRecord(state: state);

        expect(
          await gate.allowsAccountNetworkSideEffects(operation: state.wireName),
          isFalse,
          reason: state.wireName,
        );
      }
    });

    test('blocks fail-closed and peer-mismatched records', () async {
      repository.record = AccountMigrationAuthorityRecord.failClosed();
      expect(
        await gate.allowsAccountNetworkSideEffects(operation: 'test'),
        isFalse,
      );

      repository.record = const AccountMigrationAuthorityRecord(
        state: AccountMigrationAuthorityState.active,
        accountPeerId: 'peer-a',
      );
      expect(
        await gate.allowsAccountNetworkSideEffects(
          peerId: 'peer-b',
          operation: 'test',
        ),
        isFalse,
      );
    });

    test('notification display stays allowed during an export pause', () async {
      // Display has no relay side effects; an active Move Account export
      // must not blank incoming notifications on the old phone.
      final displayAllowed = [
        AccountMigrationAuthorityState.noAccount,
        AccountMigrationAuthorityState.active,
        AccountMigrationAuthorityState.migrationFailedActiveRestored,
        AccountMigrationAuthorityState.migrationExportingNetworkPaused,
      ];

      for (final state in AccountMigrationAuthorityState.values) {
        repository.record = AccountMigrationAuthorityRecord(state: state);

        expect(
          await gate.allowsAccountNotificationDisplay(),
          displayAllowed.contains(state),
          reason: state.wireName,
        );
      }

      // But network side effects remain denied while export-paused.
      repository.record = const AccountMigrationAuthorityRecord(
        state: AccountMigrationAuthorityState.migrationExportingNetworkPaused,
      );
      expect(
        await gate.allowsAccountNetworkSideEffects(operation: 'test'),
        isFalse,
      );

      // Fail-closed records never display.
      repository.record = AccountMigrationAuthorityRecord.failClosed();
      expect(await gate.allowsAccountNotificationDisplay(), isFalse);
    });
  });
}
