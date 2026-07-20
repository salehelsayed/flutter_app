import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const strictDissolvedLocalDeleteRequiredMessage =
    'Local-only group deletion requires a dissolved group.';

/// Leaves a group and then deletes its local message history.
Future<void> deleteGroupAndMessages({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository groupMessageRepo,
  required String groupId,
  bool deleteLocallyIfDissolved = false,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'DELETE_GROUP_AND_MESSAGES_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    if (deleteLocallyIfDissolved) {
      final observedGroup = await groupRepo.getGroup(groupId);
      if (observedGroup?.isDissolved != true) {
        throw StateError(strictDissolvedLocalDeleteRequiredMessage);
      }

      // The swipe/dialog can outlive its row snapshot. Re-read at the actual
      // destructive boundary and fail closed if the row disappeared or became
      // active again.
      final commitGroup = await groupRepo.getGroup(groupId);
      if (commitGroup == null || !commitGroup.isDissolved) {
        throw StateError(strictDissolvedLocalDeleteRequiredMessage);
      }

      final deletedCount = await groupMessageRepo.deleteMessagesForGroup(
        groupId,
      );
      await groupRepo.removeAllMembers(groupId);
      await groupRepo.removeAllKeys(groupId);
      if (groupRepo is GroupKeyRotationDraftRepository) {
        await (groupRepo as GroupKeyRotationDraftRepository)
            .clearPendingKeyRotations(groupId);
      }

      // Rejoin state is not guaranteed to cascade from deleteGroup. Clear it
      // while the dissolved row still exists so a failure remains retryable.
      await groupRepo.clearGroupRejoinState(groupId);
      await groupRepo.deleteGroup(groupId);
      try {
        // The queue has no group FK. It must be cleared only after the local
        // group deletion commits so a failed delete preserves recovery work.
        await discardGroupPendingBroadcasts(groupId);
      } catch (error, stackTrace) {
        // Re-create only the already revalidated dissolved row as a durable
        // retry marker. Deleted history/members/keys stay deleted; the next
        // strict call can idempotently finish queue cleanup without weakening
        // the missing-group refusal for unrelated calls.
        if (await groupRepo.getGroup(groupId) == null) {
          await groupRepo.saveGroup(commitGroup);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }

      emitFlowEvent(
        layer: 'UC',
        event: 'DELETE_GROUP_MESSAGES_PURGED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'deletedMessages': deletedCount,
          'cleanupMode': 'local_only',
        },
      );

      emitFlowEvent(
        layer: 'UC',
        event: 'DELETE_GROUP_AND_MESSAGES_SUCCESS',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'cleanupMode': 'local_only',
        },
      );
      return;
    }

    await leaveGroup(bridge: bridge, groupRepo: groupRepo, groupId: groupId);
    final deletedCount = await groupMessageRepo.deleteMessagesForGroup(groupId);

    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_GROUP_MESSAGES_PURGED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'deletedMessages': deletedCount,
        'cleanupMode': 'leave',
      },
    );

    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_GROUP_AND_MESSAGES_SUCCESS',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'cleanupMode': 'leave',
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_GROUP_AND_MESSAGES_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
