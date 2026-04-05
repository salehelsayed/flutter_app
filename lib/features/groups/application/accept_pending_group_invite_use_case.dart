import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';

enum AcceptPendingGroupInviteResult {
  success,
  notFound,
  expired,
  invalidPayload,
  duplicateGroup,
  bridgeError,
}

Future<(AcceptPendingGroupInviteResult, GroupModel?)> acceptPendingGroupInvite({
  required PendingGroupInviteRepository pendingInviteRepo,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required Bridge bridge,
  required String groupId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  GroupMessageListener? groupMessageListener,
  DateTime? now,
  DownloadGroupAvatarFn? downloadGroupAvatarFn,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'PENDING_GROUP_INVITE_ACCEPT_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final invite = await pendingInviteRepo.getPendingInvite(groupId);
  if (invite == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_NOT_FOUND',
      details: {'groupId': groupId},
    );
    return (AcceptPendingGroupInviteResult.notFound, null);
  }

  final effectiveNow = (now ?? DateTime.now()).toUtc();
  if (invite.isExpiredAt(effectiveNow)) {
    await pendingInviteRepo.deletePendingInvite(groupId);
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_EXPIRED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return (AcceptPendingGroupInviteResult.expired, null);
  }

  final payload = invite.toPayload();
  if (payload == null) {
    await pendingInviteRepo.deletePendingInvite(groupId);
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_INVALID_PAYLOAD',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return (AcceptPendingGroupInviteResult.invalidPayload, null);
  }

  final (result, acceptedGroupId) = await materializeAcceptedGroupInvitePayload(
    payload: payload,
    groupRepo: groupRepo,
    bridge: bridge,
    downloadGroupAvatarFn: downloadGroupAvatarFn,
  );

  switch (result) {
    case HandleGroupInviteResult.success:
      await pendingInviteRepo.deletePendingInvite(groupId);
      await drainGroupOfflineInboxForGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: acceptedGroupId ?? groupId,
        mediaAttachmentRepo: mediaAttachmentRepo,
        groupMessageListener: groupMessageListener,
      );
      final group = await groupRepo.getGroup(acceptedGroupId ?? groupId);
      return (AcceptPendingGroupInviteResult.success, group);
    case HandleGroupInviteResult.bridgeError:
      await pendingInviteRepo.deletePendingInvite(groupId);
      final group = await groupRepo.getGroup(acceptedGroupId ?? groupId);
      return (AcceptPendingGroupInviteResult.bridgeError, group);
    case HandleGroupInviteResult.duplicateGroup:
      await pendingInviteRepo.deletePendingInvite(groupId);
      return (AcceptPendingGroupInviteResult.duplicateGroup, null);
    case HandleGroupInviteResult.invalidPayload:
      await pendingInviteRepo.deletePendingInvite(groupId);
      return (AcceptPendingGroupInviteResult.invalidPayload, null);
    case HandleGroupInviteResult.unknownSender:
    case HandleGroupInviteResult.decryptionFailed:
      await pendingInviteRepo.deletePendingInvite(groupId);
      return (AcceptPendingGroupInviteResult.invalidPayload, null);
  }
}
