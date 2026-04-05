import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
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
  final members = await groupRepo.getMembers(groupId);
  final recipientPeerIds = members
      .map((member) => member.peerId)
      .where((peerId) => peerId.isNotEmpty && peerId != actorPeerId)
      .toList(growable: false);
  final sysText = jsonEncode({
    '__sys': 'group_dissolved',
    'dissolvedAt': eventAt.toIso8601String(),
    'dissolvedBy': actorPeerId,
  });

  try {
    await callGroupPublish(
      bridge,
      groupId: groupId,
      text: sysText,
      senderPeerId: actorPeerId,
      senderPublicKey: actorPublicKey,
      senderPrivateKey: actorPrivateKey,
      senderUsername: actorUsername,
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

  var hadBridgeRecoveryGap = false;
  if (recipientPeerIds.isNotEmpty) {
    final inboxPayload = jsonEncode({
      'groupId': groupId,
      'senderId': actorPeerId,
      'senderUsername': actorUsername,
      'keyEpoch': 0,
      'text': sysText,
      'timestamp': eventAt.toIso8601String(),
    });

    try {
      await callGroupInboxStore(
        bridge,
        groupId,
        inboxPayload,
        recipientPeerIds: recipientPeerIds,
        pushTitle: group.name,
        pushBody: buildGroupDissolvedTimelineText(actorUsername),
      );
    } catch (e) {
      hadBridgeRecoveryGap = true;
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DISSOLVE_USE_CASE_INBOX_STORE_ERROR',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'error': e.toString(),
        },
      );
    }
  }

  final updatedGroup = group.copyWith(
    isDissolved: true,
    dissolvedAt: eventAt,
    dissolvedBy: actorPeerId,
    lastMembershipEventAt: eventAt,
  );
  await groupRepo.updateGroup(updatedGroup);

  await msgRepo.saveMessage(
    buildGroupDissolvedTimelineMessage(
      groupId: groupId,
      senderId: actorPeerId,
      senderUsername: actorUsername,
      eventAt: eventAt,
    ),
  );

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
