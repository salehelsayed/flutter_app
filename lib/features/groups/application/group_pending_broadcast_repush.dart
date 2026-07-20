import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

/// Builds the [GroupPendingBroadcastRunner] re-push function: re-publishes a
/// stored (already-signed) broadcast verbatim and re-stores it to the relay
/// inbox for its recipients. Returns `true` only when both legs succeed, so a
/// partial failure retains the row for the next drain (idempotent — the
/// receive-side dedups by the broadcast's source message id).
Future<bool> Function(GroupPendingBroadcast broadcast)
buildGroupPendingBroadcastRePush({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required Future<IdentityModel?> Function() loadIdentity,
}) {
  return (broadcast) async {
    if (broadcast.kind == groupPendingBroadcastKindMemberRolePrepared) {
      // This check must precede every await. A runner that loaded the prepared
      // row before activation must not later delete the activated row as stale.
      if (isGroupRolePreparationInFlight(broadcast.id)) return false;
      final preparedMember = _preparedRoleMember(broadcast.sysText);
      if (preparedMember == null) return false;
      final currentMember = await groupRepo.getMember(
        broadcast.groupId,
        preparedMember.peerId,
      );
      final currentGroup = await groupRepo.getGroup(broadcast.groupId);
      final sourceEventId = broadcast.sourceMessageId;
      final hasExactCommitProof =
          sourceEventId != null &&
          currentGroup?.lastMembershipEventId == sourceEventId &&
          currentGroup?.lastMembershipEventAt != null &&
          currentGroup!.lastMembershipEventAt!.toUtc().isAtSameMomentAs(
            broadcast.eventAt.toUtc(),
          );
      if (!hasExactCommitProof ||
          currentMember?.role.toValue() != preparedMember.role) {
        final watermarkAt = currentGroup?.lastMembershipEventAt?.toUtc();
        final watermarkId = currentGroup?.lastMembershipEventId;
        final isSuperseded =
            sourceEventId != null &&
            watermarkAt != null &&
            (watermarkAt.isAfter(broadcast.eventAt.toUtc()) ||
                (watermarkAt.isAtSameMomentAs(broadcast.eventAt.toUtc()) &&
                    watermarkId != null &&
                    watermarkId.compareTo(sourceEventId) > 0));
        if (isSuperseded) {
          // A newer authoritative membership event makes this prepared row
          // obsolete. It is safe to clear without publishing stale state.
          return true;
        }
        // Role equality alone is not commit proof: the local role write occurs
        // before native config and the durable membership watermark. Retain
        // every ambiguous partial state so exit remains fail-closed.
        return false;
      }
    }

    final identity = await loadIdentity();
    if (identity == null) return false;

    final senderBinding = await resolveGroupSenderDeviceBinding(
      groupRepo: groupRepo,
      groupId: broadcast.groupId,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
    );

    final publishResult = await callGroupPublish(
      bridge,
      groupId: broadcast.groupId,
      text: broadcast.sysText,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: identity.privateKey,
      senderUsername: identity.username,
      senderDeviceId: senderBinding.deviceId,
      senderTransportPeerId: senderBinding.transportPeerId,
      senderDevicePublicKey: senderBinding.devicePublicKey,
      senderKeyPackageId: senderBinding.keyPackageId,
      messageId: broadcast.sourceMessageId,
    );
    if (publishResult['ok'] != true) return false;

    if (broadcast.recipientPeerIds.isEmpty) return true;

    final inboxPayload = jsonEncode({
      'groupId': broadcast.groupId,
      'senderId': identity.peerId,
      'senderUsername': identity.username,
      if (senderBinding.deviceId != null)
        'senderDeviceId': senderBinding.deviceId,
      if (senderBinding.transportPeerId != null)
        'transportPeerId': senderBinding.transportPeerId,
      'text': broadcast.sysText,
      'timestamp': broadcast.eventAt.toUtc().toIso8601String(),
      'messageId': broadcast.sourceMessageId,
    });
    final replayEnvelope = await buildGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: broadcast.groupId,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: inboxPayload,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: identity.privateKey,
      senderDeviceId: senderBinding.deviceId,
      senderTransportPeerId: senderBinding.transportPeerId,
      senderKeyPackageId: senderBinding.keyPackageId,
      messageId: broadcast.sourceMessageId,
      recipientPeerIds: broadcast.recipientPeerIds,
    );
    await callGroupInboxStore(
      bridge,
      broadcast.groupId,
      replayEnvelope,
      recipientPeerIds: broadcast.recipientPeerIds,
      preserveRecipientPeerIds: true,
    );
    return true;
  };
}

({String peerId, String role})? _preparedRoleMember(String sysText) {
  try {
    final payload = jsonDecode(sysText);
    if (payload is! Map<String, dynamic>) return null;
    final member = payload['member'];
    if (member is! Map<String, dynamic>) return null;
    final peerId = (member['peerId'] as String?)?.trim();
    final role = (member['role'] as String?)?.trim();
    if (peerId == null || peerId.isEmpty || role == null || role.isEmpty) {
      return null;
    }
    return (peerId: peerId, role: role);
  } catch (_) {
    return null;
  }
}
