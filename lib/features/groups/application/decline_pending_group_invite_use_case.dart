import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';

enum DeclinePendingGroupInviteResult { success, notFound, expired }

Future<DeclinePendingGroupInviteResult> declinePendingGroupInvite({
  required PendingGroupInviteRepository pendingInviteRepo,
  required String groupId,
  DateTime? now,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'PENDING_GROUP_INVITE_DECLINE_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final invite = await pendingInviteRepo.getPendingInvite(groupId);
  if (invite == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_DECLINE_NOT_FOUND',
      details: {'groupId': groupId},
    );
    return DeclinePendingGroupInviteResult.notFound;
  }

  await pendingInviteRepo.deletePendingInvite(groupId);

  final effectiveNow = (now ?? DateTime.now()).toUtc();
  final result = invite.isExpiredAt(effectiveNow)
      ? DeclinePendingGroupInviteResult.expired
      : DeclinePendingGroupInviteResult.success;
  emitFlowEvent(
    layer: 'FL',
    event: result == DeclinePendingGroupInviteResult.expired
        ? 'PENDING_GROUP_INVITE_DECLINE_EXPIRED'
        : 'PENDING_GROUP_INVITE_DECLINE_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );
  return result;
}
