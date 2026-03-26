import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// The reason for calling rejoinGroupTopics.
enum RejoinReason {
  /// App startup — always rejoin all topics.
  startup,

  /// Watchdog restart — Go node was restarted, topics are gone.
  watchdogRestart,

  /// Go explicitly requested rejoin because topics may be missing.
  nodeRequestedRecovery,

  /// In-place recovery succeeded — topics should still be active.
  inPlaceRecovery,
}

class RejoinGroupTopicsResult {
  final int joinedGroupCount;
  final int skippedNoKeyCount;
  final int errorCount;
  final bool skipped;

  const RejoinGroupTopicsResult({
    required this.joinedGroupCount,
    required this.skippedNoKeyCount,
    required this.errorCount,
    required this.skipped,
  });
}

/// Rejoins all group pubsub topics on startup or after watchdog restart.
///
/// After an app restart or watchdog restart the Go node is fresh — no pubsub
/// topics are subscribed. This function iterates every group (including
/// archived), builds the full groupConfig from stored members, and calls
/// [callGroupJoinWithConfig] so the node can receive and validate
/// real-time group messages again.
///
/// When [reason] is [RejoinReason.inPlaceRecovery], the rejoin is skipped
/// because topics are still active in the Go node. This makes the function
/// idempotent for in-place recovery scenarios.
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
  // Skip rejoin when in-place recovery succeeded — topics are still active.
  if (reason == RejoinReason.inPlaceRecovery) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REJOIN_TOPICS_SKIPPED',
      details: {'reason': 'inPlaceRecovery'},
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REJOIN_TOPICS_TIMING',
      details: {
        'scope': 'batch',
        'elapsedMs': rejoinStopwatch.elapsedMilliseconds,
        'outcome': 'skipped',
        'reason': reason.name,
      },
    );
    return const RejoinGroupTopicsResult(
      joinedGroupCount: 0,
      skippedNoKeyCount: 0,
      errorCount: 0,
      skipped: true,
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REJOIN_TOPICS_BEGIN',
    details: {'reason': reason.name},
  );

  final groups = await groupRepo.getAllGroups();
  var joinedGroupCount = 0;
  var skippedNoKeyCount = 0;
  var errorCount = 0;

  for (final group in groups) {
    final groupStopwatch = Stopwatch()..start();
    try {
      final keyInfo = await groupRepo.getLatestKey(group.id);
      if (keyInfo == null) {
        skippedNoKeyCount++;
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

      final groupConfig = {
        'name': group.name,
        'groupType': group.type.toValue(),
        if (group.description != null) 'description': group.description,
        'members': members
            .map(
              (m) => {
                'peerId': m.peerId,
                'username': m.username,
                'role': m.role.toValue(),
                'publicKey': m.publicKey,
                if (m.mlKemPublicKey != null)
                  'mlKemPublicKey': m.mlKemPublicKey,
              },
            )
            .toList(),
        'createdBy': group.createdBy,
        'createdAt': group.createdAt.toUtc().toIso8601String(),
      };

      await callGroupJoinWithConfig(
        bridge,
        groupId: group.id,
        groupConfig: groupConfig,
        groupKey: keyInfo.encryptedKey,
        keyEpoch: keyInfo.keyGeneration,
      );
      joinedGroupCount++;

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

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REJOIN_TOPICS_DONE',
    details: {
      'groupCount': groups.length,
      'joinedGroupCount': joinedGroupCount,
      'skippedNoKeyCount': skippedNoKeyCount,
      'errorCount': errorCount,
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

  return RejoinGroupTopicsResult(
    joinedGroupCount: joinedGroupCount,
    skippedNoKeyCount: skippedNoKeyCount,
    errorCount: errorCount,
    skipped: false,
  );
}
