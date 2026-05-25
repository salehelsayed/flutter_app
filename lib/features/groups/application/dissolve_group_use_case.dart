import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_system_publish_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

enum DissolveGroupResult {
  success,
  bridgeError,
  notFound,
  unauthorized,
  alreadyDissolved,
}

Future<(DissolveGroupResult, GroupModel?)> dissolveGroup({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String actorPeerId,
  required String actorUsername,
  required String actorPublicKey,
  required String actorPrivateKey,
  String? actorDeviceId,
  String? actorTransportPeerId,
  String? actorKeyPackageId,
  DateTime? dissolvedAt,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DISSOLVE_USE_CASE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DISSOLVE_USE_CASE_NOT_FOUND',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return (DissolveGroupResult.notFound, null);
  }

  if (group.myRole != GroupRole.admin) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DISSOLVE_USE_CASE_UNAUTHORIZED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'role': group.myRole.toValue(),
      },
    );
    return (DissolveGroupResult.unauthorized, group);
  }

  if (group.isDissolved) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DISSOLVE_USE_CASE_ALREADY_DISSOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return (DissolveGroupResult.alreadyDissolved, group);
  }

  final eventAt = (dissolvedAt ?? DateTime.now()).toUtc();
  final preTransitionStateHash = await buildGroupTransitionStateHash(
    groupRepo,
    groupId,
  );
  final members = await groupRepo.getMembers(groupId);
  final recipientPeerIds = members
      .map((member) => member.peerId)
      .where((peerId) => peerId.isNotEmpty && peerId != actorPeerId)
      .toList(growable: false);
  final sourceEventId =
      'group_dissolved:$groupId:$actorPeerId:${eventAt.microsecondsSinceEpoch}';
  final sysPayload = await signGroupSystemTransitionPayload(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    transitionType: 'group_dissolved',
    sourceEventId: sourceEventId,
    eventAt: eventAt,
    actorPeerId: actorPeerId,
    actorUsername: actorUsername,
    actorSigningPublicKey: actorPublicKey,
    actorPrivateKey: actorPrivateKey,
    actorDeviceId: actorDeviceId,
    actorTransportPeerId: actorTransportPeerId,
    actorKeyPackageId: actorKeyPackageId,
    preTransitionStateHash: preTransitionStateHash,
    systemPayload: {
      '__sys': 'group_dissolved',
      'dissolvedAt': eventAt.toIso8601String(),
      'dissolvedBy': actorPeerId,
    },
  );
  final sysText = jsonEncode(sysPayload);
  final timelineMessage = buildGroupDissolvedTimelineMessage(
    groupId: groupId,
    senderId: actorPeerId,
    senderUsername: actorUsername,
    eventAt: eventAt,
  );

  final inboxPayload = jsonEncode({
    'groupId': groupId,
    'senderId': actorPeerId,
    'senderUsername': actorUsername,
    if (actorDeviceId != null && actorDeviceId.isNotEmpty)
      'senderDeviceId': actorDeviceId,
    if (actorTransportPeerId != null && actorTransportPeerId.isNotEmpty)
      'transportPeerId': actorTransportPeerId,
    'text': sysText,
    'timestamp': eventAt.toIso8601String(),
    'messageId': sourceEventId,
  });

  late final GroupSystemPublishResult systemPublish;
  try {
    systemPublish = await publishGroupSystemMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      text: sysText,
      senderPeerId: actorPeerId,
      senderPublicKey: actorPublicKey,
      senderPrivateKey: actorPrivateKey,
      senderUsername: actorUsername,
      senderDeviceId: actorDeviceId,
      senderTransportPeerId: actorTransportPeerId,
      senderKeyPackageId: actorKeyPackageId,
      messageId: sourceEventId,
      replayPlaintext: inboxPayload,
      recipientPeerIds: recipientPeerIds,
      msgRepo: msgRepo,
      timelineMessage: timelineMessage,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DISSOLVE_USE_CASE_PUBLISH_ERROR',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'error': e.toString(),
      },
    );
    return (DissolveGroupResult.bridgeError, null);
  }

  var hadBridgeRecoveryGap =
      recipientPeerIds.isNotEmpty && !systemPublish.inboxStored;
  if (systemPublish.replayStorageError != null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DISSOLVE_USE_CASE_INBOX_STORE_ERROR',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'error': systemPublish.replayStorageError.toString(),
      },
    );
  }

  final updatedGroup = group.copyWith(
    isDissolved: true,
    dissolvedAt: eventAt,
    dissolvedBy: actorPeerId,
    lastMembershipEventAt: eventAt,
  );
  await groupRepo.updateGroup(updatedGroup);

  await msgRepo.saveMessage(systemPublish.timelineMessage ?? timelineMessage);

  try {
    await callGroupLeave(bridge, groupId);
  } catch (e) {
    hadBridgeRecoveryGap = true;
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DISSOLVE_USE_CASE_LEAVE_ERROR',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'error': e.toString(),
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DISSOLVE_USE_CASE_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'recipientCount': recipientPeerIds.length,
      'bridgeRecoveryGap': hadBridgeRecoveryGap,
    },
  );

  return (
    hadBridgeRecoveryGap
        ? DissolveGroupResult.bridgeError
        : DissolveGroupResult.success,
    updatedGroup,
  );
}
