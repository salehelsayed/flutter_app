import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_invite_auth.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package_tombstone.dart';
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
  wrongIdentity,
  repairPending,
  invalidPayload,
  duplicateGroup,
  bridgeError,
}

Future<(AcceptPendingGroupInviteResult, GroupModel?)> acceptPendingGroupInvite({
  required PendingGroupInviteRepository pendingInviteRepo,
  required GroupRepository groupRepo,
  required ContactRepository contactRepo,
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
  String? ownDeviceId,
  String? ownTransportPeerId,
  String? ownMlKemPublicKey,
  String? ownKeyPackageId,
  String? ownKeyPackagePublicMaterial,
  DateTime? now,
  DownloadGroupAvatarFn? downloadGroupAvatarFn,
  bool drainAcceptedInboxAllPages = false,
  int acceptedInboxPageSize = 50,
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

  final parsedPayload = GroupInvitePayload.parseJsonDetailed(
    invite.payloadJson,
  );
  if (!parsedPayload.isSuccess) {
    if (parsedPayload.isSecurityFailure) {
      await pendingInviteRepo.deletePendingInvite(groupId);
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_GROUP_INVITE_ACCEPT_INVALID_SIGNATURE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return (AcceptPendingGroupInviteResult.invalidPayload, null);
    }
    if (parsedPayload.failure ==
        GroupInvitePayloadParseFailure.invalidWelcomeKeyPackage) {
      await pendingInviteRepo.deletePendingInvite(groupId);
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_GROUP_INVITE_ACCEPT_INVALID_WELCOME_PACKAGE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return (AcceptPendingGroupInviteResult.invalidPayload, null);
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_REPAIR_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return (AcceptPendingGroupInviteResult.repairPending, null);
  }
  final payload = parsedPayload.payload!;
  final currentTimeFailure = payload.currentTimeValidationFailure(effectiveNow);
  if (currentTimeFailure == GroupInvitePayloadParseFailure.expired) {
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
  if (currentTimeFailure ==
      GroupInvitePayloadParseFailure.invalidWelcomeKeyPackage) {
    await pendingInviteRepo.deletePendingInvite(groupId);
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_INVALID_WELCOME_PACKAGE',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return (AcceptPendingGroupInviteResult.invalidPayload, null);
  }
  if (currentTimeFailure == GroupInvitePayloadParseFailure.invalidSignature ||
      currentTimeFailure == GroupInvitePayloadParseFailure.missingSignature ||
      currentTimeFailure ==
          GroupInvitePayloadParseFailure.staleMembershipFreshness) {
    await pendingInviteRepo.deletePendingInvite(groupId);
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_INVALID_SIGNATURE',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return (AcceptPendingGroupInviteResult.invalidPayload, null);
  }
  if (!payload.isInvitePolicyValid()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_REPAIR_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return (AcceptPendingGroupInviteResult.repairPending, null);
  }

  final expectedRecipientPeerId = senderPeerId?.trim();
  if (expectedRecipientPeerId != null && expectedRecipientPeerId.isNotEmpty) {
    if (!payload.isBoundToRecipientDevice(
      ownPeerId: expectedRecipientPeerId,
      ownDeviceId: ownDeviceId,
      ownTransportPeerId: ownTransportPeerId,
      ownMlKemPublicKey: ownMlKemPublicKey,
      ownKeyPackageId: ownKeyPackageId,
      ownKeyPackagePublicMaterial: ownKeyPackagePublicMaterial,
    )) {
      await pendingInviteRepo.deletePendingInvite(groupId);
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_GROUP_INVITE_ACCEPT_RECIPIENT_MISMATCH',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return (AcceptPendingGroupInviteResult.wrongIdentity, null);
    }
  }

  if (await _isStaleAgainstLocalGroupState(
    groupRepo: groupRepo,
    payload: payload,
    ownPeerId: expectedRecipientPeerId,
  )) {
    await pendingInviteRepo.deletePendingInvite(groupId);
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_STALE_REJECTED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'keyEpoch': payload.keyEpoch,
      },
    );
    return (AcceptPendingGroupInviteResult.invalidPayload, null);
  }

  final isSingleUse =
      payload.invitePolicy.reusePolicy == GroupInviteReusePolicy.singleUse;
  if (isSingleUse) {
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
  }

  if (await _hasActiveWelcomeKeyPackageTombstone(
    pendingInviteRepo: pendingInviteRepo,
    payload: payload,
    now: effectiveNow,
  )) {
    await pendingInviteRepo.deletePendingInvite(groupId);
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_PACKAGE_ALREADY_USED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return (AcceptPendingGroupInviteResult.alreadyUsed, null);
  }

  final authResult = await verifyGroupInviteAttestation(
    payload: payload,
    contactRepo: contactRepo,
    bridge: bridge,
    validationTime: effectiveNow,
    allowMemberSnapshotBootstrap: true,
  );
  if (authResult != GroupInviteAuthResult.authorized) {
    await pendingInviteRepo.deletePendingInvite(groupId);
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_INVALID_SIGNATURE',
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
      final acceptedId = acceptedGroupId ?? groupId;
      final inboxDrained = await _drainAcceptedGroupInboxBestEffort(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: acceptedId,
        mediaAttachmentRepo: mediaAttachmentRepo,
        reactionRepo: reactionRepo,
        groupMessageListener: groupMessageListener,
        selfPeerId: senderPeerId,
        drainAllPages: drainAcceptedInboxAllPages,
        pageSize: acceptedInboxPageSize,
      );
      final group = await groupRepo.getGroup(acceptedId);
      await _publishAcceptedJoinTimelineBestEffort(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupId: acceptedId,
        senderPeerId: senderPeerId,
        senderPublicKey: senderPublicKey,
        senderPrivateKey: senderPrivateKey,
        senderUsername: senderUsername,
        senderDeviceId: ownDeviceId,
        senderTransportPeerId: ownTransportPeerId,
        senderKeyPackageId: ownKeyPackageId,
      );
      if (!inboxDrained) {
        return (AcceptPendingGroupInviteResult.bridgeError, group);
      }
      await _commitAcceptedPendingInvite(
        pendingInviteRepo: pendingInviteRepo,
        invite: invite,
        payload: payload,
        consumedAt: effectiveNow,
        isSingleUse: isSingleUse,
      );
      return (AcceptPendingGroupInviteResult.success, group);
    case HandleGroupInviteResult.bridgeError:
      final acceptedId = acceptedGroupId ?? groupId;
      final group = await groupRepo.getGroup(acceptedId);
      await _publishAcceptedJoinTimelineBestEffort(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupId: acceptedId,
        senderPeerId: senderPeerId,
        senderPublicKey: senderPublicKey,
        senderPrivateKey: senderPrivateKey,
        senderUsername: senderUsername,
        senderDeviceId: ownDeviceId,
        senderTransportPeerId: ownTransportPeerId,
        senderKeyPackageId: ownKeyPackageId,
      );
      return (AcceptPendingGroupInviteResult.bridgeError, group);
    case HandleGroupInviteResult.duplicateGroup:
      return _retryAcceptedMaterializedInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        invite: invite,
        payload: payload,
        consumedAt: effectiveNow,
        isSingleUse: isSingleUse,
        mediaAttachmentRepo: mediaAttachmentRepo,
        reactionRepo: reactionRepo,
        groupMessageListener: groupMessageListener,
        senderPeerId: senderPeerId,
        drainAcceptedInboxAllPages: drainAcceptedInboxAllPages,
        acceptedInboxPageSize: acceptedInboxPageSize,
      );
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

Future<(AcceptPendingGroupInviteResult, GroupModel?)>
_retryAcceptedMaterializedInvite({
  required PendingGroupInviteRepository pendingInviteRepo,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required Bridge bridge,
  required PendingGroupInvite invite,
  required GroupInvitePayload payload,
  required DateTime consumedAt,
  required bool isSingleUse,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  GroupMessageListener? groupMessageListener,
  String? senderPeerId,
  required bool drainAcceptedInboxAllPages,
  required int acceptedInboxPageSize,
}) async {
  final group = await _compatibleAcceptedRetryGroup(
    groupRepo: groupRepo,
    payload: payload,
  );
  if (group == null) {
    await pendingInviteRepo.deletePendingInvite(invite.groupId);
    return (AcceptPendingGroupInviteResult.duplicateGroup, null);
  }

  try {
    await callGroupJoinWithConfig(
      bridge,
      groupId: payload.groupId,
      groupConfig: payload.groupConfig,
      groupKey: payload.groupKey,
      keyEpoch: payload.keyEpoch,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_RETRY_JOIN_WARNING',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
        'error': e.toString(),
      },
    );
    return (AcceptPendingGroupInviteResult.bridgeError, group);
  }

  final inboxDrained = await _drainAcceptedGroupInboxBestEffort(
    bridge: bridge,
    groupRepo: groupRepo,
    msgRepo: msgRepo,
    groupId: payload.groupId,
    mediaAttachmentRepo: mediaAttachmentRepo,
    reactionRepo: reactionRepo,
    groupMessageListener: groupMessageListener,
    selfPeerId: senderPeerId,
    drainAllPages: drainAcceptedInboxAllPages,
    pageSize: acceptedInboxPageSize,
  );
  if (!inboxDrained) {
    return (AcceptPendingGroupInviteResult.bridgeError, group);
  }

  await _commitAcceptedPendingInvite(
    pendingInviteRepo: pendingInviteRepo,
    invite: invite,
    payload: payload,
    consumedAt: consumedAt,
    isSingleUse: isSingleUse,
  );
  return (AcceptPendingGroupInviteResult.success, group);
}

Future<GroupModel?> _compatibleAcceptedRetryGroup({
  required GroupRepository groupRepo,
  required GroupInvitePayload payload,
}) async {
  final group = await groupRepo.getGroup(payload.groupId);
  if (group == null) {
    return null;
  }
  final latestKey = await groupRepo.getLatestKey(payload.groupId);
  if (latestKey == null ||
      latestKey.keyGeneration != payload.keyEpoch ||
      latestKey.encryptedKey != payload.groupKey) {
    return null;
  }
  return group;
}

Future<bool> _hasActiveWelcomeKeyPackageTombstone({
  required PendingGroupInviteRepository pendingInviteRepo,
  required GroupInvitePayload payload,
  required DateTime now,
}) async {
  final welcome = payload.welcomeKeyPackage;
  if (welcome == null) {
    return false;
  }
  final tombstone = await pendingInviteRepo.getWelcomeKeyPackageTombstone(
    packageId: welcome.packageId,
    recipientDeviceId: welcome.recipientDeviceId,
    groupId: welcome.groupId,
  );
  return tombstone != null && tombstone.isActiveAt(now);
}

Future<bool> _isStaleAgainstLocalGroupState({
  required GroupRepository groupRepo,
  required GroupInvitePayload payload,
  required String? ownPeerId,
}) async {
  final localGroup = await groupRepo.getGroup(payload.groupId);
  if (localGroup == null) {
    return false;
  }

  final latestKey = await groupRepo.getLatestKey(payload.groupId);
  if (latestKey != null && payload.keyEpoch < latestKey.keyGeneration) {
    return true;
  }

  final recipientPeerId = ownPeerId?.trim().isNotEmpty == true
      ? ownPeerId!.trim()
      : payload.recipientPeerId?.trim();
  if (recipientPeerId == null || recipientPeerId.isEmpty) {
    return false;
  }

  final localMember = await groupRepo.getMember(
    payload.groupId,
    recipientPeerId,
  );
  if (localMember != null) {
    return false;
  }

  final lastMembershipEventAt = localGroup.lastMembershipEventAt?.toUtc();
  if (lastMembershipEventAt == null) {
    return false;
  }
  final inviteFreshnessAt =
      payload.membershipFreshnessProof?.issuedAt.toUtc() ??
      DateTime.tryParse(payload.timestamp)?.toUtc();
  return inviteFreshnessAt == null ||
      !inviteFreshnessAt.isAfter(lastMembershipEventAt);
}

Future<void> _commitAcceptedPendingInvite({
  required PendingGroupInviteRepository pendingInviteRepo,
  required PendingGroupInvite invite,
  required GroupInvitePayload payload,
  required DateTime consumedAt,
  required bool isSingleUse,
}) async {
  if (isSingleUse) {
    await _recordConsumedInvite(
      pendingInviteRepo: pendingInviteRepo,
      invite: invite,
      consumedAt: consumedAt,
    );
  }
  await _recordWelcomeKeyPackageTombstone(
    pendingInviteRepo: pendingInviteRepo,
    payload: payload,
    consumedAt: consumedAt,
  );
  await pendingInviteRepo.deletePendingInvite(invite.groupId);
}

Future<void> _recordWelcomeKeyPackageTombstone({
  required PendingGroupInviteRepository pendingInviteRepo,
  required GroupInvitePayload payload,
  required DateTime consumedAt,
}) async {
  final welcome = payload.welcomeKeyPackage;
  if (welcome == null) {
    return;
  }
  final consumedAtUtc = consumedAt.toUtc();
  final retentionExpiry = consumedAtUtc.add(pendingGroupInviteTtl);
  final expiresAt = welcome.expiresAt.isAfter(retentionExpiry)
      ? welcome.expiresAt
      : retentionExpiry;
  await pendingInviteRepo.saveWelcomeKeyPackageTombstone(
    GroupWelcomeKeyPackageTombstone(
      packageId: welcome.packageId,
      recipientDeviceId: welcome.recipientDeviceId,
      groupId: welcome.groupId,
      inviteId: payload.id,
      publicMaterialHash: welcome.publicMaterialHash,
      consumedAt: consumedAtUtc,
      expiresAt: expiresAt,
    ),
  );
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

Future<bool> _drainAcceptedGroupInboxBestEffort({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  GroupMessageListener? groupMessageListener,
  String? selfPeerId,
  required bool drainAllPages,
  required int pageSize,
}) async {
  try {
    await drainGroupOfflineInboxForGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: groupId,
      mediaAttachmentRepo: mediaAttachmentRepo,
      reactionRepo: reactionRepo,
      groupMessageListener: groupMessageListener,
      selfPeerId: selfPeerId,
      drainAllPages: drainAllPages,
      pageSize: pageSize,
    );
    return true;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_INBOX_DRAIN_WARNING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'error': e.toString(),
      },
    );
    return false;
  }
}

Future<void> _publishAcceptedJoinTimelineBestEffort({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required Bridge bridge,
  required String groupId,
  String? senderPeerId,
  String? senderPublicKey,
  String? senderPrivateKey,
  String? senderUsername,
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderKeyPackageId,
}) async {
  try {
    await _publishAcceptedJoinTimelineIfPossible(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      bridge: bridge,
      groupId: groupId,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      senderUsername: senderUsername,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
      senderKeyPackageId: senderKeyPackageId,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_ACCEPT_JOIN_EVENT_WARNING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'stage': 'timeline',
        'error': e.toString(),
      },
    );
  }
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
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderKeyPackageId,
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
      if (senderUsername != null && senderUsername.isNotEmpty)
        'username': senderUsername,
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
    'messageId': timelineMessage.id,
  });

  try {
    await storeGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: inboxPayload,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      messageId: timelineMessage.id,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
      senderKeyPackageId: senderKeyPackageId,
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
