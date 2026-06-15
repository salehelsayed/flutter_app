import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_bridge_cleanup.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_coordinator.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_cutover_record.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_cutover_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MigrationCutoverCoordinator', () {
    late _FakeAuthorityRepository authority;
    late _FakeCutoverRepository cutover;
    late _Clock clock;
    late MigrationCutoverCoordinator coordinator;

    setUp(() {
      authority = _FakeAuthorityRepository();
      cutover = _FakeCutoverRepository();
      clock = _Clock(DateTime.utc(2026, 6, 7, 16));
      coordinator = MigrationCutoverCoordinator(
        authorityRepository: authority,
        cutoverRepository: cutover,
        now: clock.now,
      );
    });

    test(
      'missing old block proof cannot promote the new phone active',
      () async {
        final unprovedOldRecord = MigrationCutoverRecord.initial(
          sessionId: 'session-1',
          accountPeerId: 'account-peer',
          devicePeerId: 'old-device',
          deviceRole: MigrationCutoverDeviceRole.oldPhone,
          now: clock.now(),
        );

        final result = await coordinator.commitNewActive(
          sessionId: 'session-1',
          accountPeerId: 'account-peer',
          devicePeerId: 'new-device',
          importVerified: true,
          oldBlockProof: unprovedOldRecord,
        );

        expect(result.newActiveCommitted, isFalse);
        expect(
          authority.record?.state,
          AccountMigrationAuthorityState.migrationVerifiedWaitingForCutover,
        );
        expect(
          authority.history,
          isNot(
            contains(
              isA<AccountMigrationAuthorityRecord>().having(
                (record) => record.state,
                'state',
                AccountMigrationAuthorityState.active,
              ),
            ),
          ),
        );
      },
    );

    test(
      'mismatched old block proof cannot promote the new phone active',
      () async {
        final validOldProof =
            MigrationCutoverRecord.initial(
              sessionId: 'session-identity',
              accountPeerId: 'account-peer',
              devicePeerId: 'old-device',
              deviceRole: MigrationCutoverDeviceRole.oldPhone,
              now: clock.now(),
            ).copyWith(
              phase: MigrationCutoverPhase.oldNetworkBlocked,
              oldNetworkBlocked: true,
              oldNetworkBlockedAt: clock.now(),
            );
        final invalidProofs = <String, MigrationCutoverRecord>{
          'session mismatch': validOldProof.copyWith(
            sessionId: 'stale-session',
          ),
          'account mismatch': validOldProof.copyWith(
            accountPeerId: 'other-account-peer',
          ),
          'role mismatch': validOldProof.copyWith(
            deviceRole: MigrationCutoverDeviceRole.newPhone,
          ),
        };

        for (final entry in invalidProofs.entries) {
          final localAuthority = _FakeAuthorityRepository();
          final localCutover = _FakeCutoverRepository();
          final localCoordinator = MigrationCutoverCoordinator(
            authorityRepository: localAuthority,
            cutoverRepository: localCutover,
            now: clock.now,
          );

          final result = await localCoordinator.commitNewActive(
            sessionId: 'session-identity',
            accountPeerId: 'account-peer',
            devicePeerId: 'new-device',
            importVerified: true,
            oldBlockProof: entry.value,
          );

          expect(result.newActiveCommitted, isFalse, reason: entry.key);
          expect(
            localAuthority.history.last.state,
            AccountMigrationAuthorityState.migrationVerifiedWaitingForCutover,
            reason: entry.key,
          );
          expect(
            localAuthority.history,
            isNot(
              contains(_authorityState(AccountMigrationAuthorityState.active)),
            ),
            reason: entry.key,
          );
        }
      },
    );

    test('old network block is durable before new active commit', () async {
      final oldProof = await coordinator.markOldNetworkBlocked(
        sessionId: 'session-1',
        accountPeerId: 'account-peer',
        devicePeerId: 'old-device',
      );

      expect(oldProof.provesOldNetworkBlocked, isTrue);
      expect(
        authority.history.first.state,
        AccountMigrationAuthorityState.migrationCutoverPendingBlocked,
      );

      final newAuthority = _FakeAuthorityRepository();
      final newCutover = _FakeCutoverRepository();
      final newCoordinator = MigrationCutoverCoordinator(
        authorityRepository: newAuthority,
        cutoverRepository: newCutover,
        now: clock.now,
      );

      final committed = await newCoordinator.commitNewActive(
        sessionId: 'session-1',
        accountPeerId: 'account-peer',
        devicePeerId: 'new-device',
        importVerified: true,
        oldBlockProof: oldProof,
      );

      expect(committed.provesNewActiveCommitted, isTrue);
      expect(newCutover.history.first.newActiveCommitted, isTrue);
      expect(
        newAuthority.history.last.state,
        AccountMigrationAuthorityState.active,
      );
    });

    test(
      'recovers interrupted cutover branches without two active devices',
      () async {
        await authority.saveAuthority(
          const AccountMigrationAuthorityRecord(
            state: AccountMigrationAuthorityState.active,
            accountPeerId: 'account-peer',
          ),
        );
        expect(
          await coordinator.recover(),
          MigrationCutoverRecoveryDecision.oldDeviceActive,
        );

        final oldProof = await coordinator.markOldNetworkBlocked(
          sessionId: 'session-2',
          accountPeerId: 'account-peer',
          devicePeerId: 'old-device',
        );
        expect(
          await coordinator.recover(),
          MigrationCutoverRecoveryDecision.waitForOldBlockProof,
        );
        expect(authority.record?.state.blocksNormalStartup, isTrue);

        await coordinator.recordOldBlockProofReceived(
          sessionId: 'session-2',
          accountPeerId: 'account-peer',
          devicePeerId: 'new-device',
          oldBlockProof: oldProof,
        );
        expect(
          await coordinator.recover(),
          MigrationCutoverRecoveryDecision.retryNewActiveCommit,
        );

        await coordinator.commitNewActive(
          sessionId: 'session-2',
          accountPeerId: 'account-peer',
          devicePeerId: 'new-device',
          importVerified: true,
          oldBlockProof: oldProof,
        );
        expect(
          await coordinator.recover(),
          MigrationCutoverRecoveryDecision.newDeviceActive,
        );
      },
    );

    test(
      'lease cleanup clears stale push token and retries failed command',
      () async {
        final oldProof = await coordinator.markOldNetworkBlocked(
          sessionId: 'session-3',
          accountPeerId: 'account-peer',
          devicePeerId: 'old-device',
        );
        final newActiveProof = oldProof.copyWith(
          devicePeerId: 'new-device',
          deviceRole: MigrationCutoverDeviceRole.newPhone,
          oldBlockProofReceived: true,
          oldBlockProofReceivedAt: clock.now(),
          newActiveCommitted: true,
          newActiveCommittedAt: clock.now(),
        );
        final cleanup = _FakeLeaseCleanup(failInboxUnregister: true);

        final pending = await coordinator.markOldMigratedOutAfterNewActive(
          sessionId: 'session-3',
          accountPeerId: 'account-peer',
          devicePeerId: 'old-device',
          newActiveProof: newActiveProof,
          leaseCleanup: cleanup.client,
        );

        expect(
          authority.record?.state,
          AccountMigrationAuthorityState.migratedOut,
        );
        expect(pending.phase, MigrationCutoverPhase.leaseCleanupPending);
        expect(pending.stalePushTokenCleared, isTrue);
        expect(pending.rendezvousUnregisterIssued, isTrue);
        expect(pending.inboxPushTokenUnregisterIssued, isFalse);
        expect(cleanup.clearLocalPushTokenCalls, 1);
        expect(cleanup.rendezvousCalls, 1);
        expect(cleanup.inboxCalls, 1);

        cleanup.failInboxUnregister = false;
        final completed = await coordinator.retryLeaseCleanup(
          leaseCleanup: cleanup.client,
        );

        expect(completed.phase, MigrationCutoverPhase.complete);
        expect(completed.stalePushTokenCleared, isTrue);
        expect(completed.rendezvousUnregisterIssued, isTrue);
        expect(completed.inboxPushTokenUnregisterIssued, isTrue);
        expect(cleanup.clearLocalPushTokenCalls, 1);
        expect(cleanup.rendezvousCalls, 1);
        expect(cleanup.inboxCalls, 2);
      },
    );

    test(
      'old phone cleanup requests local runtime stop after migrated-out commit',
      () async {
        final oldProof = await coordinator.markOldNetworkBlocked(
          sessionId: 'session-stop-runtime',
          accountPeerId: 'account-peer',
          devicePeerId: 'old-device',
        );
        final newActiveProof = oldProof.copyWith(
          devicePeerId: 'new-device',
          deviceRole: MigrationCutoverDeviceRole.newPhone,
          oldBlockProofReceived: true,
          oldBlockProofReceivedAt: clock.now(),
          newActiveCommitted: true,
          newActiveCommittedAt: clock.now(),
        );
        final cleanup = _FakeLeaseCleanup();

        await coordinator.markOldMigratedOutAfterNewActive(
          sessionId: 'session-stop-runtime',
          accountPeerId: 'account-peer',
          devicePeerId: 'old-device',
          newActiveProof: newActiveProof,
          leaseCleanup: cleanup.client,
        );

        expect(
          authority.history,
          contains(_authorityState(AccountMigrationAuthorityState.migratedOut)),
        );
        expect(cleanup.stopLocalRuntimeCalls, 1);
      },
    );

    test(
      'mismatched new active proof cannot mark old phone migrated out',
      () async {
        final validNewActiveProof =
            MigrationCutoverRecord.initial(
              sessionId: 'session-identity',
              accountPeerId: 'account-peer',
              devicePeerId: 'new-device',
              deviceRole: MigrationCutoverDeviceRole.newPhone,
              now: clock.now(),
            ).copyWith(
              phase: MigrationCutoverPhase.newActiveCommitted,
              newActiveCommitted: true,
              newActiveCommittedAt: clock.now(),
            );
        final invalidProofs = <String, MigrationCutoverRecord>{
          'session mismatch': validNewActiveProof.copyWith(
            sessionId: 'stale-session',
          ),
          'account mismatch': validNewActiveProof.copyWith(
            accountPeerId: 'other-account-peer',
          ),
          'role mismatch': validNewActiveProof.copyWith(
            deviceRole: MigrationCutoverDeviceRole.oldPhone,
          ),
        };

        for (final entry in invalidProofs.entries) {
          final localAuthority = _FakeAuthorityRepository();
          final localCutover = _FakeCutoverRepository();
          final localCoordinator = MigrationCutoverCoordinator(
            authorityRepository: localAuthority,
            cutoverRepository: localCutover,
            now: clock.now,
          );
          final cleanup = _FakeLeaseCleanup();

          final result = await localCoordinator
              .markOldMigratedOutAfterNewActive(
                sessionId: 'session-identity',
                accountPeerId: 'account-peer',
                devicePeerId: 'old-device',
                newActiveProof: entry.value,
                leaseCleanup: cleanup.client,
              );

          expect(result.oldMigratedOutCommitted, isFalse, reason: entry.key);
          expect(
            localAuthority.history,
            isNot(
              contains(
                _authorityState(AccountMigrationAuthorityState.migratedOut),
              ),
            ),
            reason: entry.key,
          );
          expect(cleanup.clearLocalPushTokenCalls, 0, reason: entry.key);
          expect(cleanup.rendezvousCalls, 0, reason: entry.key);
          expect(cleanup.inboxCalls, 0, reason: entry.key);
        }
      },
    );

    test(
      'successful lease cleanup is idempotent on duplicate retries',
      () async {
        final oldProof = await coordinator.markOldNetworkBlocked(
          sessionId: 'session-4',
          accountPeerId: 'account-peer',
          devicePeerId: 'old-device',
        );
        final newActiveProof = oldProof.copyWith(
          devicePeerId: 'new-device',
          deviceRole: MigrationCutoverDeviceRole.newPhone,
          oldBlockProofReceived: true,
          oldBlockProofReceivedAt: clock.now(),
          newActiveCommitted: true,
          newActiveCommittedAt: clock.now(),
        );
        final cleanup = _FakeLeaseCleanup();

        final completed = await coordinator.markOldMigratedOutAfterNewActive(
          sessionId: 'session-4',
          accountPeerId: 'account-peer',
          devicePeerId: 'old-device',
          newActiveProof: newActiveProof,
          leaseCleanup: cleanup.client,
        );
        expect(completed.phase, MigrationCutoverPhase.complete);

        await coordinator.retryLeaseCleanup(leaseCleanup: cleanup.client);

        expect(cleanup.clearLocalPushTokenCalls, 1);
        expect(cleanup.rendezvousCalls, 1);
        expect(cleanup.inboxCalls, 1);
      },
    );

    test('bridge lease cleanup issues explicit unregister commands', () async {
      final bridge = _RecordingBridge();
      var localPushCleared = false;
      final cleanup = buildBridgeMigrationCutoverLeaseCleanup(
        bridge: bridge,
        namespace: 'mknoon:chat:old-peer',
        serverAddresses: const ['/ip4/127.0.0.1/tcp/4001/p2p/relay'],
        clearLocalStalePushToken: () async {
          localPushCleared = true;
        },
      );

      await cleanup.clearLocalStalePushToken();
      await cleanup.unregisterPersonalRendezvous();
      await cleanup.unregisterInboxPushToken();

      expect(localPushCleared, isTrue);
      expect(bridge.commands, [
        'rendezvous:unregister',
        'inbox:unregister_token',
      ]);
      expect(bridge.payloads.first['namespace'], 'mknoon:chat:old-peer');
      expect(bridge.payloads.last, isNot(contains('token')));
    });

    test('markExportingNetworkPaused writes export-paused authority', () async {
      await coordinator.markExportingNetworkPaused(
        accountPeerId: 'account-peer',
      );

      expect(
        authority.record?.state,
        AccountMigrationAuthorityState.migrationExportingNetworkPaused,
      );
      expect(authority.record?.accountPeerId, 'account-peer');
      // Pause is authority-only; it must not fabricate a cutover record.
      expect(cutover.record, isNull);
    });

    test(
      'restoreActiveAfterExportInterrupted restores only from export pause',
      () async {
        await coordinator.markExportingNetworkPaused(
          accountPeerId: 'account-peer',
        );

        // A different fallback id must not win over the paused record's id.
        final restored = await coordinator.restoreActiveAfterExportInterrupted(
          accountPeerId: 'other-peer',
        );

        expect(restored, isTrue);
        expect(
          authority.record?.state,
          AccountMigrationAuthorityState.migrationFailedActiveRestored,
        );
        expect(authority.record?.accountPeerId, 'account-peer');
        expect(authority.record?.state.allowsNormalStartup, isTrue);
      },
    );

    test(
      'markExportingNetworkPaused is refused from blocked or ceded states',
      () async {
        for (final state in [
          AccountMigrationAuthorityState.migrationCutoverPendingBlocked,
          AccountMigrationAuthorityState.migratedOut,
          AccountMigrationAuthorityState.migrationImportStaging,
          AccountMigrationAuthorityState.migrationVerifiedWaitingForCutover,
        ]) {
          authority.record = AccountMigrationAuthorityRecord(
            state: state,
            accountPeerId: 'account-peer',
          );

          await expectLater(
            coordinator.markExportingNetworkPaused(
              accountPeerId: 'account-peer',
            ),
            throwsStateError,
            reason: state.wireName,
          );
          expect(
            authority.record?.state,
            state,
            reason: 'state must be untouched for ${state.wireName}',
          );
        }
      },
    );

    test(
      'markExportingNetworkPaused never overwrites a fail-closed record',
      () async {
        authority.record = AccountMigrationAuthorityRecord.failClosed();

        await expectLater(
          coordinator.markExportingNetworkPaused(
            accountPeerId: 'account-peer',
          ),
          throwsStateError,
        );
        expect(authority.record?.isFailClosed, isTrue);
      },
    );

    test(
      'markExportingNetworkPaused allows active, restored, and re-entry',
      () async {
        for (final state in [
          AccountMigrationAuthorityState.active,
          AccountMigrationAuthorityState.migrationFailedActiveRestored,
          AccountMigrationAuthorityState.migrationExportingNetworkPaused,
        ]) {
          authority.record = AccountMigrationAuthorityRecord(
            state: state,
            accountPeerId: 'account-peer',
          );

          await coordinator.markExportingNetworkPaused(
            accountPeerId: 'account-peer',
          );

          expect(
            authority.record?.state,
            AccountMigrationAuthorityState.migrationExportingNetworkPaused,
            reason: state.wireName,
          );
        }
      },
    );

    test(
      'restoreActiveAfterExportInterrupted never reverts a cutover block',
      () async {
        await coordinator.markExportingNetworkPaused(
          accountPeerId: 'account-peer',
        );
        await coordinator.markOldNetworkBlocked(
          sessionId: 'session-1',
          accountPeerId: 'account-peer',
          devicePeerId: 'old-device',
        );

        final restored = await coordinator.restoreActiveAfterExportInterrupted(
          accountPeerId: 'account-peer',
        );

        expect(restored, isFalse);
        expect(
          authority.record?.state,
          AccountMigrationAuthorityState.migrationCutoverPendingBlocked,
        );
      },
    );

    test(
      'restoreActiveAfterExportInterrupted is a no-op without authority',
      () async {
        final restored = await coordinator.restoreActiveAfterExportInterrupted(
          accountPeerId: 'account-peer',
        );

        expect(restored, isFalse);
        expect(authority.record, isNull);
        expect(authority.history, isEmpty);
      },
    );

    test(
      'recover() routes an old phone with pending cleanup to retryLeaseCleanup',
      () async {
        // Cold-start shape: a prior run committed the handoff but a lease
        // cleanup step never completed before the process died.
        authority.record = const AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.migratedOut,
          accountPeerId: 'account-peer',
        );
        cutover.record =
            MigrationCutoverRecord.initial(
              sessionId: 'session-9',
              accountPeerId: 'account-peer',
              devicePeerId: 'old-device',
              deviceRole: MigrationCutoverDeviceRole.oldPhone,
              now: clock.now(),
            ).copyWith(
              phase: MigrationCutoverPhase.leaseCleanupPending,
              oldNetworkBlocked: true,
              oldNetworkBlockedAt: clock.now(),
              newActiveCommitted: true,
              newActiveCommittedAt: clock.now(),
              stalePushTokenCleared: true,
              rendezvousUnregisterIssued: true,
            );

        expect(
          await coordinator.recover(),
          MigrationCutoverRecoveryDecision.retryLeaseCleanup,
        );

        // The retry completes ONLY the missing step, then recovery settles.
        final cleanup = _FakeLeaseCleanup(failInboxUnregister: false);
        final completed = await coordinator.retryLeaseCleanup(
          leaseCleanup: cleanup.client,
        );
        expect(completed.phase, MigrationCutoverPhase.complete);
        expect(cleanup.clearLocalPushTokenCalls, 0);
        expect(cleanup.rendezvousCalls, 0);
        expect(cleanup.inboxCalls, 1);
        expect(
          await coordinator.recover(),
          MigrationCutoverRecoveryDecision.newDeviceActive,
        );
      },
    );

    test(
      'a failing cleanup step does not stop later steps; first failure wins',
      () async {
        cutover.record =
            MigrationCutoverRecord.initial(
              sessionId: 'session-10',
              accountPeerId: 'account-peer',
              devicePeerId: 'old-device',
              deviceRole: MigrationCutoverDeviceRole.oldPhone,
              now: clock.now(),
            ).copyWith(
              oldNetworkBlocked: true,
              oldNetworkBlockedAt: clock.now(),
              newActiveCommitted: true,
              newActiveCommittedAt: clock.now(),
            );
        var clearCalls = 0;
        var rendezvousCalls = 0;
        var inboxCalls = 0;
        final cleanup = MigrationCutoverLeaseCleanup(
          clearLocalStalePushToken: () async => clearCalls++,
          unregisterPersonalRendezvous: () async {
            rendezvousCalls++;
            throw StateError('rendezvous down');
          },
          unregisterInboxPushToken: () async {
            inboxCalls++;
            throw TimeoutException('inbox down');
          },
        );

        final record = await coordinator.retryLeaseCleanup(
          leaseCleanup: cleanup,
        );

        expect([clearCalls, rendezvousCalls, inboxCalls], [1, 1, 1]);
        expect(record.phase, MigrationCutoverPhase.leaseCleanupPending);
        expect(record.failureCode, 'rendezvous_unregister_failed');
        expect(record.failureDetails, 'StateError');
        expect(record.stalePushTokenCleared, isTrue);
        expect(record.rendezvousUnregisterIssued, isFalse);
        expect(record.inboxPushTokenUnregisterIssued, isFalse);
      },
    );

    test('recover() demands cleanup for fail-closed records', () async {
      authority.record = AccountMigrationAuthorityRecord.failClosed();

      expect(
        await coordinator.recover(),
        MigrationCutoverRecoveryDecision.cleanupRequired,
      );
    });

    test(
      'retryLeaseCleanup without a cutover record persists a failed record',
      () async {
        final cleanup = _FakeLeaseCleanup(failInboxUnregister: false);

        final record = await coordinator.retryLeaseCleanup(
          leaseCleanup: cleanup.client,
        );

        expect(record.failureCode, 'missing_cutover_record');
        expect(cutover.record?.failureCode, 'missing_cutover_record');
        expect(cleanup.inboxCalls, 0);
      },
    );
  });
}

Matcher _authorityState(AccountMigrationAuthorityState state) {
  return isA<AccountMigrationAuthorityRecord>().having(
    (record) => record.state,
    'state',
    state,
  );
}

class _Clock {
  DateTime value;

  _Clock(this.value);

  DateTime now() {
    final current = value;
    value = value.add(const Duration(seconds: 1));
    return current;
  }
}

class _FakeAuthorityRepository implements AccountMigrationAuthorityRepository {
  AccountMigrationAuthorityRecord? record;
  final history = <AccountMigrationAuthorityRecord>[];

  @override
  Future<AccountMigrationAuthorityRecord?> loadAuthority() async => record;

  @override
  Future<void> saveAuthority(AccountMigrationAuthorityRecord record) async {
    this.record = record;
    history.add(record);
  }

  @override
  Future<void> clearAuthority() async {
    record = null;
  }
}

class _FakeCutoverRepository implements MigrationCutoverRepository {
  MigrationCutoverRecord? record;
  final history = <MigrationCutoverRecord>[];

  @override
  Future<MigrationCutoverRecord?> loadCutover() async => record;

  @override
  Future<void> saveCutover(MigrationCutoverRecord record) async {
    this.record = record;
    history.add(record);
  }

  @override
  Future<void> clearCutover() async {
    record = null;
  }
}

class _FakeLeaseCleanup {
  bool failInboxUnregister;
  int clearLocalPushTokenCalls = 0;
  int rendezvousCalls = 0;
  int inboxCalls = 0;
  int stopLocalRuntimeCalls = 0;

  _FakeLeaseCleanup({this.failInboxUnregister = false});

  MigrationCutoverLeaseCleanup get client {
    return MigrationCutoverLeaseCleanup(
      clearLocalStalePushToken: () async {
        clearLocalPushTokenCalls++;
      },
      unregisterPersonalRendezvous: () async {
        rendezvousCalls++;
      },
      unregisterInboxPushToken: () async {
        inboxCalls++;
        if (failInboxUnregister) {
          throw TimeoutException('inbox unregister stalled');
        }
      },
      stopLocalRuntime: () async {
        stopLocalRuntimeCalls++;
      },
    );
  }
}

class _RecordingBridge extends Bridge {
  final commands = <String>[];
  final payloads = <Map<String, dynamic>>[];

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    commands.add(request['cmd'] as String);
    payloads.add(request['payload'] as Map<String, dynamic>);
    return jsonEncode({'ok': true});
  }
}
