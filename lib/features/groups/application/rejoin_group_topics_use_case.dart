import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
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
enum RejoinOutcome { joined, skippedNoKey, error, skippedDissolved }

class RejoinGroupTopicsResult {
  final int joinedGroupCount;
  final int skippedNoKeyCount;
  final int errorCount;
  final bool skipped;

  /// groupId → outcome for every group visited this pass.
  final Map<String, RejoinOutcome> perGroupOutcomes;

  const RejoinGroupTopicsResult({
    required this.joinedGroupCount,
    required this.skippedNoKeyCount,
    required this.errorCount,
    required this.skipped,
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
  final perGroupOutcomes = <String, RejoinOutcome>{};

  for (final group in groups) {
    final groupStopwatch = Stopwatch()..start();
    try {
      if (group.isDissolved) {
        perGroupOutcomes[group.id] = RejoinOutcome.skippedDissolved;
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REJOIN_TOPICS_SKIP_DISSOLVED',
          details: {
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
            if (group.dissolvedAt != null)
              'dissolvedAt': group.dissolvedAt!.toUtc().toIso8601String(),
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
        continue;
      }

      final keyInfo = await groupRepo.getLatestKey(group.id);
      if (keyInfo == null) {
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
        continue;
      }

      final members = await groupRepo.getMembers(group.id);

      final groupConfig = buildGroupConfigPayload(group, members);

      await callGroupJoinWithConfig(
        bridge,
        groupId: group.id,
        groupConfig: groupConfig,
        groupKey: keyInfo.encryptedKey,
        keyEpoch: keyInfo.keyGeneration,
      );
      joinedGroupCount++;
      perGroupOutcomes[group.id] = RejoinOutcome.joined;

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REJOIN_TOPICS_JOINED',
        details: {
          'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
          'keyEpoch': keyInfo.keyGeneration,
          'memberCount': members.length,
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
          'memberCount': members.length,
        },
      );
    } catch (e) {
      errorCount++;
      perGroupOutcomes[group.id] = RejoinOutcome.error;
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
    }
  }

  final result = RejoinGroupTopicsResult(
    joinedGroupCount: joinedGroupCount,
    skippedNoKeyCount: skippedNoKeyCount,
    errorCount: errorCount,
    skipped: false,
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
