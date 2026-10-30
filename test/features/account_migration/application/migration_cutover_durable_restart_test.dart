import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_coordinator.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_repository_impl.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_cutover_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../migration_durable_fixture.dart';

enum _Cut {
  oldBlockedAuthority(true, true, 'migration_cutover_pending_blocked'),
  oldBlockedProof(true, false, 'old_network_blocked'),
  newCommittedProof(false, false, 'new_active_committed'),
  newActiveAuthority(false, true, 'active'),
  oldRetiredProof(true, false, 'old_migrated_out_committed'),
  oldRetiredAuthority(true, true, 'migrated_out');

  const _Cut(this.oldPhone, this.authorityWrite, this.value);
  final bool oldPhone;
  final bool authorityWrite;
  final String value;

  bool matches(String key, String raw) {
    final expectedKey = authorityWrite
        ? SecureKeyStoreAccountMigrationAuthorityRepository.storageKey
        : SecureKeyStoreMigrationCutoverRepository.storageKey;
    return key == expectedKey &&
        (jsonDecode(raw) as Map<String, dynamic>)[authorityWrite
                ? 'state'
                : 'phase'] ==
            value;
  }
}

final class _PowerLoss implements Exception {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  for (final cut in _Cut.values) {
    test('DC-019 TRANSFER-009 disk reopen after ${cut.name} never activates '
        'both phones or restores retired source authority', () async {
      final directory = await Directory.systemTemp.createTemp(
        'migration-cutover-',
      );
      var oldKeys = await DurableMigrationKeyStore.open(
        '${directory.path}/old.db',
      );
      var newKeys = await DurableMigrationKeyStore.open(
        '${directory.path}/new.db',
      );
      addTearDown(() async {
        await oldKeys.close();
        await newKeys.close();
        await directory.delete(recursive: true);
      });
      await oldKeys.authority.saveAuthority(
        AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.active,
          accountPeerId: migrationOwner.peerId,
        ),
      );
      await newKeys.authority.saveAuthority(
        AccountMigrationAuthorityRecord(
          state:
              AccountMigrationAuthorityState.migrationVerifiedWaitingForCutover,
          accountPeerId: migrationOwner.peerId,
        ),
      );
      var interrupted = false;
      (cut.oldPhone ? oldKeys : newKeys).afterWrite = (key, value) {
        if (!interrupted && cut.matches(key, value)) {
          interrupted = true;
          // The write has committed to a real file, but the next coordinator
          // statement must not run. This is a deterministic persistence cutpoint,
          // not a claim about power-loss atomicity of native secure storage.
          throw _PowerLoss();
        }
      };
      final cleanupCalls = <String>[];
      MigrationCutoverLeaseCleanup cleanup() => MigrationCutoverLeaseCleanup(
        clearLocalStalePushToken: () async {
          cleanupCalls.add('local-token');
        },
        unregisterPersonalRendezvous: () async {
          cleanupCalls.add('rendezvous');
        },
        unregisterInboxPushToken: () async {
          cleanupCalls.add('inbox-token');
        },
      );
      Future<void> handoff() async {
        final oldProof = await oldKeys.coordinator.markOldNetworkBlocked(
          sessionId: 'durable',
          accountPeerId: migrationOwner.peerId,
          devicePeerId: 'old-device',
        );
        await newKeys.coordinator.recordOldBlockProofReceived(
          sessionId: 'durable',
          accountPeerId: migrationOwner.peerId,
          devicePeerId: 'new-device',
          oldBlockProof: oldProof,
        );
        final newProof = await newKeys.coordinator.commitNewActive(
          sessionId: 'durable',
          accountPeerId: migrationOwner.peerId,
          devicePeerId: 'new-device',
          importVerified: true,
          oldBlockProof: oldProof,
        );
        await oldKeys.coordinator.markOldMigratedOutAfterNewActive(
          sessionId: 'durable',
          accountPeerId: migrationOwner.peerId,
          devicePeerId: 'old-device',
          newActiveProof: newProof,
          leaseCleanup: cleanup(),
        );
      }

      await expectLater(handoff(), throwsA(isA<_PowerLoss>()));
      expect(
        interrupted,
        isTrue,
        reason: 'the named write must actually be reached',
      );
      oldKeys = await oldKeys.reopen();
      newKeys = await newKeys.reopen();
      final oldAuthority = (await oldKeys.authority.loadAuthority())!;
      final newAuthority = (await newKeys.authority.loadAuthority())!;
      expect(oldAuthority.blocksNormalStartup, isTrue);
      expect(
        [
          oldAuthority,
          newAuthority,
        ].where((record) => record.state.isActiveAccountAuthority),
        hasLength(
          cut == _Cut.newActiveAuthority ||
                  cut == _Cut.oldRetiredProof ||
                  cut == _Cut.oldRetiredAuthority
              ? 1
              : 0,
        ),
      );
      expect(
        await oldKeys.networkGate.allowsAccountNetworkSideEffects(
          peerId: migrationOwner.peerId,
          operation: 'pending_retry',
        ),
        isFalse,
      );
      expect(
        await oldKeys.coordinator.restoreActiveAfterExportInterrupted(
          accountPeerId: migrationOwner.peerId,
        ),
        isFalse,
      );
      await expectLater(
        oldKeys.coordinator.markExportingNetworkPaused(
          accountPeerId: migrationOwner.peerId,
        ),
        throwsStateError,
      );
      if (!cut.authorityWrite) {
        final durableProof = await (cut.oldPhone ? oldKeys : newKeys).cutover
            .loadCutover();
        expect(durableProof!.phase.wireName, cut.value);
      }

      // Resume only public persisted transitions, loading all proof inputs from
      // the reopened stores. No fixture flag can grant an active identity.
      var oldProof = await oldKeys.cutover.loadCutover();
      if (oldProof == null || !oldProof.provesOldNetworkBlocked) {
        oldProof = await oldKeys.coordinator.markOldNetworkBlocked(
          sessionId: 'durable',
          accountPeerId: migrationOwner.peerId,
          devicePeerId: 'old-device',
        );
      }
      final newProof = await newKeys.coordinator.commitNewActive(
        sessionId: 'durable',
        accountPeerId: migrationOwner.peerId,
        devicePeerId: 'new-device',
        importVerified: true,
        oldBlockProof: oldProof,
      );
      expect(newProof.provesNewActiveCommitted, isTrue);
      await oldKeys.coordinator.markOldMigratedOutAfterNewActive(
        sessionId: 'durable',
        accountPeerId: migrationOwner.peerId,
        devicePeerId: 'old-device',
        newActiveProof: newProof,
        leaseCleanup: cleanup(),
      );
      oldKeys = await oldKeys.reopen();
      newKeys = await newKeys.reopen();
      expect(
        (await oldKeys.authority.loadAuthority())!.state,
        AccountMigrationAuthorityState.migratedOut,
      );
      expect(
        (await newKeys.authority.loadAuthority())!.state,
        AccountMigrationAuthorityState.active,
      );
      expect(
        (await oldKeys.cutover.loadCutover())!.phase,
        MigrationCutoverPhase.complete,
      );
      expect(
        await newKeys.coordinator.recover(),
        MigrationCutoverRecoveryDecision.newDeviceActive,
      );
      expect(
        await oldKeys.networkGate.allowsAccountNetworkSideEffects(
          peerId: migrationOwner.peerId,
          operation: 'inbox_replay',
        ),
        isFalse,
      );
      expect(
        await newKeys.networkGate.allowsAccountNetworkSideEffects(
          peerId: migrationOwner.peerId,
          operation: 'pending_retry',
        ),
        isTrue,
      );
      expect(
        await oldKeys.coordinator.restoreActiveAfterExportInterrupted(),
        isFalse,
      );
      expect(cleanupCalls, ['local-token', 'rendezvous', 'inbox-token']);
      await oldKeys.coordinator.retryLeaseCleanup(leaseCleanup: cleanup());
      expect(cleanupCalls, [
        'local-token',
        'rendezvous',
        'inbox-token',
      ], reason: 'persisted cleanup completion survives restart');
    });
  }
}
