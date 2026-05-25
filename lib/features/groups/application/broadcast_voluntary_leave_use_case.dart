import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

enum VoluntaryLeaveBroadcastSkipReason { lastAdmin, memberNotFound }

class VoluntaryLeaveBroadcastResult {
  final bool didBroadcast;
  final List<String> remainingPeerIds;
  final GroupKeyInfo? rotatedKey;
  final VoluntaryLeaveBroadcastSkipReason? skipReason;

  const VoluntaryLeaveBroadcastResult({
    required this.didBroadcast,
    required this.remainingPeerIds,
    this.rotatedKey,
    this.skipReason,
  });

  static const skipped = VoluntaryLeaveBroadcastResult(
    didBroadcast: false,
    remainingPeerIds: <String>[],
  );

  static const skippedLastAdmin = VoluntaryLeaveBroadcastResult(
    didBroadcast: false,
    remainingPeerIds: <String>[],
    skipReason: VoluntaryLeaveBroadcastSkipReason.lastAdmin,
  );

  static const skippedMemberNotFound = VoluntaryLeaveBroadcastResult(
    didBroadcast: false,
    remainingPeerIds: <String>[],
    skipReason: VoluntaryLeaveBroadcastSkipReason.memberNotFound,
  );
}

const voluntaryLeaveRotationFailedMessage =
    'Failed to rotate group key before leaving';

/// Broadcasts the local member's voluntary leave and rotates future group
/// traffic away from the departing member before local cleanup deletes state.
Future<VoluntaryLeaveBroadcastResult> broadcastVoluntaryLeaveAndRotateKey({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupModel group,
  required IdentityRepository identityRepo,
  GroupMessageRepository? msgRepo,
  Future<bool> Function(String peerId, String message)? sendP2PMessage,
  Future<bool> Function(String peerId, String message)? storeP2PMessageInInbox,
}) async {
  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    throw StateError('No identity found');
  }

  final members = await groupRepo.getMembers(group.id);
  final adminCount = members
      .where((member) => member.role == MemberRole.admin)
      .length;
  if (group.myRole == GroupRole.admin && adminCount <= 1) {
    return VoluntaryLeaveBroadcastResult.skippedLastAdmin;
  }

  final selfMember = members.where(
    (member) => member.peerId == identity.peerId,
  );
  if (selfMember.isEmpty) {
    return VoluntaryLeaveBroadcastResult.skippedMemberNotFound;
  }

  final remainingMembers = members
      .where((member) => member.peerId != identity.peerId)
      .toList(growable: false);
  final remainingPeerIds = remainingMembers
      .map((member) => member.peerId)
      .toList(growable: false);
  final preTransitionStateHash = await buildGroupTransitionStateHash(
    groupRepo,
    group.id,
  );
  final leftAt = DateTime.now().toUtc();
  final senderUsername = identity.username;
  final sourceEventId =
      'member_removed:${group.id}:${identity.peerId}:${leftAt.microsecondsSinceEpoch}';
  final sysPayload = await signGroupSystemTransitionPayload(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: group.id,
    transitionType: 'member_removed',
    sourceEventId: sourceEventId,
    eventAt: leftAt,
    actorPeerId: identity.peerId,
    actorUsername: senderUsername,
    actorSigningPublicKey: identity.publicKey,
    actorPrivateKey: identity.privateKey,
    preTransitionStateHash: preTransitionStateHash,
    systemPayload: {
      '__sys': 'member_removed',
      'member': {'peerId': identity.peerId, 'username': senderUsername},
      'removedAt': leftAt.toIso8601String(),
      'groupConfig': buildGroupConfigPayload(group, remainingMembers),
    },
  );
  final sysText = jsonEncode(sysPayload);

  final leaveTimelineMessage = buildMemberRemovedTimelineMessage(
    groupId: group.id,
    removedPeerId: identity.peerId,
    removedUsername: senderUsername,
    senderId: identity.peerId,
    senderUsername: senderUsername,
    eventAt: leftAt,
  );
  if (msgRepo != null) {
    await msgRepo.saveMessage(leaveTimelineMessage);
  }

  await callGroupPublish(
    bridge,
    groupId: group.id,
    text: sysText,
    senderPeerId: identity.peerId,
    senderPublicKey: identity.publicKey,
    senderPrivateKey: identity.privateKey,
    senderUsername: senderUsername,
    messageId: sourceEventId,
  );

  if (remainingPeerIds.isNotEmpty) {
    final inboxPayload = jsonEncode({
      'groupId': group.id,
      'senderId': identity.peerId,
      'senderUsername': senderUsername,
      'text': sysText,
      'timestamp': leftAt.toIso8601String(),
      'messageId': sourceEventId,
    });
    await storeGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: group.id,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: inboxPayload,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: identity.privateKey,
      messageId: leaveTimelineMessage.id,
      recipientPeerIds: remainingPeerIds,
    );
  }

  GroupKeyInfo? rotatedKey;
  if (remainingMembers.isNotEmpty) {
    rotatedKey = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: group.id,
      selfPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: identity.privateKey,
      senderUsername: senderUsername,
      sendP2PMessage: sendP2PMessage,
      storeP2PMessageInInbox: storeP2PMessageInInbox,
    );

    if (rotatedKey == null) {
      throw StateError(voluntaryLeaveRotationFailedMessage);
    }
  }

  return VoluntaryLeaveBroadcastResult(
    didBroadcast: true,
    remainingPeerIds: remainingPeerIds,
    rotatedKey: rotatedKey,
    skipReason: null,
  );
}
