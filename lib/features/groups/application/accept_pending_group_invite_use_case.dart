import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';

enum AcceptPendingGroupInviteResult {
  success,
  notFound,
  expired,
  revoked,
  alreadyUsed,
  repairPending,
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
  ReactionRepository? reactionRepo,
  GroupMessageListener? groupMessageListener,
  String? senderPeerId,
  String? senderPublicKey,
  String? senderPrivateKey,
  String? senderUsername,
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
  final revocation = await pendingInviteRepo.getRevokedInvite(invite.inviteId);
  if (revocation != null && revocation.isActiveAt(effectiveNow)) {
    await pendingInviteRepo.deletePendingInvite(groupId);
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_REVOKED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return (AcceptPendingGroupInviteResult.revoked, null);
  }

  final consumption = await pendingInviteRepo.getConsumedInvite(
    invite.inviteId,
  );
  if (consumption != null && consumption.isActiveAt(effectiveNow)) {
    await pendingInviteRepo.deletePendingInvite(groupId);
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_ALREADY_USED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return (AcceptPendingGroupInviteResult.alreadyUsed, null);
  }

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
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_REPAIR_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return (AcceptPendingGroupInviteResult.repairPending, null);
  }

  final (result, acceptedGroupId) = await materializeAcceptedGroupInvitePayload(
    payload: payload,
    groupRepo: groupRepo,
    bridge: bridge,
    downloadGroupAvatarFn: downloadGroupAvatarFn,
  );

  switch (result) {
    case HandleGroupInviteResult.success:
      await _recordConsumedInvite(
        pendingInviteRepo: pendingInviteRepo,
        invite: invite,
        consumedAt: effectiveNow,
      );
      await pendingInviteRepo.deletePendingInvite(groupId);
      await drainGroupOfflineInboxForGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: acceptedGroupId ?? groupId,
        mediaAttachmentRepo: mediaAttachmentRepo,
        reactionRepo: reactionRepo,
        groupMessageListener: groupMessageListener,
      );
      final acceptedId = acceptedGroupId ?? groupId;
      final group = await groupRepo.getGroup(acceptedId);
      await _publishAcceptedJoinTimelineIfPossible(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupId: acceptedId,
        senderPeerId: senderPeerId,
        senderPublicKey: senderPublicKey,
        senderPrivateKey: senderPrivateKey,
        senderUsername: senderUsername,
      );
      return (AcceptPendingGroupInviteResult.success, group);
    case HandleGroupInviteResult.bridgeError:
      await _recordConsumedInvite(
        pendingInviteRepo: pendingInviteRepo,
        invite: invite,
        consumedAt: effectiveNow,
      );
      await pendingInviteRepo.deletePendingInvite(groupId);
      final acceptedId = acceptedGroupId ?? groupId;
      final group = await groupRepo.getGroup(acceptedId);
      await _publishAcceptedJoinTimelineIfPossible(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupId: acceptedId,
        senderPeerId: senderPeerId,
        senderPublicKey: senderPublicKey,
        senderPrivateKey: senderPrivateKey,
        senderUsername: senderUsername,
      );
      return (AcceptPendingGroupInviteResult.bridgeError, group);
    case HandleGroupInviteResult.duplicateGroup:
      await pendingInviteRepo.deletePendingInvite(groupId);
      return (AcceptPendingGroupInviteResult.duplicateGroup, null);
    case HandleGroupInviteResult.invalidPayload:
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_GROUP_INVITE_ACCEPT_REPAIR_PENDING',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return (AcceptPendingGroupInviteResult.repairPending, null);
    case HandleGroupInviteResult.unknownSender:
    case HandleGroupInviteResult.decryptionFailed:
      await pendingInviteRepo.deletePendingInvite(groupId);
      return (AcceptPendingGroupInviteResult.invalidPayload, null);
  }
}

Future<void> _recordConsumedInvite({
  required PendingGroupInviteRepository pendingInviteRepo,
  required PendingGroupInvite invite,
  required DateTime consumedAt,
}) async {
  final consumedAtUtc = consumedAt.toUtc();
  final retentionExpiry = consumedAtUtc.add(pendingGroupInviteTtl);
  await pendingInviteRepo.saveConsumedInvite(
    GroupInviteConsumption(
      inviteId: invite.inviteId,
      groupId: invite.groupId,
      consumedAt: consumedAtUtc,
      expiresAt: invite.expiresAt.isAfter(retentionExpiry)
          ? invite.expiresAt
          : retentionExpiry,
    ),
  );
}

Future<void> _publishAcceptedJoinTimelineIfPossible({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required Bridge bridge,
  required String groupId,
  String? senderPeerId,
  String? senderPublicKey,
  String? senderPrivateKey,
  String? senderUsername,
}) async {
  if (senderPeerId == null ||
      senderPeerId.isEmpty ||
      senderPublicKey == null ||
      senderPrivateKey == null) {
    return;
  }

  final joinedAt = DateTime.now().toUtc();
  final timelineMessage = buildMemberJoinedTimelineMessage(
    groupId: groupId,
    joinedPeerId: senderPeerId,
    joinedUsername: senderUsername,
    eventAt: joinedAt,
  );
  await msgRepo.saveMessage(timelineMessage);

  final sysText = jsonEncode({
    '__sys': 'member_joined',
    'member': {
      'peerId': senderPeerId,
      if (senderUsername != null) 'username': senderUsername,
    },
  });

  final recipientPeerIds = (await groupRepo.getMembers(groupId))
      .map((member) => member.peerId)
      .where((peerId) => peerId != senderPeerId)
      .toList(growable: false);

  try {
    await callGroupPublish(
      bridge,
      groupId: groupId,
      text: sysText,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      senderUsername: senderUsername ?? '',
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_JOIN_EVENT_WARNING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'stage': 'publish',
        'error': e.toString(),
      },
    );
  }

  if (recipientPeerIds.isEmpty) {
    return;
  }

  final inboxPayload = jsonEncode({
    'groupId': groupId,
    'senderId': senderPeerId,
    'senderUsername': senderUsername ?? '',
    'text': sysText,
    'timestamp': joinedAt.toIso8601String(),
  });

  try {
    await storeGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: inboxPayload,
      messageId: timelineMessage.id,
      recipientPeerIds: recipientPeerIds,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_JOIN_EVENT_WARNING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'stage': 'replay_store',
        'error': e.toString(),
      },
    );
  }
}
