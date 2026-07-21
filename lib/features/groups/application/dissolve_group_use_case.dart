import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_system_publish_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

enum DissolveGroupResult {
  success,
  bridgeError,
  notFound,
  unauthorized,
  alreadyDissolved,
  exitWorkPending,
}

class _DissolvePublishAttempt {
  const _DissolvePublishAttempt.blocked(this.preflight, this.group)
    : deniedResult = null,
      publishResult = null,
      publishError = null,
      recipientPeerIds = const <String>[],
      updatedGroup = null;

  const _DissolvePublishAttempt.denied(this.deniedResult, this.group)
    : preflight = GroupDissolvePreflightDisposition.allowed,
      publishResult = null,
      publishError = null,
      recipientPeerIds = const <String>[],
      updatedGroup = null;

  const _DissolvePublishAttempt.published(
    this.publishResult,
    this.updatedGroup,
    this.recipientPeerIds,
  ) : preflight = GroupDissolvePreflightDisposition.allowed,
      deniedResult = null,
      publishError = null,
      group = updatedGroup;

  const _DissolvePublishAttempt.failed(this.publishError, this.group)
    : preflight = GroupDissolvePreflightDisposition.allowed,
      deniedResult = null,
      publishResult = null,
      recipientPeerIds = const <String>[],
      updatedGroup = null;

  final GroupDissolvePreflightDisposition preflight;
  final DissolveGroupResult? deniedResult;
  final GroupModel? group;
  final GroupSystemPublishResult? publishResult;
  final Object? publishError;
  final List<String> recipientPeerIds;
  final GroupModel? updatedGroup;
}

Future<(DissolveGroupResult, GroupModel?)> dissolveGroup({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required GroupDissolvePreflightAuthority preflightAuthority,
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

  final actorMember = await groupRepo.getMember(groupId, actorPeerId);
  if (actorMember?.role != MemberRole.admin) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DISSOLVE_USE_CASE_UNAUTHORIZED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'role': actorMember?.role.toValue() ?? 'missing',
      },
    );
    return (DissolveGroupResult.unauthorized, group);
  }

  final preflight = await preflightAuthority.evaluate(groupId);
  if (preflight != GroupDissolvePreflightDisposition.allowed) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DISSOLVE_USE_CASE_EXIT_WORK_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'reason': preflight.name,
      },
    );
    return (DissolveGroupResult.exitWorkPending, group);
  }

  final eventAt = (dissolvedAt ?? DateTime.now()).toUtc();
  final preTransitionStateHash = await buildGroupTransitionStateHash(
    groupRepo,
    groupId,
  );
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

  final publishAttempt = await runGroupMembershipMutationLocked(
    groupId: groupId,
    action: () async {
      // The early preflight avoids unnecessary signing. This second read is
      // authoritative: the same membership phase also owns the first dissolve
      // effect and the local terminal write, so exit/role work cannot commit
      // between the decision and the dissolved state.
      final finalPreflight = await preflightAuthority.evaluate(groupId);
      if (finalPreflight != GroupDissolvePreflightDisposition.allowed) {
        return _DissolvePublishAttempt.blocked(
          finalPreflight,
          await groupRepo.getGroup(groupId),
        );
      }

      // Signing may yield long enough for another membership mutation to
      // converge completely (and remove its pending role row). Re-read every
      // authority and state input under the membership lock. The signature is
      // valid only for the exact state hash it committed to.
      final freshGroup = await groupRepo.getGroup(groupId);
      if (freshGroup == null) {
        return const _DissolvePublishAttempt.denied(
          DissolveGroupResult.notFound,
          null,
        );
      }
      if (freshGroup.isDissolved) {
        return _DissolvePublishAttempt.denied(
          DissolveGroupResult.alreadyDissolved,
          freshGroup,
        );
      }
      final freshActorMember = await groupRepo.getMember(groupId, actorPeerId);
      if (freshActorMember?.role != MemberRole.admin) {
        return _DissolvePublishAttempt.denied(
          DissolveGroupResult.unauthorized,
          freshGroup,
        );
      }
      final freshStateHash = await buildGroupTransitionStateHash(
        groupRepo,
        groupId,
      );
      if (freshStateHash != preTransitionStateHash) {
        return _DissolvePublishAttempt.denied(
          DissolveGroupResult.bridgeError,
          freshGroup,
        );
      }

      final freshMembers = await groupRepo.getMembers(groupId);
      final recipientPeerIds = freshMembers
          .map((member) => member.peerId.trim())
          .where((peerId) => peerId.isNotEmpty && peerId != actorPeerId)
          .toSet()
          .toList(growable: false);
      final updatedGroup = freshGroup.copyWith(
        isDissolved: true,
        dissolvedAt: eventAt,
        dissolvedBy: actorPeerId,
        lastMembershipEventAt: eventAt,
      );
      late final GroupSystemPublishResult published;
      try {
        published = await publishGroupSystemMessageAssumingMembershipPhaseHeld(
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
      } catch (error) {
        return _DissolvePublishAttempt.failed(error, freshGroup);
      }
      await groupRepo.updateGroup(updatedGroup);
      return _DissolvePublishAttempt.published(
        published,
        updatedGroup,
        recipientPeerIds,
      );
    },
  );

  if (publishAttempt.preflight != GroupDissolvePreflightDisposition.allowed) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DISSOLVE_USE_CASE_EXIT_WORK_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'reason': publishAttempt.preflight.name,
        'phase': 'final_membership_authority',
      },
    );
    return (DissolveGroupResult.exitWorkPending, publishAttempt.group ?? group);
  }

  final deniedResult = publishAttempt.deniedResult;
  if (deniedResult != null) {
    emitFlowEvent(
      layer: 'FL',
      event: deniedResult == DissolveGroupResult.bridgeError
          ? 'GROUP_DISSOLVE_USE_CASE_SIGNED_STATE_CHANGED'
          : 'GROUP_DISSOLVE_USE_CASE_FINAL_AUTHORITY_DENIED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'result': deniedResult.name,
      },
    );
    return (deniedResult, publishAttempt.group);
  }

  final publishError = publishAttempt.publishError;
  if (publishError != null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DISSOLVE_USE_CASE_PUBLISH_ERROR',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'error': publishError.toString(),
      },
    );
    return (DissolveGroupResult.bridgeError, publishAttempt.group);
  }
  final systemPublish = publishAttempt.publishResult!;
  final recipientPeerIds = publishAttempt.recipientPeerIds;
  final updatedGroup = publishAttempt.updatedGroup!;

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
