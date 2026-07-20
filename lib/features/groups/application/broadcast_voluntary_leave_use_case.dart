import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
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
  final Map<String, dynamic>? livePublishResult;

  /// True when the member left but could NOT rotate the group key because the
  /// leaver lacks the `rotateKeys` permission and/or is not the group creator.
  /// The departure still broadcasts and completes (best-effort rotation); the
  /// group owes a re-key, which a remaining admin performs on receiving the
  /// `member_removed` — mirroring admin-removal's remover-driven rotation.
  final bool rotationDeferred;

  const VoluntaryLeaveBroadcastResult({
    required this.didBroadcast,
    required this.remainingPeerIds,
    this.rotatedKey,
    this.skipReason,
    this.livePublishResult,
    this.rotationDeferred = false,
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
  void Function(String messageId)? onTimelineMessageSaved,
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
  final senderBinding = resolveGroupSenderDeviceBindingFromMember(
    member: selfMember.first,
    senderPublicKey: identity.publicKey,
  );

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
    actorDeviceId: senderBinding.deviceId,
    actorTransportPeerId: senderBinding.transportPeerId,
    actorKeyPackageId: senderBinding.keyPackageId,
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
    onTimelineMessageSaved?.call(leaveTimelineMessage.id);
  }

  final livePublishResult = await callGroupPublish(
    bridge,
    groupId: group.id,
    text: sysText,
    senderPeerId: identity.peerId,
    senderPublicKey: identity.publicKey,
    senderPrivateKey: identity.privateKey,
    senderUsername: senderUsername,
    senderDeviceId: senderBinding.deviceId,
    senderTransportPeerId: senderBinding.transportPeerId,
    senderDevicePublicKey: senderBinding.devicePublicKey,
    senderKeyPackageId: senderBinding.keyPackageId,
    messageId: sourceEventId,
  );

  if (remainingPeerIds.isNotEmpty) {
    final inboxPayload = jsonEncode({
      'groupId': group.id,
      'senderId': identity.peerId,
      'senderUsername': senderUsername,
      if (senderBinding.deviceId != null)
        'senderDeviceId': senderBinding.deviceId,
      if (senderBinding.transportPeerId != null)
        'transportPeerId': senderBinding.transportPeerId,
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
      senderDeviceId: senderBinding.deviceId,
      senderTransportPeerId: senderBinding.transportPeerId,
      senderKeyPackageId: senderBinding.keyPackageId,
      messageId: leaveTimelineMessage.id,
      recipientPeerIds: remainingPeerIds,
    );
  }

  GroupKeyInfo? rotatedKey;
  var rotationDeferred = false;
  if (remainingMembers.isNotEmpty) {
    final rotationOutcome = await rotateAndDistributeGroupKey(
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
    rotatedKey = rotationOutcome.key;

    // Best-effort rotation: a privileged leaver (creator/admin) rotates here
    // exactly as before. A plain member fails the rotation gates and gets a
    // null result — do NOT abort the leave. Record the deferral so the caller
    // proceeds to leaveGroup(); a remaining admin re-keys on receiving the
    // member_removed, preserving forward secrecy without forcing the departing
    // member to hold rotateKeys/creator status.
    rotationDeferred = rotatedKey == null;
    if (rotationDeferred) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_VOLUNTARY_LEAVE_ROTATION_DEFERRED',
        details: {
          'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
        },
      );
    }
  }

  return VoluntaryLeaveBroadcastResult(
    didBroadcast: true,
    remainingPeerIds: remainingPeerIds,
    rotatedKey: rotatedKey,
    skipReason: null,
    livePublishResult: livePublishResult,
    rotationDeferred: rotationDeferred,
  );
}
