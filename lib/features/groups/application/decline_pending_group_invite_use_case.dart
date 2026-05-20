import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
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

  final effectiveNow = (now ?? DateTime.now()).toUtc();
  await _recordDeclinedInviteTombstone(
    pendingInviteRepo: pendingInviteRepo,
    invite: invite,
    declinedAt: effectiveNow,
  );
  await pendingInviteRepo.deletePendingInvite(groupId);

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

Future<void> _recordDeclinedInviteTombstone({
  required PendingGroupInviteRepository pendingInviteRepo,
  required PendingGroupInvite invite,
  required DateTime declinedAt,
}) async {
  final declinedAtUtc = declinedAt.toUtc();
  final retentionExpiry = declinedAtUtc.add(pendingGroupInviteTtl);
  await pendingInviteRepo.saveConsumedInvite(
    GroupInviteConsumption(
      inviteId: invite.inviteId,
      groupId: invite.groupId,
      consumedAt: declinedAtUtc,
      expiresAt: invite.expiresAt.isAfter(retentionExpiry)
          ? invite.expiresAt
          : retentionExpiry,
    ),
  );
}
