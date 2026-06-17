import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_decline_ack_payload.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';

enum SendGroupInviteDeclineAckResult {
  success,
  nodeNotRunning,
  encryptionRequired,
  invalidPayload,
  sendFailed,
}

/// Sends a signed, encrypted decline acknowledgement from the declining
/// invitee to the inviter, so the inviter's per-peer delivery-attempt row can
/// flip to `declined`. Best-effort and fire-and-forget at the call site: it
/// returns a status but never blocks the local decline. Mirrors
/// [sendGroupInviteRevocation]'s transport (sign → encrypt → sendMessage →
/// storeInInbox fallback), minus the revoker-authorization snapshot — the
/// receiver's spoof guard is `declinedByPeerId == message.from`.
Future<SendGroupInviteDeclineAckResult> sendGroupInviteDeclineAck({
  required P2PService p2pService,
  required Bridge bridge,
  required String inviteId,
  required String groupId,
  required String inviterPeerId,
  required String? inviterMlKemPublicKey,
  required String declinerPeerId,
  required String declinerPrivateKey,
  DateTime? now,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_DECLINE_ACK_SEND_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'inviteId': inviteId.length > 8 ? inviteId.substring(0, 8) : inviteId,
    },
  );

  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_SEND_NODE_NOT_RUNNING',
      details: {},
    );
    return SendGroupInviteDeclineAckResult.nodeNotRunning;
  }

  if (inviterMlKemPublicKey == null || inviterMlKemPublicKey.trim().isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DECLINE_ACK_ENCRYPTION_SKIPPED',
      details: {'reason': 'missing_inviter_mlkem'},
    );
    return SendGroupInviteDeclineAckResult.encryptionRequired;
  }

  if (inviteId.trim().isEmpty ||
      groupId.trim().isEmpty ||
      inviterPeerId.trim().isEmpty ||
      declinerPeerId.trim().isEmpty ||
      declinerPrivateKey.trim().isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_SEND_INVALID_PAYLOAD',
      details: {'reason': 'missing_required_field'},
    );
    return SendGroupInviteDeclineAckResult.invalidPayload;
  }

  final declinedAt = (now ?? DateTime.now()).toUtc();
  final payload = GroupInviteDeclineAckPayload(
    inviteId: inviteId,
    groupId: groupId,
    declinedByPeerId: declinerPeerId,
    declinedAt: declinedAt.toIso8601String(),
    expiresAt: declinedAt.add(pendingGroupInviteTtl).toIso8601String(),
  );

  final canonicalPayload = payload.canonicalDeclineAckSignedPayload();
  late final GroupInviteDeclineAckPayload signedPayload;
  try {
    final signResponse = await callSignPayload(
      bridge: bridge,
      dataToSign: canonicalPayload,
      privateKey: declinerPrivateKey,
    );
    final signature = signResponse['signature'] as String?;
    if (signResponse['ok'] != true ||
        signature == null ||
        signature.trim().isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_DECLINE_ACK_SEND_INVALID_PAYLOAD',
        details: {'reason': 'sign_failed'},
      );
      return SendGroupInviteDeclineAckResult.invalidPayload;
    }
    signedPayload = payload.withDeclineSignature(
      signature: signature,
      signedPayload: canonicalPayload,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_SEND_INVALID_PAYLOAD',
      details: {'reason': 'sign_error', 'error': e.toString()},
    );
    return SendGroupInviteDeclineAckResult.invalidPayload;
  }

  late final String envelopeJson;
  try {
    final encryptResult = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: inviterMlKemPublicKey,
      plaintext: signedPayload.toInnerJson(),
    );
    if (encryptResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_DECLINE_ACK_SEND_ENCRYPT_FAILED',
        details: {'errorCode': encryptResult['errorCode']},
      );
      return SendGroupInviteDeclineAckResult.sendFailed;
    }
    envelopeJson = GroupInviteDeclineAckPayload.buildEncryptedEnvelope(
      senderPeerId: declinerPeerId,
      inviteId: inviteId,
      kem: encryptResult['kem'] as String,
      ciphertext: encryptResult['ciphertext'] as String,
      nonce: encryptResult['nonce'] as String,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_SEND_ENCRYPT_ERROR',
      details: {'error': e.toString()},
    );
    return SendGroupInviteDeclineAckResult.sendFailed;
  }

  try {
    final sent = await p2pService.sendMessage(inviterPeerId, envelopeJson);
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_SEND_DIRECT_RESULT',
      details: {'sent': sent},
    );
    if (sent) {
      return SendGroupInviteDeclineAckResult.success;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_SEND_DIRECT_FAILED',
      details: {'error': e.toString()},
    );
  }

  try {
    final stored = await p2pService.storeInInbox(inviterPeerId, envelopeJson);
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_SEND_INBOX_RESULT',
      details: {'stored': stored},
    );
    if (stored) {
      return SendGroupInviteDeclineAckResult.success;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_SEND_INBOX_FAILED',
      details: {'error': e.toString()},
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_DECLINE_ACK_SEND_FAILED',
    details: {},
  );
  return SendGroupInviteDeclineAckResult.sendFailed;
}
