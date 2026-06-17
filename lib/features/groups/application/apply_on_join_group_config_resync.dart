import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

enum ApplyGroupConfigResponseResult {
  applied,
  notNewer,
  unauthenticated,
  notMember,
  invalidPayload,
}

/// Applies a verified, admin-signed `config:response` to the local group
/// (finding D / L2). The decrypted [systemPayload] is the `__sys`
/// `group_metadata_updated` body. This is a metadata-mutation vector, so it
/// applies ONLY when:
///   1. the signer is a CURRENT ADMIN member known locally with a matching
///      public key (no self-promotion / impersonation), AND
///   2. the embedded actor-event signature cryptographically verifies, AND
///   3. the response metadata is STRICTLY NEWER than the local watermark
///      (`lastMetadataEventAt` only ever moves forward).
///
/// Members must NOT route through `updateGroupMetadata` (it throws for
/// non-admins and under recovery) — this is the dedicated member-side applier.
Future<ApplyGroupConfigResponseResult> applyOnJoinGroupConfigResponse({
  required Map<String, dynamic> systemPayload,
  required String groupId,
  required GroupRepository groupRepo,
  required Bridge bridge,
  DownloadGroupAvatarFn? downloadGroupAvatarFn,
  DateTime? now,
}) async {
  // Read the signer identity from the signed actor-event payload.
  final actorEnvelope = systemPayload[groupMetadataActorEventEnvelopeField];
  if (actorEnvelope is! Map) {
    return ApplyGroupConfigResponseResult.invalidPayload;
  }
  final signedPayloadStr =
      actorEnvelope[groupMetadataActorEventSignedPayloadField] as String?;
  if (signedPayloadStr == null || signedPayloadStr.isEmpty) {
    return ApplyGroupConfigResponseResult.invalidPayload;
  }
  Map<String, dynamic> decodedSigned;
  try {
    final decoded = jsonDecode(signedPayloadStr);
    if (decoded is! Map) return ApplyGroupConfigResponseResult.invalidPayload;
    decodedSigned = Map<String, dynamic>.from(decoded);
  } catch (_) {
    return ApplyGroupConfigResponseResult.invalidPayload;
  }
  final actor = decodedSigned['actor'];
  if (actor is! Map) return ApplyGroupConfigResponseResult.invalidPayload;
  final actorPeerId = actor['peerId'] as String?;
  final actorUsername = actor['username'] as String?;
  if (actorPeerId == null || actorPeerId.isEmpty) {
    return ApplyGroupConfigResponseResult.invalidPayload;
  }

  // The signer must be a CURRENT ADMIN member known locally.
  final signerMember = await groupRepo.getMember(groupId, actorPeerId);
  if (signerMember == null ||
      signerMember.role != MemberRole.admin ||
      signerMember.publicKey == null ||
      signerMember.publicKey!.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ONJOIN_CONFIG_RESYNC_APPLY_NOT_ADMIN_SIGNER',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return ApplyGroupConfigResponseResult.notMember;
  }

  // Structural binding + signer-key binding.
  final verificationData = extractGroupMetadataActorEventVerificationData(
    systemPayload: systemPayload,
    groupId: groupId,
    senderId: actorPeerId,
    senderUsername: actorUsername ?? signerMember.username ?? '',
    trustedActorPublicKey: signerMember.publicKey!,
  );
  if (verificationData == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ONJOIN_CONFIG_RESYNC_APPLY_STRUCTURAL_REJECT',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return ApplyGroupConfigResponseResult.invalidPayload;
  }

  // Cryptographic signature verification (extract only checks structure).
  final signatureValid = await callVerifyPayload(
    bridge: bridge,
    publicKey: verificationData.actorPublicKey,
    data: verificationData.signedPayload,
    signature: verificationData.signature,
  );
  if (!signatureValid) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ONJOIN_CONFIG_RESYNC_APPLY_SIGNATURE_INVALID',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return ApplyGroupConfigResponseResult.unauthenticated;
  }

  final config = systemPayload['groupConfig'];
  if (config is! Map) return ApplyGroupConfigResponseResult.invalidPayload;
  final updatedAtStr = systemPayload['updatedAt'] as String?;
  final responseMetadataAt = updatedAtStr == null
      ? null
      : DateTime.tryParse(updatedAtStr)?.toUtc();
  if (responseMetadataAt == null) {
    return ApplyGroupConfigResponseResult.invalidPayload;
  }

  final localGroup = await groupRepo.getGroup(groupId);
  if (localGroup == null) {
    return ApplyGroupConfigResponseResult.notMember;
  }

  // Strictly-newer watermark (mirrors inviteMetadataIsCurrent inverted).
  final localWatermark = localGroup.lastMetadataEventAt?.toUtc();
  if (localWatermark != null && !responseMetadataAt.isAfter(localWatermark)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ONJOIN_CONFIG_RESYNC_APPLY_NOT_NEWER',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return ApplyGroupConfigResponseResult.notNewer;
  }

  final newName = config['name'] as String? ?? localGroup.name;
  final newDescription = config['description'] as String?;
  final newAvatarBlobId = config['avatarBlobId'] as String?;
  final newAvatarMime = config['avatarMime'] as String?;

  await groupRepo.updateGroup(
    localGroup.copyWith(
      name: newName,
      description: newDescription,
      avatarBlobId: newAvatarBlobId,
      avatarMime: newAvatarMime,
      lastMetadataEventAt: responseMetadataAt,
    ),
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'ONJOIN_CONFIG_RESYNC_APPLY_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  // Best-effort avatar fetch + persist, re-checking the watermark so a
  // concurrently-fresher local edit is never clobbered (mirrors materialize).
  if (newAvatarBlobId != null && newAvatarMime != null) {
    final avatarPath = await (downloadGroupAvatarFn ?? downloadGroupAvatar)(
      bridge: bridge,
      groupId: groupId,
      blobId: newAvatarBlobId,
    );
    if (avatarPath != null) {
      final refreshed = await groupRepo.getGroup(groupId);
      final refreshedWatermark = refreshed?.lastMetadataEventAt?.toUtc();
      final stillCurrent =
          refreshedWatermark == null ||
          !responseMetadataAt.isBefore(refreshedWatermark);
      if (refreshed != null &&
          stillCurrent &&
          refreshed.avatarBlobId == newAvatarBlobId &&
          refreshed.avatarMime == newAvatarMime) {
        await groupRepo.updateGroup(refreshed.copyWith(avatarPath: avatarPath));
      }
    }
  }

  return ApplyGroupConfigResponseResult.applied;
}
