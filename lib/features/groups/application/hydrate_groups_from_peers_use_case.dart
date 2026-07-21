import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/config/multi_device_sync_flag.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// B3 (Part B of 12-P2): the production analogue of the test-only
/// `mirrorJoinedGroupState`. After a restored device has been re-admitted and
/// has received the current group key (B1b: device_announce → admission →
/// re-distribution), this converges its group state by reusing the existing
/// production primitives — it does NOT hand-copy keys:
///   1. [rejoinGroupTopics] re-subscribes to every known group topic so live +
///      relay traffic flows to the device again.
///   2. [drainGroupOfflineInboxForGroup] pulls each group's relay backlog so
///      missed history converges.
///
/// Group/member/metadata STATE itself arrives via the existing authoritative
/// group-config propagation once the device is admitted (it rides the config
/// payload); this use case is the catch-up step over that learned state. It does
/// not invent a device→device "pull roster" RPC (none exists).
///
/// Flag-gated (default-OFF). Best-effort per group. Returns the number of
/// non-dissolved groups whose inbox drain completed.
Future<int> hydrateGroupsFromPeers({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required Future<bool> Function(String groupId) canRejoinForExitIntent,
  required Future<void> Function(String groupId) processExitIntent,
  GroupMessageListener? groupMessageListener,
  String? selfPeerId,
  bool multiDeviceSyncEnabled = kMultiDeviceSyncEnabled,
}) async {
  if (!multiDeviceSyncEnabled) {
    return 0;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HYDRATE_FROM_PEERS_BEGIN',
    details: {},
  );

  // 1. Re-subscribe to every known group topic (idempotent; skips keyless +
  //    dissolved groups internally).
  final rejoinResult = await rejoinGroupTopics(
    bridge: bridge,
    groupRepo: groupRepo,
    canRejoinForExitIntent: canRejoinForExitIntent,
    processExitIntent: processExitIntent,
  );

  // 2. Drain each non-dissolved group's relay offline inbox to converge history.
  final groups = await groupRepo.getAllGroups();
  var hydrated = 0;
  for (final group in groups) {
    if (rejoinResult.perGroupOutcomes[group.id] ==
        RejoinOutcome.skippedExitInProgress) {
      continue;
    }
    final currentGroup = await groupRepo.getGroup(group.id);
    if (currentGroup == null ||
        currentGroup.isDissolved ||
        currentGroup.selfRemovedAt != null) {
      continue;
    }
    try {
      await drainGroupOfflineInboxForGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: group.id,
        groupMessageListener: groupMessageListener,
        selfPeerId: selfPeerId,
        drainAllPages: true,
      );
      final refreshedGroup = await groupRepo.getGroup(group.id);
      if (refreshedGroup != null &&
          !refreshedGroup.isDissolved &&
          refreshedGroup.selfRemovedAt == null) {
        hydrated++;
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HYDRATE_FROM_PEERS_GROUP_ERROR',
        details: {
          'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
          'error': e.toString(),
        },
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HYDRATE_FROM_PEERS_COMPLETE',
    details: {'hydrated': hydrated, 'groups': groups.length},
  );
  return hydrated;
}
