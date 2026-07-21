import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/application/self_removed_group_lifecycle_guard.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// The reason for calling rejoinGroupTopics.
enum RejoinReason {
  /// App startup — always rejoin all topics.
  startup,

  /// Watchdog restart — Go node was restarted, topics are gone.
  watchdogRestart,

  /// Go explicitly requested rejoin because topics may be missing.
  nodeRequestedRecovery,

  /// In-place recovery succeeded — refresh topics idempotently because the
  /// transport can recover while pubsub peers still need to converge again.
  inPlaceRecovery,
}

/// Per-group result of a single rejoin pass. Exposed so callers (and a future
/// per-group Go ack) can reason about which specific groups are still
/// un-recovered rather than only the batch aggregates.
enum RejoinOutcome {
  joined,
  skippedNoKey,
  error,
  skippedDissolved,
  skippedSelfRemoved,
  skippedExitInProgress,
  deferred,
}

class RejoinGroupTopicsResult {
  final int joinedGroupCount;
  final int skippedNoKeyCount;
  final int errorCount;
  final bool skipped;

  /// Finding 05 Phase 3: groups skipped this pass because they are inside their
  /// rejoin-backoff window (a prior attempt failed). Does not block the ack.
  final int deferredCount;

  /// groupId → outcome for every group visited this pass.
  final Map<String, RejoinOutcome> perGroupOutcomes;

  const RejoinGroupTopicsResult({
    required this.joinedGroupCount,
    required this.skippedNoKeyCount,
    required this.errorCount,
    required this.skipped,
    this.deferredCount = 0,
    this.perGroupOutcomes = const {},
  });

  /// Whether this pass may acknowledge group recovery to the relay.
  ///
  /// The Go ack is **node-wide** (it takes no groupId), so eligibility is
  /// computed over the *recoverable* set:
  ///   * A group skipped for **no key material** is NOT a transient miss — it
  ///     stays un-rejoinable until a key arrives, and key arrival re-triggers
  ///     its own rejoin+drain. Blocking the node-wide ack on it would leave
  ///     `needsGroupRecovery` stuck forever (the relay never hears we caught up
  ///     for every *other* group), so no-key groups do NOT block the ack.
  ///   * A transient per-group **error** still blocks: a failed rejoin may mean
  ///     we missed live messages for that group, and with a node-wide ack we
  ///     conservatively withhold the whole ack until a later pass clears it.
  bool get canAcknowledgeGroupRecovery => !skipped && errorCount == 0;
}

// Finding 05 Phase 3: bounded per-group rejoin retry. A persistently-failing
// rejoin is backed off (base 30s ×2, cap 30min) instead of hammered every pass,
// and a group that exceeds [_maxRejoinAttempts] is reported as permanently
// stuck via GROUP_REJOIN_PERMANENTLY_STUCK.
const Duration _rejoinBackoffBase = Duration(seconds: 30);
const Duration _rejoinBackoffCap = Duration(minutes: 30);
const int _maxRejoinAttempts = 10;

Duration _rejoinBackoffDelay(int attempt) {
  final baseMs = _rejoinBackoffBase.inMilliseconds;
  final capMs = _rejoinBackoffCap.inMilliseconds;
  final raw = baseMs * (1 << attempt.clamp(0, 20));
  return Duration(milliseconds: raw > capMs ? capMs : raw);
}

/// Rejoins all group pubsub topics on startup or after watchdog restart.
///
/// After an app restart or watchdog restart the Go node is fresh — no pubsub
/// topics are subscribed. This function iterates every group (including
/// archived), builds the full groupConfig from stored members, and calls
/// [callGroupJoinWithConfig] so the node can receive and validate
/// real-time group messages again.
///
/// In-place recovery still refreshes topics because transport recovery does not
/// guarantee that the pubsub mesh has fully converged again. The join call is
/// idempotent, so this remains safe even when the topic is already active.
///
/// Groups without a stored key are skipped (can't join without key material).
/// Errors on individual groups are logged and do not prevent other groups
/// from being rejoined.
Future<RejoinGroupTopicsResult> rejoinGroupTopics({
  required Bridge bridge,
  required GroupRepository groupRepo,
  RejoinReason reason = RejoinReason.startup,
  Future<bool> Function(String groupId)? canRejoinForExitIntent,
  Future<void> Function(String groupId)? processExitIntent,
}) async {
  final rejoinStopwatch = Stopwatch()..start();
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REJOIN_TOPICS_BEGIN',
    details: {'reason': reason.name},
  );

  final groups = await groupRepo.getAllGroups();
  var joinedGroupCount = 0;
  var skippedNoKeyCount = 0;
  var errorCount = 0;
  var deferredCount = 0;
  final perGroupOutcomes = <String, RejoinOutcome>{};

  // Finding 05 Phase 3: per-group rejoin backoff state (sparse — only failing
  // groups have an entry). Loaded once per pass.
  final rejoinStates = await groupRepo.loadGroupRejoinStates();
  final nowUtc = DateTime.now().toUtc();

  Future<void> processExitBestEffort(String groupId) async {
    final processExit = processExitIntent;
    if (processExit == null) return;
    try {
      // Rejoin is only a lifecycle trigger for skipped branches. The exit
      // runner owns terminal authority and decides whether network work is
      // legal; dissolved/self-removed/native-leave cleanup remains local-only.
      await processExit(groupId);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REJOIN_EXIT_INTENT_PROCESS_ERROR',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'error': error.toString(),
        },
      );
    }
  }

  for (final group in groups) {
    final groupStopwatch = Stopwatch()..start();
    final rejoinState = rejoinStates[group.id];
    try {
      final guarded =
          await runSelfRemovedGroupLifecycleLeaf<
            ({
              RejoinOutcome outcome,
              int? keyEpoch,
              int memberCount,
              DateTime? dissolvedAt,
            })
          >(
            groupRepo: groupRepo,
            groupId: group.id,
            action: (currentGroup) async {
              final canRejoin = canRejoinForExitIntent;
              if (canRejoin != null && !await canRejoin(group.id)) {
                return (
                  outcome: RejoinOutcome.skippedExitInProgress,
                  keyEpoch: null,
                  memberCount: 0,
                  dissolvedAt: null,
                );
              }
              if (currentGroup.isDissolved) {
                return (
                  outcome: RejoinOutcome.skippedDissolved,
                  keyEpoch: null,
                  memberCount: 0,
                  dissolvedAt: currentGroup.dissolvedAt,
                );
              }

              final keyInfo = await groupRepo.getLatestKey(group.id);
              if (keyInfo == null) {
                return (
                  outcome: RejoinOutcome.skippedNoKey,
                  keyEpoch: null,
                  memberCount: 0,
                  dissolvedAt: null,
                );
              }

              // Finding 05 Phase 3: skip a group still inside its rejoin-backoff
              // window. The shortlist is batch-loaded, but the external join still
              // owns a fresh lifecycle read in this per-group phase.
              if (rejoinState?.nextEligibleAt != null &&
                  rejoinState!.nextEligibleAt!.isAfter(nowUtc)) {
                return (
                  outcome: RejoinOutcome.deferred,
                  keyEpoch: keyInfo.keyGeneration,
                  memberCount: 0,
                  dissolvedAt: null,
                );
              }

              final members = await groupRepo.getMembers(group.id);
              final groupConfig = buildGroupConfigPayload(
                currentGroup,
                members,
              );
              await callGroupJoinWithConfig(
                bridge,
                groupId: group.id,
                groupConfig: groupConfig,
                groupKey: keyInfo.encryptedKey,
                keyEpoch: keyInfo.keyGeneration,
              );
              if (rejoinState != null) {
                try {
                  await groupRepo.clearGroupRejoinState(group.id);
                } catch (_) {}
              }
              return (
                outcome: RejoinOutcome.joined,
                keyEpoch: keyInfo.keyGeneration,
                memberCount: members.length,
                dissolvedAt: null,
              );
            },
          );

      if (!guarded.didRun) {
        perGroupOutcomes[group.id] = RejoinOutcome.skippedSelfRemoved;
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REJOIN_TOPICS_SKIP_SELF_REMOVED',
          details: {
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
            'disposition': guarded.disposition.name,
          },
        );
        await processExitBestEffort(group.id);
        continue;
      }

      final leaf = guarded.value!;
      if (leaf.outcome == RejoinOutcome.skippedExitInProgress) {
        perGroupOutcomes[group.id] = RejoinOutcome.skippedExitInProgress;
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REJOIN_TOPICS_SKIP_EXIT_IN_PROGRESS',
          details: {
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
          },
        );
        await processExitBestEffort(group.id);
        continue;
      }
      if (leaf.outcome == RejoinOutcome.skippedDissolved) {
        perGroupOutcomes[group.id] = RejoinOutcome.skippedDissolved;
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REJOIN_TOPICS_SKIP_DISSOLVED',
          details: {
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
            if (leaf.dissolvedAt != null)
              'dissolvedAt': leaf.dissolvedAt!.toUtc().toIso8601String(),
          },
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REJOIN_TOPICS_TIMING',
          details: {
            'scope': 'group',
            'elapsedMs': groupStopwatch.elapsedMilliseconds,
            'outcome': 'skip_dissolved',
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
          },
        );
        await processExitBestEffort(group.id);
        continue;
      }

      if (leaf.outcome == RejoinOutcome.skippedNoKey) {
        skippedNoKeyCount++;
        perGroupOutcomes[group.id] = RejoinOutcome.skippedNoKey;
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REJOIN_TOPICS_SKIP_NO_KEY',
          details: {
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
          },
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REJOIN_TOPICS_TIMING',
          details: {
            'scope': 'group',
            'elapsedMs': groupStopwatch.elapsedMilliseconds,
            'outcome': 'skip_no_key',
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
          },
        );
        await processExitBestEffort(group.id);
        continue;
      }

      if (leaf.outcome == RejoinOutcome.deferred) {
        deferredCount++;
        perGroupOutcomes[group.id] = RejoinOutcome.deferred;
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REJOIN_TOPICS_SKIP_BACKOFF',
          details: {
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
            'attempt': rejoinState!.attemptCount,
          },
        );
        await processExitBestEffort(group.id);
        continue;
      }

      joinedGroupCount++;
      perGroupOutcomes[group.id] = RejoinOutcome.joined;

      // Finding 07 (S2b / G4): now that this group's topic is rejoined, drain
      // any durable broadcasts (metadata/membership edits) that failed to leave
      // the device — converging on the path that just reconnected instead of
      // waiting for the next app-resume drainAll. Never throws (sink-wrapped);
      // a no-op when nothing is queued or no sink is wired.
      await triggerGroupPendingBroadcastDrainForGroup(group.id);
      await processExitBestEffort(group.id);

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REJOIN_TOPICS_JOINED',
        details: {
          'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
          'keyEpoch': leaf.keyEpoch,
          'memberCount': leaf.memberCount,
        },
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REJOIN_TOPICS_TIMING',
        details: {
          'scope': 'group',
          'elapsedMs': groupStopwatch.elapsedMilliseconds,
          'outcome': 'joined',
          'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
          'memberCount': leaf.memberCount,
        },
      );
    } catch (e) {
      errorCount++;
      perGroupOutcomes[group.id] = RejoinOutcome.error;
      final attempt = (rejoinState?.attemptCount ?? 0) + 1;
      try {
        await groupRepo.recordGroupRejoinFailure(
          group.id,
          nextEligibleAt: nowUtc.add(_rejoinBackoffDelay(attempt)),
        );
      } catch (_) {}
      if (attempt >= _maxRejoinAttempts) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REJOIN_PERMANENTLY_STUCK',
          details: {
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
            'attempt': attempt,
          },
        );
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REJOIN_TOPICS_ERROR',
        details: {
          'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
          'error': e.toString(),
        },
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REJOIN_TOPICS_TIMING',
        details: {
          'scope': 'group',
          'elapsedMs': groupStopwatch.elapsedMilliseconds,
          'outcome': 'error',
          'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
        },
      );
      await processExitBestEffort(group.id);
    }
  }

  final result = RejoinGroupTopicsResult(
    joinedGroupCount: joinedGroupCount,
    skippedNoKeyCount: skippedNoKeyCount,
    errorCount: errorCount,
    skipped: false,
    deferredCount: deferredCount,
    perGroupOutcomes: perGroupOutcomes,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REJOIN_TOPICS_DONE',
    details: {
      'groupCount': groups.length,
      'joinedGroupCount': joinedGroupCount,
      'skippedNoKeyCount': skippedNoKeyCount,
      'errorCount': errorCount,
      'deferredCount': deferredCount,
      // Node-wide ack eligibility: no-key groups no longer block it; only
      // transient errors do (see RejoinGroupTopicsResult.canAcknowledgeGroupRecovery).
      'canAcknowledgeGroupRecovery': result.canAcknowledgeGroupRecovery,
    },
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REJOIN_TOPICS_TIMING',
    details: {
      'scope': 'batch',
      'elapsedMs': rejoinStopwatch.elapsedMilliseconds,
      'outcome': 'complete',
      'reason': reason.name,
      'groupCount': groups.length,
      'joinedGroupCount': joinedGroupCount,
      'skippedNoKeyCount': skippedNoKeyCount,
      'errorCount': errorCount,
    },
  );

  return result;
}
