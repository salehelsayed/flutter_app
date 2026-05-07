import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/record_group_invite_delivery_attempts.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

enum ResendGroupInviteReason {
  delivered,
  memberNotFound,
  groupNotFound,
  missingGroupKey,
  sendFailed,
}

class ResendGroupInviteResult {
  final GroupInviteDeliveryStatus status;
  final ResendGroupInviteReason reason;

  const ResendGroupInviteResult({required this.status, required this.reason});

  bool get wasQueuedOrSent =>
      status == GroupInviteDeliveryStatus.sent ||
      status == GroupInviteDeliveryStatus.queued;
}

Future<ResendGroupInviteResult> resendGroupInvite({
  required P2PService p2pService,
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupInviteDeliveryAttemptRepository inviteDeliveryAttemptRepo,
  required IdentityModel identity,
  required String groupId,
  required String memberPeerId,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_RESEND_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'peerId': memberPeerId.length > 10
          ? memberPeerId.substring(0, 10)
          : memberPeerId,
    },
  );

  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    return const ResendGroupInviteResult(
      status: GroupInviteDeliveryStatus.unknown,
      reason: ResendGroupInviteReason.groupNotFound,
    );
  }

  final member = await groupRepo.getMember(groupId, memberPeerId);
  if (member == null) {
    return const ResendGroupInviteResult(
      status: GroupInviteDeliveryStatus.unknown,
      reason: ResendGroupInviteReason.memberNotFound,
    );
  }

  final keyInfo = await groupRepo.getLatestKey(groupId);
  if (keyInfo == null) {
    final now = DateTime.now().toUtc();
    await inviteDeliveryAttemptRepo.saveAttempt(
      GroupInviteDeliveryAttempt(
        groupId: groupId,
        peerId: member.peerId,
        username: member.username,
        status: GroupInviteDeliveryStatus.needsResend,
        attemptedAt: now,
        updatedAt: now,
        lastError: 'group_key_missing',
      ),
    );
    return const ResendGroupInviteResult(
      status: GroupInviteDeliveryStatus.needsResend,
      reason: ResendGroupInviteReason.missingGroupKey,
    );
  }

  final members = await groupRepo.getMembers(groupId);
  final groupConfig = buildGroupConfigPayload(group, members);
  final sendResult = await sendGroupInvite(
    p2pService: p2pService,
    bridge: bridge,
    groupRepo: groupRepo,
    recipientPeerId: member.peerId,
    recipientMlKemPublicKey: member.mlKemPublicKey,
    senderPeerId: identity.peerId,
    senderPublicKey: identity.publicKey,
    senderPrivateKey: identity.privateKey,
    senderUsername: identity.username ?? '',
    groupId: groupId,
    groupKey: keyInfo.encryptedKey,
    keyEpoch: keyInfo.keyGeneration,
    groupConfig: groupConfig,
  );

  await recordGroupInviteDeliveryBatch(
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
    groupId: groupId,
    attempts: [
      GroupInviteAttempt(
        peerId: member.peerId,
        username: member.username,
        result: sendResult,
      ),
    ],
  );

  final status = groupInviteDeliveryStatusForSendResult(sendResult);
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_RESEND_DONE',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'peerId': memberPeerId.length > 10
          ? memberPeerId.substring(0, 10)
          : memberPeerId,
      'status': status.toValue(),
    },
  );
  return ResendGroupInviteResult(
    status: status,
    reason:
        status == GroupInviteDeliveryStatus.sent ||
            status == GroupInviteDeliveryStatus.queued
        ? ResendGroupInviteReason.delivered
        : ResendGroupInviteReason.sendFailed,
  );
}
