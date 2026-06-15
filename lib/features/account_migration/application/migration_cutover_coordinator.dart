import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_cutover_record.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_cutover_repository.dart';

typedef MigrationCutoverNow = DateTime Function();
typedef MigrationCutoverCleanupCommand = Future<void> Function();

class MigrationCutoverLeaseCleanup {
  final MigrationCutoverCleanupCommand unregisterPersonalRendezvous;
  final MigrationCutoverCleanupCommand unregisterInboxPushToken;
  final MigrationCutoverCleanupCommand clearLocalStalePushToken;
  final MigrationCutoverCleanupCommand? stopLocalRuntime;

  const MigrationCutoverLeaseCleanup({
    required this.unregisterPersonalRendezvous,
    required this.unregisterInboxPushToken,
    required this.clearLocalStalePushToken,
    this.stopLocalRuntime,
  });
}

enum MigrationCutoverRecoveryDecision {
  oldDeviceActive,
  waitForOldBlockProof,
  retryNewActiveCommit,
  retryLeaseCleanup,
  newDeviceActive,
  cleanupRequired,
}

class MigrationCutoverCoordinator {
  final AccountMigrationAuthorityRepository _authorityRepository;
  final MigrationCutoverRepository _cutoverRepository;
  final MigrationCutoverNow _now;

  const MigrationCutoverCoordinator({
    required AccountMigrationAuthorityRepository authorityRepository,
    required MigrationCutoverRepository cutoverRepository,
    MigrationCutoverNow? now,
  }) : _authorityRepository = authorityRepository,
       _cutoverRepository = cutoverRepository,
       _now = now ?? DateTime.now;

  /// Pauses this old phone's account network side effects for the duration of
  /// a Move Account export, so the relay inbox is not drained (and
  /// ACK-deleted) after the bundle snapshot has been frozen. Messages that
  /// arrive during the transfer stay on the relay for the new phone.
  ///
  /// State-guarded: only an active-authority device (or a re-entrant export
  /// overlap) may pause. Throws [StateError] otherwise so a blocked,
  /// migrated-out, or fail-closed device can never be laundered back to
  /// active through the pause→restore sequence.
  Future<void> markExportingNetworkPaused({
    required String accountPeerId,
  }) async {
    final existing = await _authorityRepository.loadAuthority();
    if (existing != null) {
      if (existing.isFailClosed) {
        throw StateError(
          'account migration authority is fail-closed; export pause refused',
        );
      }
      final state = existing.state;
      final canPause =
          state ==
              AccountMigrationAuthorityState.migrationExportingNetworkPaused ||
          state == AccountMigrationAuthorityState.noAccount ||
          state.isActiveAccountAuthority;
      if (!canPause) {
        throw StateError(
          'export pause refused from authority state ${state.wireName}',
        );
      }
    }
    await _authorityRepository.saveAuthority(
      AccountMigrationAuthorityRecord(
        state: AccountMigrationAuthorityState.migrationExportingNetworkPaused,
        accountPeerId: accountPeerId,
      ),
    );
  }

  /// Restores active account authority after an interrupted export.
  ///
  /// Applies only while the authority is still export-paused, so a completed
  /// handoff (`migrationCutoverPendingBlocked` / `migratedOut`) is never
  /// reverted. Returns whether a restore was performed. [accountPeerId] is a
  /// fallback only; the paused record's own peer id wins.
  Future<bool> restoreActiveAfterExportInterrupted({
    String? accountPeerId,
  }) async {
    final existing = await _authorityRepository.loadAuthority();
    if (existing == null ||
        existing.isFailClosed ||
        existing.state !=
            AccountMigrationAuthorityState.migrationExportingNetworkPaused) {
      return false;
    }
    await _authorityRepository.saveAuthority(
      AccountMigrationAuthorityRecord(
        state: AccountMigrationAuthorityState.migrationFailedActiveRestored,
        accountPeerId: existing.accountPeerId ?? accountPeerId,
      ),
    );
    return true;
  }

  Future<MigrationCutoverRecord> markOldNetworkBlocked({
    required String sessionId,
    required String accountPeerId,
    required String devicePeerId,
  }) async {
    final now = _now().toUtc();
    final existing = await _cutoverRepository.loadCutover();
    final base = _baseRecord(
      existing,
      sessionId: sessionId,
      accountPeerId: accountPeerId,
      devicePeerId: devicePeerId,
      deviceRole: MigrationCutoverDeviceRole.oldPhone,
      now: now,
    );

    await _authorityRepository.saveAuthority(
      AccountMigrationAuthorityRecord(
        state: AccountMigrationAuthorityState.migrationCutoverPendingBlocked,
        accountPeerId: accountPeerId,
      ),
    );

    final blocked = base.copyWith(
      deviceRole: MigrationCutoverDeviceRole.oldPhone,
      phase: MigrationCutoverPhase.oldNetworkBlocked,
      oldNetworkBlocked: true,
      oldNetworkBlockedAt: base.oldNetworkBlockedAt ?? now,
      updatedAt: now,
      clearFailure: true,
    );
    await _cutoverRepository.saveCutover(blocked);
    return blocked;
  }

  Future<MigrationCutoverRecord> recordOldBlockProofReceived({
    required String sessionId,
    required String accountPeerId,
    required String devicePeerId,
    required MigrationCutoverRecord oldBlockProof,
  }) async {
    final now = _now().toUtc();
    final existing = await _cutoverRepository.loadCutover();
    final base = _baseRecord(
      existing,
      sessionId: sessionId,
      accountPeerId: accountPeerId,
      devicePeerId: devicePeerId,
      deviceRole: MigrationCutoverDeviceRole.newPhone,
      now: now,
    );
    final proved = oldBlockProof.provesOldNetworkBlocked;
    final record = base.copyWith(
      deviceRole: MigrationCutoverDeviceRole.newPhone,
      phase: proved
          ? MigrationCutoverPhase.oldBlockProofReceived
          : MigrationCutoverPhase.leaseCleanupPending,
      oldNetworkBlocked: proved,
      oldNetworkBlockedAt: proved
          ? oldBlockProof.oldNetworkBlockedAt ?? now
          : base.oldNetworkBlockedAt,
      oldBlockProofReceived: proved,
      oldBlockProofReceivedAt: proved
          ? base.oldBlockProofReceivedAt ?? now
          : base.oldBlockProofReceivedAt,
      updatedAt: now,
      clearFailure: true,
    );
    await _authorityRepository.saveAuthority(
      AccountMigrationAuthorityRecord(
        state:
            AccountMigrationAuthorityState.migrationVerifiedWaitingForCutover,
        accountPeerId: accountPeerId,
      ),
    );
    await _cutoverRepository.saveCutover(record);
    return record;
  }

  Future<MigrationCutoverRecord> commitNewActive({
    required String sessionId,
    required String accountPeerId,
    required String devicePeerId,
    required bool importVerified,
    required MigrationCutoverRecord oldBlockProof,
  }) async {
    final now = _now().toUtc();
    final existing = await _cutoverRepository.loadCutover();
    final base = _baseRecord(
      existing,
      sessionId: sessionId,
      accountPeerId: accountPeerId,
      devicePeerId: devicePeerId,
      deviceRole: MigrationCutoverDeviceRole.newPhone,
      now: now,
    );

    if (!importVerified) {
      final failed = base.copyWith(
        deviceRole: MigrationCutoverDeviceRole.newPhone,
        phase: MigrationCutoverPhase.failed,
        updatedAt: now,
        failureCode: 'import_not_verified',
        failureDetails: 'import verification must pass before cutover',
      );
      await _authorityRepository.saveAuthority(
        AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.migrationFailedCleanupRequired,
          accountPeerId: accountPeerId,
        ),
      );
      await _cutoverRepository.saveCutover(failed);
      return failed;
    }

    if (!_isValidOldBlockProof(
      oldBlockProof,
      sessionId: sessionId,
      accountPeerId: accountPeerId,
    )) {
      final pending = base.copyWith(
        deviceRole: MigrationCutoverDeviceRole.newPhone,
        phase: MigrationCutoverPhase.oldBlockProofReceived,
        oldNetworkBlocked: false,
        oldBlockProofReceived: false,
        newActiveCommitted: false,
        updatedAt: now,
      );
      await _authorityRepository.saveAuthority(
        AccountMigrationAuthorityRecord(
          state:
              AccountMigrationAuthorityState.migrationVerifiedWaitingForCutover,
          accountPeerId: accountPeerId,
        ),
      );
      await _cutoverRepository.saveCutover(pending);
      return pending;
    }

    final committed = base.copyWith(
      deviceRole: MigrationCutoverDeviceRole.newPhone,
      phase: MigrationCutoverPhase.newActiveCommitted,
      oldNetworkBlocked: true,
      oldNetworkBlockedAt: oldBlockProof.oldNetworkBlockedAt ?? now,
      oldBlockProofReceived: true,
      oldBlockProofReceivedAt: base.oldBlockProofReceivedAt ?? now,
      newActiveCommitted: true,
      newActiveCommittedAt: base.newActiveCommittedAt ?? now,
      updatedAt: now,
      clearFailure: true,
    );

    await _cutoverRepository.saveCutover(committed);
    await _authorityRepository.saveAuthority(
      AccountMigrationAuthorityRecord(
        state: AccountMigrationAuthorityState.active,
        accountPeerId: accountPeerId,
      ),
    );
    return committed;
  }

  Future<MigrationCutoverRecord> markOldMigratedOutAfterNewActive({
    required String sessionId,
    required String accountPeerId,
    required String devicePeerId,
    required MigrationCutoverRecord newActiveProof,
    required MigrationCutoverLeaseCleanup leaseCleanup,
  }) async {
    final now = _now().toUtc();
    final existing = await _cutoverRepository.loadCutover();
    final base = _baseRecord(
      existing,
      sessionId: sessionId,
      accountPeerId: accountPeerId,
      devicePeerId: devicePeerId,
      deviceRole: MigrationCutoverDeviceRole.oldPhone,
      now: now,
    );

    if (!_isValidNewActiveProof(
      newActiveProof,
      sessionId: sessionId,
      accountPeerId: accountPeerId,
    )) {
      final pending = base.copyWith(
        deviceRole: MigrationCutoverDeviceRole.oldPhone,
        phase: MigrationCutoverPhase.oldNetworkBlocked,
        updatedAt: now,
      );
      await _cutoverRepository.saveCutover(pending);
      return pending;
    }

    final migratedOut = base.copyWith(
      deviceRole: MigrationCutoverDeviceRole.oldPhone,
      phase: MigrationCutoverPhase.oldMigratedOutCommitted,
      oldNetworkBlocked: true,
      oldNetworkBlockedAt: base.oldNetworkBlockedAt ?? now,
      oldBlockProofReceived: true,
      oldBlockProofReceivedAt: base.oldBlockProofReceivedAt ?? now,
      newActiveCommitted: true,
      newActiveCommittedAt: newActiveProof.newActiveCommittedAt ?? now,
      oldMigratedOutCommitted: true,
      oldMigratedOutCommittedAt: base.oldMigratedOutCommittedAt ?? now,
      updatedAt: now,
      clearFailure: true,
    );
    await _cutoverRepository.saveCutover(migratedOut);
    await _authorityRepository.saveAuthority(
      AccountMigrationAuthorityRecord(
        state: AccountMigrationAuthorityState.migratedOut,
        accountPeerId: accountPeerId,
      ),
    );

    return retryLeaseCleanup(leaseCleanup: leaseCleanup);
  }

  Future<MigrationCutoverRecord> retryLeaseCleanup({
    required MigrationCutoverLeaseCleanup leaseCleanup,
  }) async {
    final loaded = await _cutoverRepository.loadCutover();
    if (loaded == null) {
      final now = _now().toUtc();
      final failed =
          MigrationCutoverRecord.initial(
            sessionId: 'unknown',
            accountPeerId: 'unknown',
            devicePeerId: 'unknown',
            deviceRole: MigrationCutoverDeviceRole.oldPhone,
            now: now,
          ).copyWith(
            phase: MigrationCutoverPhase.failed,
            updatedAt: now,
            failureCode: 'missing_cutover_record',
            failureDetails: 'lease cleanup requires a durable cutover record',
          );
      await _cutoverRepository.saveCutover(failed);
      return failed;
    }

    var record = loaded;
    final now = _now().toUtc();
    var hadFailure = false;
    String? failureCode;
    String? failureDetails;

    Future<void> runStep({
      required bool alreadyComplete,
      required MigrationCutoverCleanupCommand command,
      required String code,
      required MigrationCutoverRecord Function(MigrationCutoverRecord)
      markComplete,
    }) async {
      if (alreadyComplete) return;
      try {
        await command();
        record = markComplete(
          record.copyWith(
            updatedAt: _now().toUtc(),
            leaseCleanupAttemptedAt: _now().toUtc(),
          ),
        );
        await _cutoverRepository.saveCutover(record);
      } catch (error) {
        hadFailure = true;
        failureCode ??= code;
        failureDetails ??= _safeFailureDetails(error);
        record = record.copyWith(
          phase: MigrationCutoverPhase.leaseCleanupPending,
          updatedAt: _now().toUtc(),
          leaseCleanupAttemptedAt: _now().toUtc(),
          failureCode: failureCode,
          failureDetails: failureDetails,
        );
        await _cutoverRepository.saveCutover(record);
      }
    }

    // Local token clear runs before remote unregister so stale old-device token
    // material cannot be reused by this primitive if later cleanup is retried.
    await runStep(
      alreadyComplete: record.stalePushTokenCleared,
      command: leaseCleanup.clearLocalStalePushToken,
      code: 'clear_stale_push_token_failed',
      markComplete: (value) => value.copyWith(stalePushTokenCleared: true),
    );
    await runStep(
      alreadyComplete: record.rendezvousUnregisterIssued,
      command: leaseCleanup.unregisterPersonalRendezvous,
      code: 'rendezvous_unregister_failed',
      markComplete: (value) => value.copyWith(rendezvousUnregisterIssued: true),
    );
    await runStep(
      alreadyComplete: record.inboxPushTokenUnregisterIssued,
      command: leaseCleanup.unregisterInboxPushToken,
      code: 'inbox_push_token_unregister_failed',
      markComplete: (value) =>
          value.copyWith(inboxPushTokenUnregisterIssued: true),
    );
    final stopLocalRuntime = leaseCleanup.stopLocalRuntime;
    if (stopLocalRuntime != null) {
      try {
        await stopLocalRuntime();
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_OLD_RUNTIME_STOP_REQUESTED',
          details: {},
        );
      } catch (error) {
        // The persisted migrated-out authority remains the hard safety gate.
        // Runtime stop is best-effort so migration is not reported failed after
        // the new phone has already committed active state.
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_OLD_RUNTIME_STOP_FAILED',
          details: {'error': _safeFailureDetails(error)},
        );
      }
    }

    final refreshed = await _cutoverRepository.loadCutover() ?? record;
    final completed = refreshed.copyWith(
      phase: hadFailure || refreshed.hasPendingLeaseCleanup
          ? MigrationCutoverPhase.leaseCleanupPending
          : MigrationCutoverPhase.complete,
      updatedAt: _now().toUtc(),
      leaseCleanupAttemptedAt: refreshed.leaseCleanupAttemptedAt ?? now,
      clearFailure: !hadFailure && !refreshed.hasPendingLeaseCleanup,
    );
    await _cutoverRepository.saveCutover(completed);
    return completed;
  }

  Future<MigrationCutoverRecoveryDecision> recover() async {
    final authority = await _authorityRepository.loadAuthority();
    final cutover = await _cutoverRepository.loadCutover();
    if (authority?.isFailClosed == true || cutover?.isFailClosed == true) {
      return MigrationCutoverRecoveryDecision.cleanupRequired;
    }

    if (authority?.state == AccountMigrationAuthorityState.active &&
        cutover == null) {
      return MigrationCutoverRecoveryDecision.oldDeviceActive;
    }

    if (cutover == null || !cutover.oldNetworkBlocked) {
      return MigrationCutoverRecoveryDecision.oldDeviceActive;
    }

    if (cutover.provesNewActiveCommitted ||
        authority?.state == AccountMigrationAuthorityState.active) {
      if (cutover.deviceRole == MigrationCutoverDeviceRole.oldPhone &&
          cutover.hasPendingLeaseCleanup) {
        return MigrationCutoverRecoveryDecision.retryLeaseCleanup;
      }
      return MigrationCutoverRecoveryDecision.newDeviceActive;
    }

    if (cutover.oldNetworkBlocked && !cutover.oldBlockProofReceived) {
      return MigrationCutoverRecoveryDecision.waitForOldBlockProof;
    }

    return MigrationCutoverRecoveryDecision.retryNewActiveCommit;
  }

  MigrationCutoverRecord _baseRecord(
    MigrationCutoverRecord? existing, {
    required String sessionId,
    required String accountPeerId,
    required String devicePeerId,
    required MigrationCutoverDeviceRole deviceRole,
    required DateTime now,
  }) {
    if (existing != null && existing.sessionId == sessionId) {
      return existing.copyWith(
        accountPeerId: accountPeerId,
        devicePeerId: devicePeerId,
        deviceRole: deviceRole,
        updatedAt: now,
      );
    }
    return MigrationCutoverRecord.initial(
      sessionId: sessionId,
      accountPeerId: accountPeerId,
      devicePeerId: devicePeerId,
      deviceRole: deviceRole,
      now: now,
    );
  }

  bool _isValidOldBlockProof(
    MigrationCutoverRecord proof, {
    required String sessionId,
    required String accountPeerId,
  }) {
    return proof.sessionId == sessionId &&
        proof.accountPeerId == accountPeerId &&
        proof.deviceRole == MigrationCutoverDeviceRole.oldPhone &&
        proof.provesOldNetworkBlocked;
  }

  bool _isValidNewActiveProof(
    MigrationCutoverRecord proof, {
    required String sessionId,
    required String accountPeerId,
  }) {
    return proof.sessionId == sessionId &&
        proof.accountPeerId == accountPeerId &&
        proof.deviceRole == MigrationCutoverDeviceRole.newPhone &&
        proof.provesNewActiveCommitted;
  }
}

String _safeFailureDetails(Object error) {
  final text = error.runtimeType.toString();
  if (text.length <= 80) return text;
  return text.substring(0, 80);
}
