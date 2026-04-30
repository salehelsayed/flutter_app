import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';

enum RevokePendingGroupInviteResult { revoked, notFound }

Future<RevokePendingGroupInviteResult> revokePendingGroupInvite({
  required PendingGroupInviteRepository pendingInviteRepo,
  required String groupId,
  DateTime? now,
  String? revokedBy,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'PENDING_GROUP_INVITE_REVOKE_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final invite = await pendingInviteRepo.getPendingInvite(groupId);
  if (invite == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_REVOKE_NOT_FOUND',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return RevokePendingGroupInviteResult.notFound;
  }

  final revokedAt = (now ?? DateTime.now()).toUtc();
  await pendingInviteRepo.saveRevokedInvite(
    GroupInviteRevocation(
      inviteId: invite.inviteId,
      groupId: invite.groupId,
      revokedAt: revokedAt,
      expiresAt: revokedAt.add(pendingGroupInviteTtl),
      revokedBy: revokedBy,
    ),
  );
  await pendingInviteRepo.deletePendingInvite(groupId);

  emitFlowEvent(
    layer: 'FL',
    event: 'PENDING_GROUP_INVITE_REVOKE_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );
  return RevokePendingGroupInviteResult.revoked;
}
