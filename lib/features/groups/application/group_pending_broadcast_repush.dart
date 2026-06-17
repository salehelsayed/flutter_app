import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
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
