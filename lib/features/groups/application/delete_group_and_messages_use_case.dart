import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const strictDissolvedLocalDeleteRequiredMessage =
    'Local-only group deletion requires a dissolved group.';

/// Typed refusal for a stale dissolved-shell presentation snapshot.
///
/// This remains a [StateError] for compatibility with existing callers, but
/// gives Plan 266's diagnostic decorator a structural way to distinguish an
/// expected state race from an invoked cleanup failure. No exception text is
/// inspected.
class DissolvedGroupDeleteStateChangedException extends StateError {
  DissolvedGroupDeleteStateChangedException()
    : super(strictDissolvedLocalDeleteRequiredMessage);
}

/// Deletes the local state for a twice-revalidated dissolved group.
Future<void> deleteGroupAndMessages({
  required GroupRepository groupRepo,
  required GroupMessageRepository groupMessageRepo,
  required String groupId,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'DELETE_GROUP_AND_MESSAGES_START',
    details: const {'phase': 'local_delete', 'severity': 'info'},
  );

  try {
    final observedGroup = await groupRepo.getGroup(groupId);
    if (observedGroup?.isDissolved != true) {
      throw DissolvedGroupDeleteStateChangedException();
    }

    // The swipe/dialog can outlive its row snapshot. Re-read at the actual
    // destructive boundary and fail closed if the row disappeared or became
    // active again.
    final commitGroup = await groupRepo.getGroup(groupId);
    if (commitGroup == null || !commitGroup.isDissolved) {
      throw DissolvedGroupDeleteStateChangedException();
    }

    await groupMessageRepo.deleteMessagesForGroup(groupId);
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
      details: const {'phase': 'local_delete', 'severity': 'info'},
    );

    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_GROUP_AND_MESSAGES_SUCCESS',
      details: const {'phase': 'local_delete', 'severity': 'info'},
    );
  } catch (e) {
    final stateChanged = e is DissolvedGroupDeleteStateChangedException;
    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_GROUP_AND_MESSAGES_ERROR',
      details: {
        if (!stateChanged) 'code': 'EX10',
        'phase': 'local_delete',
        'severity': stateChanged ? 'warning' : 'failure',
      },
    );
    rethrow;
  }
}
