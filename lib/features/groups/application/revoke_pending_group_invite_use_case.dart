import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_invite_auth.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation_payload.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';

enum RevokePendingGroupInviteResult { revoked, notFound }

enum SendGroupInviteRevocationResult {
  success,
  nodeNotRunning,
  encryptionRequired,
  invalidPayload,
  sendFailed,
}

Future<RevokePendingGroupInviteResult> revokePendingGroupInvite({
  required PendingGroupInviteRepository pendingInviteRepo,
  required String groupId,
  DateTime? now,
  String? revokedBy,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'PENDING_GROUP_INVITE_REVOKE_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final invite = await pendingInviteRepo.getPendingInvite(groupId);
  if (invite == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_REVOKE_NOT_FOUND',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return RevokePendingGroupInviteResult.notFound;
  }

  final revokedAt = (now ?? DateTime.now()).toUtc();
  await pendingInviteRepo.saveRevokedInvite(
    GroupInviteRevocation(
      inviteId: invite.inviteId,
      groupId: invite.groupId,
      revokedAt: revokedAt,
      expiresAt: revokedAt.add(pendingGroupInviteTtl),
      revokedBy: revokedBy,
    ),
  );
  await pendingInviteRepo.deletePendingInvite(groupId);

  emitFlowEvent(
    layer: 'FL',
    event: 'PENDING_GROUP_INVITE_REVOKE_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );
  return RevokePendingGroupInviteResult.revoked;
}

Future<SendGroupInviteRevocationResult> sendGroupInviteRevocation({
  required P2PService p2pService,
  required Bridge bridge,
  required String inviteId,
  required String groupId,
  required String recipientPeerId,
  required String? recipientMlKemPublicKey,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required Map<String, dynamic> groupConfig,
  DateTime? now,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_REVOCATION_SEND_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'inviteId': inviteId.length > 8 ? inviteId.substring(0, 8) : inviteId,
    },
  );

  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_SEND_NODE_NOT_RUNNING',
      details: {},
    );
    return SendGroupInviteRevocationResult.nodeNotRunning;
  }

  if (recipientMlKemPublicKey == null ||
      recipientMlKemPublicKey.trim().isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_SEND_ENCRYPTION_REQUIRED',
      details: {},
    );
    return SendGroupInviteRevocationResult.encryptionRequired;
  }

  if (inviteId.trim().isEmpty ||
      groupId.trim().isEmpty ||
      recipientPeerId.trim().isEmpty ||
      senderPeerId.trim().isEmpty ||
      senderPublicKey.trim().isEmpty ||
      senderPrivateKey.trim().isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_SEND_INVALID_PAYLOAD',
      details: {'reason': 'missing_required_field'},
    );
    return SendGroupInviteRevocationResult.invalidPayload;
  }

  final revokedAt = (now ?? DateTime.now()).toUtc();
  final revokerAuthorization = buildGroupInviteRevokerAuthorizationSnapshot(
    groupConfig: groupConfig,
    revokedByPeerId: senderPeerId,
    trustedRevokerPublicKey: senderPublicKey,
  );
  if (revokerAuthorization == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_SEND_INVALID_PAYLOAD',
      details: {'reason': 'revoker_snapshot_missing'},
    );
    return SendGroupInviteRevocationResult.invalidPayload;
  }

  final payload = GroupInviteRevocationPayload(
    inviteId: inviteId,
    groupId: groupId,
    recipientPeerId: recipientPeerId,
    revokedByPeerId: senderPeerId,
    revokedAt: revokedAt.toIso8601String(),
    expiresAt: revokedAt.add(pendingGroupInviteTtl).toIso8601String(),
    revokerAuthorization: revokerAuthorization,
  );
  if (!isRevokerAuthorizedBySignedSnapshot(
    payload: payload,
    trustedRevokerPublicKey: senderPublicKey,
  )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_SEND_INVALID_PAYLOAD',
      details: {'reason': 'revoker_not_authorized'},
    );
    return SendGroupInviteRevocationResult.invalidPayload;
  }

  final canonicalPayload = payload.canonicalRevocationSignedPayload();
  late final GroupInviteRevocationPayload signedPayload;
  try {
    final signResponse = await callSignPayload(
      bridge: bridge,
      dataToSign: canonicalPayload,
      privateKey: senderPrivateKey,
    );
    final signature = signResponse['signature'] as String?;
    if (signResponse['ok'] != true ||
        signature == null ||
        signature.trim().isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_REVOCATION_SEND_INVALID_PAYLOAD',
        details: {'reason': 'sign_failed'},
      );
      return SendGroupInviteRevocationResult.invalidPayload;
    }
    signedPayload = payload.withRevocationSignature(
      signature: signature,
      signedPayload: canonicalPayload,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_SEND_INVALID_PAYLOAD',
      details: {'reason': 'sign_error', 'error': e.toString()},
    );
    return SendGroupInviteRevocationResult.invalidPayload;
  }

  late final String envelopeJson;
  try {
    final encryptResult = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      plaintext: signedPayload.toInnerJson(),
    );
    if (encryptResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_REVOCATION_SEND_ENCRYPT_FAILED',
        details: {'errorCode': encryptResult['errorCode']},
      );
      return SendGroupInviteRevocationResult.sendFailed;
    }

    envelopeJson = GroupInviteRevocationPayload.buildEncryptedEnvelope(
      senderPeerId: senderPeerId,
      inviteId: inviteId,
      kem: encryptResult['kem'] as String,
      ciphertext: encryptResult['ciphertext'] as String,
      nonce: encryptResult['nonce'] as String,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_SEND_ENCRYPT_ERROR',
      details: {'error': e.toString()},
    );
    return SendGroupInviteRevocationResult.sendFailed;
  }

  try {
    final sent = await p2pService.sendMessage(recipientPeerId, envelopeJson);
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_SEND_DIRECT_RESULT',
      details: {'sent': sent},
    );
    if (sent) {
      return SendGroupInviteRevocationResult.success;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_SEND_DIRECT_FAILED',
      details: {'error': e.toString()},
    );
  }

  try {
    final stored = await p2pService.storeInInbox(recipientPeerId, envelopeJson);
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_SEND_INBOX_RESULT',
      details: {'stored': stored},
    );
    if (stored) {
      return SendGroupInviteRevocationResult.success;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_SEND_INBOX_FAILED',
      details: {'error': e.toString()},
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_REVOCATION_SEND_FAILED',
    details: {},
  );
  return SendGroupInviteRevocationResult.sendFailed;
}
