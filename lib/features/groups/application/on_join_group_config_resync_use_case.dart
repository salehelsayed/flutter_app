import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/apply_on_join_group_config_resync.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_config_resync_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'dart:convert';

enum SendGroupConfigResyncResult {
  success,
  nodeNotRunning,
  encryptionRequired,
  invalidPayload,
  sendFailed,
}

/// Sends a best-effort `config:request` to the inviter so a freshly-joined
/// member can pull current authoritative metadata (finding D / L2).
Future<SendGroupConfigResyncResult> sendOnJoinGroupConfigRequest({
  required P2PService p2pService,
  required Bridge bridge,
  required String groupId,
  required String requesterPeerId,
  required String inviterPeerId,
  required String? inviterMlKemPublicKey,
}) async {
  return _sendEncrypted(
    p2pService: p2pService,
    bridge: bridge,
    type: groupConfigRequestType,
    groupId: groupId,
    senderPeerId: requesterPeerId,
    recipientPeerId: inviterPeerId,
    recipientMlKemPublicKey: inviterMlKemPublicKey,
    plaintext: GroupConfigRequestBody(
      groupId: groupId,
      requesterPeerId: requesterPeerId,
    ).toInnerJson(),
    eventPrefix: 'GROUP_CONFIG_REQUEST',
  );
}

/// Handles an inbound `config:request` at a peer that holds the group: verify
/// the requester is a current member, then (only if WE are an admin so the
/// joiner can trust us) reply with our authoritative, admin-signed config.
Future<void> handleIncomingGroupConfigRequest({
  required ChatMessage message,
  required GroupRepository groupRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityModel? ownIdentity,
  String? ownMlKemSecretKey,
  DateTime? now,
}) async {
  final envelope = GroupConfigResyncEnvelope.parse(
    message.content,
    groupConfigRequestType,
  );
  if (envelope == null) return;
  if (envelope['senderPeerId'] != message.from) return;
  final body = await _decryptInner(
    envelope: envelope,
    bridge: bridge,
    ownMlKemSecretKey: ownMlKemSecretKey,
    parse: GroupConfigRequestBody.fromInnerJson,
    eventPrefix: 'GROUP_CONFIG_REQUEST',
  );
  if (body == null) return;

  // Only answer current members.
  final requester = await groupRepo.getMember(body.groupId, message.from);
  if (requester == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_CONFIG_REQUEST_HANDLE_NOT_MEMBER',
      details: {},
    );
    return;
  }

  final identity = ownIdentity;
  if (identity == null) return;
  final group = await groupRepo.getGroup(body.groupId);
  if (group == null) return;
  final members = await groupRepo.getMembers(body.groupId);

  // Only an admin's reply is trusted by the joiner's applier, so don't bother
  // replying otherwise.
  final ownMembership = members.firstWhere(
    (m) => m.peerId == identity.peerId,
    orElse: () => GroupMember(
      groupId: body.groupId,
      peerId: identity.peerId,
      role: MemberRole.reader,
      joinedAt: DateTime.now().toUtc(),
    ),
  );
  if (ownMembership.role != MemberRole.admin) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_CONFIG_REQUEST_HANDLE_NOT_ADMIN_RESPONDER',
      details: {},
    );
    return;
  }

  final groupConfig = buildGroupConfigPayload(group, members);
  final updatedAt = (group.lastMetadataEventAt ?? group.createdAt).toUtc();
  final actorPayload = buildGroupMetadataActorEventPayload(
    groupId: body.groupId,
    updatedAt: updatedAt,
    actorPeerId: identity.peerId,
    actorUsername: identity.username,
    actorPublicKey: identity.publicKey,
    groupConfig: groupConfig,
  );
  final canonical = canonicalizeGroupMetadataActorEventPayload(actorPayload);
  final signResponse = await callSignPayload(
    bridge: bridge,
    dataToSign: canonical,
    privateKey: identity.privateKey,
  );
  final signature = signResponse['signature'] as String?;
  if (signResponse['ok'] != true ||
      signature == null ||
      signature.trim().isEmpty) {
    return;
  }
  final systemPayload = <String, dynamic>{
    '__sys': groupMetadataUpdatedEventType,
    'updatedAt': updatedAt.toIso8601String(),
    'groupConfig': groupConfig,
    groupMetadataActorEventEnvelopeField:
        buildSignedGroupMetadataActorEventEnvelope(
          signedPayload: canonical,
          signature: signature,
        ),
  };

  await _sendEncrypted(
    p2pService: p2pService,
    bridge: bridge,
    type: groupConfigResponseType,
    groupId: body.groupId,
    senderPeerId: identity.peerId,
    recipientPeerId: message.from,
    recipientMlKemPublicKey: requester.mlKemPublicKey,
    plaintext: jsonEncode(systemPayload),
    eventPrefix: 'GROUP_CONFIG_RESPONSE',
  );
}

/// Handles an inbound `config:response`: decrypt → apply (verified + strictly
/// newer).
Future<ApplyGroupConfigResponseResult> handleIncomingGroupConfigResponse({
  required ChatMessage message,
  required GroupRepository groupRepo,
  required Bridge bridge,
  String? ownMlKemSecretKey,
  DownloadGroupAvatarFn? downloadGroupAvatarFn,
  DateTime? now,
}) async {
  final envelope = GroupConfigResyncEnvelope.parse(
    message.content,
    groupConfigResponseType,
  );
  if (envelope == null) {
    return ApplyGroupConfigResponseResult.invalidPayload;
  }
  if (envelope['senderPeerId'] != message.from) {
    return ApplyGroupConfigResponseResult.invalidPayload;
  }
  final systemPayload = await _decryptInner(
    envelope: envelope,
    bridge: bridge,
    ownMlKemSecretKey: ownMlKemSecretKey,
    parse: (json) {
      try {
        final decoded = jsonDecode(json);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } catch (_) {
        return null;
      }
    },
    eventPrefix: 'GROUP_CONFIG_RESPONSE',
  );
  if (systemPayload == null) {
    return ApplyGroupConfigResponseResult.invalidPayload;
  }

  final groupId = envelope['id'] as String;
  return applyOnJoinGroupConfigResponse(
    systemPayload: systemPayload,
    groupId: groupId,
    groupRepo: groupRepo,
    bridge: bridge,
    downloadGroupAvatarFn: downloadGroupAvatarFn,
    now: now,
  );
}

Future<SendGroupConfigResyncResult> _sendEncrypted({
  required P2PService p2pService,
  required Bridge bridge,
  required String type,
  required String groupId,
  required String senderPeerId,
  required String recipientPeerId,
  required String? recipientMlKemPublicKey,
  required String plaintext,
  required String eventPrefix,
}) async {
  if (!p2pService.currentState.isStarted) {
    return SendGroupConfigResyncResult.nodeNotRunning;
  }
  if (recipientMlKemPublicKey == null || recipientMlKemPublicKey.trim().isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: '${eventPrefix}_SEND_ENCRYPTION_SKIPPED',
      details: {},
    );
    return SendGroupConfigResyncResult.encryptionRequired;
  }

  late final String envelopeJson;
  try {
    final encryptResult = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      plaintext: plaintext,
    );
    if (encryptResult['ok'] != true) {
      return SendGroupConfigResyncResult.sendFailed;
    }
    envelopeJson = GroupConfigResyncEnvelope.build(
      type: type,
      senderPeerId: senderPeerId,
      groupId: groupId,
      kem: encryptResult['kem'] as String,
      ciphertext: encryptResult['ciphertext'] as String,
      nonce: encryptResult['nonce'] as String,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: '${eventPrefix}_SEND_ENCRYPT_ERROR',
      details: {'error': e.toString()},
    );
    return SendGroupConfigResyncResult.sendFailed;
  }

  try {
    final sent = await p2pService.sendMessage(recipientPeerId, envelopeJson);
    if (sent) return SendGroupConfigResyncResult.success;
  } catch (_) {}
  try {
    final stored = await p2pService.storeInInbox(recipientPeerId, envelopeJson);
    if (stored) return SendGroupConfigResyncResult.success;
  } catch (_) {}
  return SendGroupConfigResyncResult.sendFailed;
}

Future<T?> _decryptInner<T>({
  required Map<String, dynamic> envelope,
  required Bridge bridge,
  required String? ownMlKemSecretKey,
  required T? Function(String innerJson) parse,
  required String eventPrefix,
}) async {
  if (ownMlKemSecretKey == null || ownMlKemSecretKey.trim().isEmpty) {
    return null;
  }
  final encrypted = envelope['encrypted'] as Map<String, dynamic>;
  try {
    final decryptResult = await callDecryptMessage(
      bridge: bridge,
      ownMlKemSecretKey: ownMlKemSecretKey,
      kem: encrypted['kem'] as String,
      ciphertext: encrypted['ciphertext'] as String,
      nonce: encrypted['nonce'] as String,
    );
    if (decryptResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: '${eventPrefix}_HANDLE_DECRYPT_FAILED',
        details: {'errorCode': decryptResult['errorCode']},
      );
      return null;
    }
    return parse(decryptResult['plaintext'] as String);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: '${eventPrefix}_HANDLE_DECRYPT_ERROR',
      details: {'error': e.toString()},
    );
    return null;
  }
}
