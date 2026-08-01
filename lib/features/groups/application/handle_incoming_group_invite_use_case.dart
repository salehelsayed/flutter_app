import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_invite_auth.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Result of handling an incoming group invite.
enum HandleGroupInviteResult {
  success,
  duplicateGroup,
  invalidPayload,
  unknownSender,
  decryptionFailed,
  bridgeError,
}

enum StorePendingGroupInviteResult {
  storedPending,
  duplicateGroup,
  revoked,
  alreadyUsed,
  invalidPayload,
  unknownSender,
  decryptionFailed,
}

enum HandleGroupInviteRevocationResult {
  revoked,
  invalidPayload,
  unknownSender,
  decryptionFailed,
}

enum _ResolveIncomingGroupInviteResult {
  success,
  invalidPayload,
  unknownSender,
  decryptionFailed,
}

class _ResolvedGroupInvite {
  final GroupInvitePayload payload;

  const _ResolvedGroupInvite(this.payload);
}

class _ResolvedGroupInviteRevocation {
  final GroupInviteRevocationPayload payload;

  const _ResolvedGroupInviteRevocation(this.payload);
}

Future<(_ResolveIncomingGroupInviteResult, _ResolvedGroupInvite?)>
_resolveIncomingGroupInvite({
  required ChatMessage message,
  required ContactRepository contactRepo,
  required Bridge bridge,
  String? ownMlKemSecretKey,
  String? ownPeerId,
  String? ownDeviceId,
  String? ownTransportPeerId,
  String? ownMlKemPublicKey,
  String? ownKeyPackageId,
  String? ownKeyPackagePublicMaterial,
  DateTime? validationTime,
}) async {
  GroupInvitePayload? payload;

  final v2Envelope = GroupInvitePayload.parseEncryptedEnvelope(message.content);
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_HANDLE_ENVELOPE_CHECK',
    details: {
      'isV2': v2Envelope != null,
      'contentLength': message.content.length,
    },
  );
  if (v2Envelope != null) {
    final encrypted = v2Envelope['encrypted'] as Map<String, dynamic>;
    final kem = encrypted['kem'] as String;
    final ciphertext = encrypted['ciphertext'] as String;
    final nonce = encrypted['nonce'] as String;

    if (ownMlKemSecretKey == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_HANDLE_NO_SECRET_KEY',
        details: {},
      );
      return (_ResolveIncomingGroupInviteResult.decryptionFailed, null);
    }

    try {
      final decryptResult = await callDecryptMessage(
        bridge: bridge,
        ownMlKemSecretKey: ownMlKemSecretKey,
        kem: kem,
        ciphertext: ciphertext,
        nonce: nonce,
      );

      if (decryptResult['ok'] != true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INVITE_HANDLE_DECRYPT_FAILED',
          details: {'errorCode': decryptResult['errorCode']},
        );
        return (_ResolveIncomingGroupInviteResult.decryptionFailed, null);
      }

      final plaintext = decryptResult['plaintext'] as String;
      payload = GroupInvitePayload.fromInnerJson(plaintext);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_HANDLE_DECRYPT_ERROR',
        details: {'error': e.toString()},
      );
      return (_ResolveIncomingGroupInviteResult.decryptionFailed, null);
    }
  } else {
    payload = GroupInvitePayload.fromJson(message.content);
  }

  if (payload == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_INVALID_PAYLOAD',
      details: {},
    );
    return (_ResolveIncomingGroupInviteResult.invalidPayload, null);
  }

  final outerTransportPeerId = message.from.trim();
  final signedDeviceId = payload.senderDeviceId?.trim();
  final signedTransportPeerId = payload.senderTransportPeerId?.trim();
  final signedDevicePublicKey = payload.senderDeviceSigningPublicKey?.trim();
  final signedKeyPackageId = payload.senderKeyPackageId?.trim();
  final hasAnySignedDeviceBinding = <String?>[
    signedDeviceId,
    signedTransportPeerId,
    signedDevicePublicKey,
    signedKeyPackageId,
  ].any((value) => value != null && value.isNotEmpty);
  final hasCompleteSignedDeviceBinding =
      signedDeviceId != null &&
      signedDeviceId.isNotEmpty &&
      signedTransportPeerId != null &&
      signedTransportPeerId.isNotEmpty &&
      signedDevicePublicKey != null &&
      signedDevicePublicKey.isNotEmpty;
  final senderMatchesOuterTransport = hasAnySignedDeviceBinding
      ? hasCompleteSignedDeviceBinding &&
            signedTransportPeerId == outerTransportPeerId
      : payload.senderPeerId == outerTransportPeerId;
  if (!senderMatchesOuterTransport) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_SENDER_MISMATCH',
      details: {
        'transportSender': message.from.length > 10
            ? message.from.substring(0, 10)
            : message.from,
        'payloadSender': payload.senderPeerId.length > 10
            ? payload.senderPeerId.substring(0, 10)
            : payload.senderPeerId,
      },
    );
    return (_ResolveIncomingGroupInviteResult.invalidPayload, null);
  }

  final expectedRecipientPeerId = ownPeerId?.trim();
  if (expectedRecipientPeerId == null || expectedRecipientPeerId.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_MISSING_OWN_PEER_ID',
      details: {
        'messageTo': message.to.length > 10
            ? message.to.substring(0, 10)
            : message.to,
      },
    );
    return (_ResolveIncomingGroupInviteResult.invalidPayload, null);
  }

  if (!payload.isBoundToRecipientDevice(
    ownPeerId: expectedRecipientPeerId,
    ownDeviceId: ownDeviceId,
    ownTransportPeerId: ownTransportPeerId,
    ownMlKemPublicKey: ownMlKemPublicKey,
    ownKeyPackageId: ownKeyPackageId,
    ownKeyPackagePublicMaterial: ownKeyPackagePublicMaterial,
  )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_RECIPIENT_MISMATCH',
      details: {
        'messageTo': message.to.length > 10
            ? message.to.substring(0, 10)
            : message.to,
      },
    );
    return (_ResolveIncomingGroupInviteResult.invalidPayload, null);
  }

  final authResult = await verifyGroupInviteAttestation(
    payload: payload,
    contactRepo: contactRepo,
    bridge: bridge,
    validationTime: validationTime,
  );
  switch (authResult) {
    case GroupInviteAuthResult.authorized:
      break;
    case GroupInviteAuthResult.unknownSender:
      final senderPeerId = payload.senderPeerId;
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_HANDLE_UNKNOWN_SENDER',
        details: {
          'senderPeerId': senderPeerId.length > 10
              ? senderPeerId.substring(0, 10)
              : senderPeerId,
        },
      );
      return (_ResolveIncomingGroupInviteResult.unknownSender, null);
    case GroupInviteAuthResult.invalidPayload:
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_HANDLE_INVALID_SIGNATURE',
        details: {
          'groupId': payload.groupId.length > 8
              ? payload.groupId.substring(0, 8)
              : payload.groupId,
        },
      );
      return (_ResolveIncomingGroupInviteResult.invalidPayload, null);
  }

  return (
    _ResolveIncomingGroupInviteResult.success,
    _ResolvedGroupInvite(payload),
  );
}

Future<(HandleGroupInviteRevocationResult, _ResolvedGroupInviteRevocation?)>
_resolveIncomingGroupInviteRevocation({
  required ChatMessage message,
  required ContactRepository contactRepo,
  required Bridge bridge,
  String? ownMlKemSecretKey,
  String? ownPeerId,
  DateTime? now,
}) async {
  final envelope = GroupInviteRevocationPayload.parseEncryptedEnvelope(
    message.content,
  );
  if (envelope == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_HANDLE_INVALID_ENVELOPE',
      details: {},
    );
    return (HandleGroupInviteRevocationResult.invalidPayload, null);
  }

  final envelopeSenderPeerId = envelope['senderPeerId'] as String;
  if (envelopeSenderPeerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_HANDLE_SENDER_MISMATCH',
      details: {},
    );
    return (HandleGroupInviteRevocationResult.invalidPayload, null);
  }

  if (ownMlKemSecretKey == null || ownMlKemSecretKey.trim().isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_HANDLE_NO_SECRET_KEY',
      details: {},
    );
    return (HandleGroupInviteRevocationResult.decryptionFailed, null);
  }

  final encrypted = envelope['encrypted'] as Map<String, dynamic>;
  late final GroupInviteRevocationPayload payload;
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
        event: 'GROUP_INVITE_REVOCATION_HANDLE_DECRYPT_FAILED',
        details: {'errorCode': decryptResult['errorCode']},
      );
      return (HandleGroupInviteRevocationResult.decryptionFailed, null);
    }

    final plaintext = decryptResult['plaintext'] as String;
    final parsedPayload = GroupInviteRevocationPayload.fromInnerJson(plaintext);
    if (parsedPayload == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_REVOCATION_HANDLE_INVALID_PAYLOAD',
        details: {},
      );
      return (HandleGroupInviteRevocationResult.invalidPayload, null);
    }
    payload = parsedPayload;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_HANDLE_DECRYPT_ERROR',
      details: {'error': e.toString()},
    );
    return (HandleGroupInviteRevocationResult.decryptionFailed, null);
  }

  if (payload.revokedByPeerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_HANDLE_PAYLOAD_SENDER_MISMATCH',
      details: {},
    );
    return (HandleGroupInviteRevocationResult.invalidPayload, null);
  }

  final expectedRecipient = _effectiveRecipientPeerId(
    ownPeerId: ownPeerId,
    message: message,
  );
  if (expectedRecipient != null &&
      !payload.isBoundToRecipient(expectedRecipient)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_HANDLE_RECIPIENT_MISMATCH',
      details: {},
    );
    return (HandleGroupInviteRevocationResult.invalidPayload, null);
  }

  final effectiveNow = (now ?? DateTime.now()).toUtc();
  if (payload.isExpiredAt(effectiveNow)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_HANDLE_EXPIRED',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
      },
    );
    return (HandleGroupInviteRevocationResult.invalidPayload, null);
  }

  final authResult = await verifyGroupInviteRevocationAttestation(
    payload: payload,
    contactRepo: contactRepo,
    bridge: bridge,
  );
  switch (authResult) {
    case GroupInviteAuthResult.authorized:
      break;
    case GroupInviteAuthResult.unknownSender:
      return (HandleGroupInviteRevocationResult.unknownSender, null);
    case GroupInviteAuthResult.invalidPayload:
      return (HandleGroupInviteRevocationResult.invalidPayload, null);
  }

  return (
    HandleGroupInviteRevocationResult.revoked,
    _ResolvedGroupInviteRevocation(payload),
  );
}

String? _effectiveRecipientPeerId({
  required String? ownPeerId,
  required ChatMessage message,
}) {
  final own = ownPeerId?.trim();
  if (own != null && own.isNotEmpty) {
    return own;
  }
  final to = message.to.trim();
  return to.isEmpty ? null : to;
}

Future<(HandleGroupInviteRevocationResult, PendingGroupInvite?)>
handleIncomingGroupInviteRevocation({
  required ChatMessage message,
  required PendingGroupInviteRepository pendingInviteRepo,
  required ContactRepository contactRepo,
  required Bridge bridge,
  String? ownMlKemSecretKey,
  String? ownPeerId,
  DateTime? now,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_REVOCATION_HANDLE_START',
    details: {
      'from': message.from.length > 10
          ? message.from.substring(0, 10)
          : message.from,
    },
  );

  final (
    resolveResult,
    resolvedRevocation,
  ) = await _resolveIncomingGroupInviteRevocation(
    message: message,
    contactRepo: contactRepo,
    bridge: bridge,
    ownMlKemSecretKey: ownMlKemSecretKey,
    ownPeerId: ownPeerId,
    now: now,
  );
  if (resolveResult != HandleGroupInviteRevocationResult.revoked) {
    return (resolveResult, null);
  }

  final payload = resolvedRevocation!.payload;
  final effectiveNow = (now ?? DateTime.now()).toUtc();
  final revocation = GroupInviteRevocation(
    inviteId: payload.inviteId,
    groupId: payload.groupId,
    revokedAt: payload.revokedAtDateTime,
    expiresAt: payload.expiresAtDateTime.isAfter(effectiveNow)
        ? payload.expiresAtDateTime
        : effectiveNow.add(pendingGroupInviteTtl),
    revokedBy: payload.revokedByPeerId,
  );
  await pendingInviteRepo.saveRevokedInvite(revocation);

  final pending = await pendingInviteRepo.getPendingInvite(payload.groupId);
  PendingGroupInvite? removedPendingInvite;
  if (pending != null && pending.inviteId == payload.inviteId) {
    removedPendingInvite = pending;
    await pendingInviteRepo.deletePendingInvite(payload.groupId);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_REVOCATION_HANDLE_SUCCESS',
    details: {
      'groupId': payload.groupId.length > 8
          ? payload.groupId.substring(0, 8)
          : payload.groupId,
      'removedPending': removedPendingInvite != null,
    },
  );
  return (HandleGroupInviteRevocationResult.revoked, removedPendingInvite);
}

Future<(StorePendingGroupInviteResult, PendingGroupInvite?)>
storeIncomingPendingGroupInvite({
  required ChatMessage message,
  required GroupRepository groupRepo,
  required PendingGroupInviteRepository pendingInviteRepo,
  required ContactRepository contactRepo,
  required Bridge bridge,
  String? ownMlKemSecretKey,
  String? ownPeerId,
  String? ownDeviceId,
  String? ownTransportPeerId,
  String? ownMlKemPublicKey,
  String? ownKeyPackageId,
  String? ownKeyPackagePublicMaterial,
  DateTime? receivedAt,
  Duration ttl = pendingGroupInviteTtl,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_STORE_PENDING_START',
    details: {
      'from': message.from.length > 10
          ? message.from.substring(0, 10)
          : message.from,
    },
  );

  final effectiveReceivedAt =
      (receivedAt ?? DateTime.tryParse(message.timestamp) ?? DateTime.now())
          .toUtc();
  final (resolveResult, resolvedInvite) = await _resolveIncomingGroupInvite(
    message: message,
    contactRepo: contactRepo,
    bridge: bridge,
    ownMlKemSecretKey: ownMlKemSecretKey,
    ownPeerId: ownPeerId,
    ownDeviceId: ownDeviceId,
    ownTransportPeerId: ownTransportPeerId,
    ownMlKemPublicKey: ownMlKemPublicKey,
    ownKeyPackageId: ownKeyPackageId,
    ownKeyPackagePublicMaterial: ownKeyPackagePublicMaterial,
    validationTime: effectiveReceivedAt,
  );

  switch (resolveResult) {
    case _ResolveIncomingGroupInviteResult.invalidPayload:
      return (StorePendingGroupInviteResult.invalidPayload, null);
    case _ResolveIncomingGroupInviteResult.unknownSender:
      return (StorePendingGroupInviteResult.unknownSender, null);
    case _ResolveIncomingGroupInviteResult.decryptionFailed:
      return (StorePendingGroupInviteResult.decryptionFailed, null);
    case _ResolveIncomingGroupInviteResult.success:
      break;
  }

  final payload = resolvedInvite!.payload;
  if (!payload.isInvitePolicyValid(validationTime: effectiveReceivedAt)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_STORE_PENDING_INVALID_POLICY',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
      },
    );
    return (StorePendingGroupInviteResult.invalidPayload, null);
  }

  final revocation = await pendingInviteRepo.getRevokedInvite(payload.id);
  if (revocation != null && revocation.isActiveAt(effectiveReceivedAt)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_STORE_PENDING_REVOKED',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
      },
    );
    return (StorePendingGroupInviteResult.revoked, null);
  }

  if (payload.invitePolicy.reusePolicy == GroupInviteReusePolicy.singleUse) {
    final consumption = await pendingInviteRepo.getConsumedInvite(payload.id);
    if (consumption != null && consumption.isActiveAt(effectiveReceivedAt)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_STORE_PENDING_ALREADY_USED',
        details: {
          'groupId': payload.groupId.length > 8
              ? payload.groupId.substring(0, 8)
              : payload.groupId,
        },
      );
      return (StorePendingGroupInviteResult.alreadyUsed, null);
    }
  }

  if (await _hasActiveWelcomeKeyPackageTombstone(
    pendingInviteRepo: pendingInviteRepo,
    payload: payload,
    now: effectiveReceivedAt,
  )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_STORE_PENDING_PACKAGE_ALREADY_USED',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
      },
    );
    return (StorePendingGroupInviteResult.alreadyUsed, null);
  }

  final existingInvite = await pendingInviteRepo.getPendingInvite(
    payload.groupId,
  );
  if (existingInvite != null && existingInvite.inviteId != payload.id) {
    final existingPayload = existingInvite.toPayload();
    if (existingPayload != null &&
        _incomingInviteIsStaleComparedToExistingPending(
          incoming: payload,
          existing: existingPayload,
          incomingReceivedAt: effectiveReceivedAt,
          existingReceivedAt: existingInvite.receivedAt,
        )) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_STORE_PENDING_STALE_IGNORED',
        details: {
          'groupId': payload.groupId.length > 8
              ? payload.groupId.substring(0, 8)
              : payload.groupId,
          'incomingEpoch': payload.keyEpoch,
          'existingEpoch': existingPayload.keyEpoch,
        },
      );
      return (StorePendingGroupInviteResult.invalidPayload, null);
    }
  }

  final selfPeerId = ownPeerId?.trim();
  final existingGroup = await groupRepo.getGroup(payload.groupId);
  if (existingGroup != null) {
    // B3 re-join: a previously-removed member RETAINS the group read-only
    // (self removed from members, keys cleared) instead of hard-deleting it,
    // so a fresh re-add invite must be STORED as pending — letting the
    // accept/materialize path re-join (re-saving group/members/key + myRole) —
    // rather than being dropped here as a duplicate. Detect the retained-removed
    // shell via self no longer being an active member: a voluntarily-left group
    // is hard-deleted (getGroup == null), so "row exists + self absent" uniquely
    // identifies the retained-removed case. A genuinely-joined duplicate (self
    // still a member) short-circuits as before. Mirrors the guard in
    // materializeAcceptedGroupInvitePayload.
    final selfIsActiveMember = selfPeerId == null || selfPeerId.isEmpty
        ? true
        : (await groupRepo.getMember(payload.groupId, selfPeerId)) != null;
    if (selfIsActiveMember) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_STORE_PENDING_DUPLICATE_GROUP',
        details: {
          'groupId': payload.groupId.length > 8
              ? payload.groupId.substring(0, 8)
              : payload.groupId,
        },
      );
      return (StorePendingGroupInviteResult.duplicateGroup, null);
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_STORE_PENDING_REJOIN_AFTER_REMOVAL',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
      },
    );
    // Fall through to store the pending invite so the accept/materialize path
    // re-joins the retained group.
  }

  final invite = PendingGroupInvite.fromPayload(
    payload,
    receivedAt: effectiveReceivedAt,
    ttl: ttl,
  );
  await pendingInviteRepo.savePendingInvite(invite);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_STORE_PENDING_SUCCESS',
    details: {
      'groupId': payload.groupId.length > 8
          ? payload.groupId.substring(0, 8)
          : payload.groupId,
    },
  );
  return (StorePendingGroupInviteResult.storedPending, invite);
}

bool _incomingInviteIsStaleComparedToExistingPending({
  required GroupInvitePayload incoming,
  required GroupInvitePayload existing,
  required DateTime incomingReceivedAt,
  required DateTime existingReceivedAt,
}) {
  if (incoming.keyEpoch != existing.keyEpoch) {
    return incoming.keyEpoch < existing.keyEpoch;
  }

  final incomingFreshnessAt =
      incoming.membershipFreshnessProof?.issuedAt.toUtc() ??
      DateTime.tryParse(incoming.timestamp)?.toUtc() ??
      incomingReceivedAt.toUtc();
  final existingFreshnessAt =
      existing.membershipFreshnessProof?.issuedAt.toUtc() ??
      DateTime.tryParse(existing.timestamp)?.toUtc() ??
      existingReceivedAt.toUtc();
  if (incomingFreshnessAt.isBefore(existingFreshnessAt)) {
    return true;
  }
  if (incomingFreshnessAt.isAfter(existingFreshnessAt)) {
    return false;
  }

  final incomingWatermark =
      incoming.membershipFreshnessProof?.membershipWatermark;
  final existingWatermark =
      existing.membershipFreshnessProof?.membershipWatermark;
  if (incomingWatermark != null &&
      existingWatermark != null &&
      incomingWatermark != existingWatermark) {
    return !incomingReceivedAt.toUtc().isAfter(existingReceivedAt.toUtc());
  }

  return false;
}

Future<bool> _hasActiveWelcomeKeyPackageTombstone({
  required PendingGroupInviteRepository pendingInviteRepo,
  required GroupInvitePayload payload,
  required DateTime now,
}) async {
  final welcome = payload.welcomeKeyPackage;
  if (welcome == null) {
    return false;
  }
  final tombstone = await pendingInviteRepo.getWelcomeKeyPackageTombstone(
    packageId: welcome.packageId,
    recipientDeviceId: welcome.recipientDeviceId,
    groupId: welcome.groupId,
  );
  return tombstone != null && tombstone.isActiveAt(now);
}

/// Processes an incoming group invite message.
///
/// Steps:
/// 1. Try v2 parse -> decrypt -> fromInnerJson. Fallback to v1 fromJson.
/// 2. Validate required fields (groupId, groupKey, groupConfig).
/// 3. Verify sender is a known contact.
/// 4. Check for duplicate group (getGroup(groupId) != null -> duplicateGroup).
/// 5. Parse groupConfig into GroupModel, members, key.
/// 6. Persist GroupModel with myRole = GroupRole.member.
/// 7. Persist each GroupMember from config.
/// 8. Persist GroupKeyInfo.
/// 9. Call callGroupJoinWithConfig (catch timeout -> bridgeError, but group is still persisted).
/// 10. Return success + groupId.
///
/// Returns a record of (result, groupId?) where groupId is non-null on success
/// or bridgeError (group was persisted).
Future<(HandleGroupInviteResult, String?)> handleIncomingGroupInvite({
  required ChatMessage message,
  required GroupRepository groupRepo,
  required ContactRepository contactRepo,
  required Bridge bridge,
  String? ownMlKemSecretKey,
  String? ownPeerId,
  String? ownDeviceId,
  String? ownTransportPeerId,
  String? ownMlKemPublicKey,
  String? ownKeyPackageId,
  String? ownKeyPackagePublicMaterial,
  DateTime? now,
  DateTime Function()? nowUtc,
  DownloadGroupAvatarFn? downloadGroupAvatarFn,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_HANDLE_START',
    details: {
      'from': message.from.length > 10
          ? message.from.substring(0, 10)
          : message.from,
    },
  );

  DateTime currentValidationTime() =>
      (nowUtc?.call() ?? now ?? DateTime.now()).toUtc();
  final effectiveNow = currentValidationTime();
  final (resolveResult, resolvedInvite) = await _resolveIncomingGroupInvite(
    message: message,
    contactRepo: contactRepo,
    bridge: bridge,
    ownMlKemSecretKey: ownMlKemSecretKey,
    ownPeerId: ownPeerId,
    ownDeviceId: ownDeviceId,
    ownTransportPeerId: ownTransportPeerId,
    ownMlKemPublicKey: ownMlKemPublicKey,
    ownKeyPackageId: ownKeyPackageId,
    ownKeyPackagePublicMaterial: ownKeyPackagePublicMaterial,
    validationTime: effectiveNow,
  );

  switch (resolveResult) {
    case _ResolveIncomingGroupInviteResult.invalidPayload:
      return (HandleGroupInviteResult.invalidPayload, null);
    case _ResolveIncomingGroupInviteResult.unknownSender:
      return (HandleGroupInviteResult.unknownSender, null);
    case _ResolveIncomingGroupInviteResult.decryptionFailed:
      return (HandleGroupInviteResult.decryptionFailed, null);
    case _ResolveIncomingGroupInviteResult.success:
      break;
  }

  if (!resolvedInvite!.payload.isInvitePolicyValid(
    validationTime: effectiveNow,
  )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_INVALID_POLICY',
      details: {
        'groupId': resolvedInvite.payload.groupId.length > 8
            ? resolvedInvite.payload.groupId.substring(0, 8)
            : resolvedInvite.payload.groupId,
      },
    );
    return (HandleGroupInviteResult.invalidPayload, null);
  }

  return materializeAcceptedGroupInvitePayload(
    payload: resolvedInvite.payload,
    groupRepo: groupRepo,
    bridge: bridge,
    downloadGroupAvatarFn: downloadGroupAvatarFn,
    ownPeerId: ownPeerId,
    validationNowUtc: currentValidationTime,
  );
}

Future<(HandleGroupInviteResult, String?)>
materializeAcceptedGroupInvitePayload({
  required GroupInvitePayload payload,
  required GroupRepository groupRepo,
  required Bridge bridge,
  DownloadGroupAvatarFn? downloadGroupAvatarFn,
  String? ownPeerId,
  DateTime Function()? validationNowUtc,
}) async {
  if (!payload.isInvitePolicyValid()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_INVALID_POLICY',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
      },
    );
    return (HandleGroupInviteResult.invalidPayload, null);
  }

  final requestedSelfPeerId = ownPeerId?.trim();
  final payloadRecipientPeerId = payload.recipientPeerId?.trim();
  final selfPeerId =
      requestedSelfPeerId != null && requestedSelfPeerId.isNotEmpty
      ? requestedSelfPeerId
      : payloadRecipientPeerId;
  final shellRepository = groupRepo is SelfRemovedGroupShellRepository
      ? groupRepo as SelfRemovedGroupShellRepository
      : null;
  final existingGroup = await groupRepo.getGroup(payload.groupId);
  var isPostRemovalReentry = false;
  DateTime? postRemovalGenerationFloor;
  if (existingGroup != null) {
    // B3 re-join: a previously-removed member RETAINS the group read-only
    // (self removed from members, keys cleared) instead of hard-deleting it,
    // so a fresh re-add invite must RE-JOIN by falling through to
    // re-materialization (group/members/key + myRole) rather than being
    // rejected as a duplicate. Detect the retained-removed shell via self no
    // longer being an active member — a voluntarily-left group is hard-deleted
    // (getGroup == null), so this uniquely identifies the retained case. A
    // genuinely-joined duplicate (self still a member) short-circuits as before.
    final selfIsActiveMember = selfPeerId == null || selfPeerId.isEmpty
        ? true
        : (await groupRepo.getMember(payload.groupId, selfPeerId)) != null;
    if (selfIsActiveMember) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_HANDLE_DUPLICATE',
        details: {
          'groupId': payload.groupId.length > 8
              ? payload.groupId.substring(0, 8)
              : payload.groupId,
        },
      );
      return (HandleGroupInviteResult.duplicateGroup, null);
    }
    if (existingGroup.selfRemovedAt == null || shellRepository == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_HANDLE_REJOIN_AUTHORITY_MISSING',
        details: {'groupId': payload.groupId},
      );
      return (HandleGroupInviteResult.invalidPayload, null);
    }
    isPostRemovalReentry = true;
    postRemovalGenerationFloor = existingGroup.selfRemovedAt!.toUtc();
    final membershipFloor = existingGroup.lastMembershipEventAt?.toUtc();
    if (membershipFloor != null &&
        membershipFloor.isAfter(postRemovalGenerationFloor)) {
      postRemovalGenerationFloor = membershipFloor;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_REJOIN_AFTER_REMOVAL',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
      },
    );
    // Fall through to the authenticated atomic re-entry phase.
  } else {
    // An absent row may still have a retained removal floor. Production and
    // accepted-invite tests must expose the capability so absence can never be
    // mistaken for a truly fresh group.
    if (shellRepository == null || selfPeerId == null || selfPeerId.isEmpty) {
      return (HandleGroupInviteResult.invalidPayload, null);
    }
    try {
      final floor = await shellRepository.loadSelfRemovedShellFreshnessFloor(
        payload.groupId,
      );
      isPostRemovalReentry = floor != null;
      postRemovalGenerationFloor = floor?.selfRemovedAt.toUtc();
    } catch (_) {
      return (HandleGroupInviteResult.invalidPayload, null);
    }
  }

  final config = payload.groupConfig;
  if (payload.groupKey.trim().isEmpty || payload.keyEpoch <= 0) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_INVALID_JOIN_MATERIAL',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
        'hasGroupKey': payload.groupKey.trim().isNotEmpty,
        'keyEpoch': payload.keyEpoch,
      },
    );
    return (HandleGroupInviteResult.invalidPayload, null);
  }

  final keyMaterialRejectReason = groupConfigMemberKeyMaterialRejectReason(
    config,
  );
  if (keyMaterialRejectReason != null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_INVALID_MEMBER_KEY_MATERIAL',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
        'reason': keyMaterialRejectReason,
      },
    );
    return (HandleGroupInviteResult.invalidPayload, null);
  }

  final groupName = config['name'] as String? ?? 'Unnamed Group';
  final groupTypeStr = config['groupType'] as String? ?? 'chat';
  final description = config['description'] as String?;
  final avatarBlobId = config['avatarBlobId'] as String?;
  final avatarMime = config['avatarMime'] as String?;
  final createdBy = config['createdBy'] as String? ?? payload.senderPeerId;
  final createdAtStr = config['createdAt'] as String?;
  final metadataUpdatedAtStr = config['metadataUpdatedAt'] as String?;
  final createdAt = createdAtStr != null
      ? DateTime.tryParse(createdAtStr) ?? DateTime.now().toUtc()
      : DateTime.now().toUtc();
  final metadataUpdatedAt = metadataUpdatedAtStr != null
      ? DateTime.tryParse(metadataUpdatedAtStr)?.toUtc()
      : null;
  final membershipWatermarkAt = _parseInviteMembershipWatermark(payload);
  final inviteIssuedAt = _parseInviteIssuedAt(payload);
  if (isPostRemovalReentry &&
      (membershipWatermarkAt == null || inviteIssuedAt == null)) {
    return (HandleGroupInviteResult.invalidPayload, null);
  }
  final acceptedMembershipWatermarkAt = isPostRemovalReentry
      ? _laterInstant(membershipWatermarkAt!, inviteIssuedAt!)
      : membershipWatermarkAt ?? inviteIssuedAt;

  // 6. Persist GroupModel with myRole = member
  final groupModel = GroupModel(
    id: payload.groupId,
    name: groupName,
    type: _parseGroupType(groupTypeStr),
    topicName: '/mknoon/group/${payload.groupId}',
    description: description,
    avatarBlobId: avatarBlobId,
    avatarMime: avatarMime,
    createdAt: createdAt,
    createdBy: createdBy,
    myRole: GroupRole.member,
    lastMetadataEventAt: metadataUpdatedAt,
    lastMembershipEventAt: acceptedMembershipWatermarkAt,
  );

  final membersList = config['members'] as List<dynamic>? ?? [];
  final materializedAt = DateTime.now().toUtc();
  final acceptedRoster = <GroupMember>[];
  for (final memberMap in membersList) {
    if (memberMap is! Map) {
      return (HandleGroupInviteResult.invalidPayload, null);
    }
    final member = GroupMember.fromConfigMap(
      groupId: payload.groupId,
      map: Map<String, dynamic>.from(memberMap),
      joinedAt: _acceptedMemberJoinedAt(
        Map<String, dynamic>.from(memberMap),
        membershipWatermarkAt: acceptedMembershipWatermarkAt,
        materializedAt: materializedAt,
      ),
    );
    acceptedRoster.add(member);
  }
  if (isPostRemovalReentry) {
    final acceptedSelf = acceptedRoster
        .where((member) => member.peerId == selfPeerId)
        .toList(growable: false);
    final generationFloor = postRemovalGenerationFloor;
    if (generationFloor == null ||
        acceptedSelf.length != 1 ||
        !acceptedSelf.single.joinedAt.toUtc().isAfter(generationFloor)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_ACCEPTED_REENTRY_SELF_GENERATION_REFUSED',
        details: {'groupId': payload.groupId},
      );
      return (HandleGroupInviteResult.invalidPayload, null);
    }
  }
  final keyInfo = GroupKeyInfo(
    groupId: payload.groupId,
    keyGeneration: payload.keyEpoch,
    encryptedKey: payload.groupKey,
    createdAt: DateTime.now().toUtc(),
  );

  if (isPostRemovalReentry) {
    final result = await _materializePostRemovalAcceptedInvite(
      payload: payload,
      groupRepo: groupRepo,
      shellRepository: shellRepository,
      bridge: bridge,
      group: groupModel,
      roster: acceptedRoster,
      key: keyInfo,
      selfPeerId: selfPeerId,
      validationNowUtc: validationNowUtc,
    );
    if (result.$2 != null) {
      for (final member in acceptedRoster) {
        if (groupMemberRegainedDeliverableKey(existing: null, saved: member)) {
          await triggerDeferredDistributionDrainForPeer(
            groupId: payload.groupId,
            peerId: member.peerId,
          );
        }
      }
      await _downloadAcceptedAvatarIfCurrent(
        payload: payload,
        groupRepo: groupRepo,
        bridge: bridge,
        downloadGroupAvatarFn: downloadGroupAvatarFn,
        metadataUpdatedAt: metadataUpdatedAt,
        avatarBlobId: avatarBlobId,
        avatarMime: avatarMime,
      );
    }
    return result;
  }

  // Plan 321: the incremental projection mirrors would expose the group
  // epoch-less for the whole roster loop (the iOS NSE drops epoch-less docs),
  // so on a capability-bearing repository the save scope runs with mirror
  // upserts suppressed and ONE complete context is published from committed
  // rows afterwards. Drains are collected during the loop and run after the
  // publish (the reentry precedent) so the save scope holds no await-driven
  // interleave surface beyond the persistence calls themselves.
  final projectionAtomicity = groupRepo is FreshJoinProjectionAtomicity
      ? groupRepo as FreshJoinProjectionAtomicity
      : null;
  final drainPeerIds = <String>[];

  Future<void> persistJoinAuthority() async {
    await groupRepo.saveGroup(groupModel);

    // 7. Persist members from config
    for (final member in acceptedRoster) {
      final priorMember = await groupRepo.getMember(
        payload.groupId,
        member.peerId,
      );
      await groupRepo.saveMember(member);
      // G-A: if materializing this accepted invite first lands a member's
      // usable ML-KEM key, drain any deferred key distribution owed to it.
      // Gated so a keyless member never burns a deferred-distribution attempt.
      if (groupMemberRegainedDeliverableKey(
        existing: priorMember,
        saved: member,
      )) {
        drainPeerIds.add(member.peerId);
      }
    }

    // 8. Persist GroupKeyInfo
    await groupRepo.saveKey(keyInfo);
  }

  if (projectionAtomicity != null) {
    await projectionAtomicity.runWithSuppressedGroupProjectionMirrors(
      payload.groupId,
      persistJoinAuthority,
    );
    // The join NEVER fails because of the projection (the 07-31
    // non-negotiable): failures defer to the next launch's authoritative
    // rebuild and are observable via the flow event.
    try {
      final published = await projectionAtomicity.projectCommittedFreshJoin(
        payload.groupId,
      );
      if (published) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_FRESH_JOIN_PROJECTION_PUBLISHED',
          details: {
            'groupId': payload.groupId.length > 8
                ? payload.groupId.substring(0, 8)
                : payload.groupId,
          },
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_FRESH_JOIN_PROJECTION_DEFERRED',
        details: {
          'groupId': payload.groupId.length > 8
              ? payload.groupId.substring(0, 8)
              : payload.groupId,
          'error': e.toString(),
        },
      );
    }
  } else {
    await persistJoinAuthority();
  }

  for (final peerId in drainPeerIds) {
    await triggerDeferredDistributionDrainForPeer(
      groupId: payload.groupId,
      peerId: peerId,
    );
  }

  await _downloadAcceptedAvatarIfCurrent(
    payload: payload,
    groupRepo: groupRepo,
    bridge: bridge,
    downloadGroupAvatarFn: downloadGroupAvatarFn,
    metadataUpdatedAt: metadataUpdatedAt,
    avatarBlobId: avatarBlobId,
    avatarMime: avatarMime,
  );

  // 9. Call bridge to join the group topic
  try {
    await callGroupJoinWithConfig(
      bridge,
      groupId: payload.groupId,
      groupConfig: config,
      groupKey: payload.groupKey,
      keyEpoch: payload.keyEpoch,
    );
  } on BridgeCommandException catch (e) {
    if (_isRepairableJoinMaterialError(e)) {
      await _rollbackMaterializedInviteState(
        groupRepo: groupRepo,
        groupId: payload.groupId,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_HANDLE_JOIN_MATERIAL_REPAIR_PENDING',
        details: {
          'groupId': payload.groupId.length > 8
              ? payload.groupId.substring(0, 8)
              : payload.groupId,
          'errorCode': e.errorCode,
        },
      );
      return (HandleGroupInviteResult.invalidPayload, null);
    }
    // Non-repairable bridge error (e.g. topic-subscribe failure): the group is
    // already materialized (key persisted above), so treat it as a TRANSIENT
    // join failure and enroll it in the bounded 088 rejoin retrier. The
    // retrier re-attempts the join and, after the attempt cap, surfaces a
    // "Couldn't join" badge — it never sits silently half-materialized. The
    // genuinely-fatal/malformed-config cases are already caught and rolled back
    // by the _isRepairableJoinMaterialError branch above.
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_BRIDGE_ERROR',
      details: {'error': e.toString()},
    );
    await _enrollTransientJoinFailureForRejoin(groupRepo, payload.groupId);
    return (HandleGroupInviteResult.bridgeError, payload.groupId);
  } on TimeoutException {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_BRIDGE_TIMEOUT',
      details: {
        'groupId': payload.groupId.length > 8
            ? payload.groupId.substring(0, 8)
            : payload.groupId,
      },
    );
    // Group is already persisted — enroll in the bounded rejoin retrier so the
    // join is re-attempted later instead of leaking half-materialized.
    await _enrollTransientJoinFailureForRejoin(groupRepo, payload.groupId);
    return (HandleGroupInviteResult.bridgeError, payload.groupId);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_HANDLE_BRIDGE_ERROR',
      details: {'error': e.toString()},
    );
    await _enrollTransientJoinFailureForRejoin(groupRepo, payload.groupId);
    return (HandleGroupInviteResult.bridgeError, payload.groupId);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_HANDLE_SUCCESS',
    details: {
      'groupId': payload.groupId.length > 8
          ? payload.groupId.substring(0, 8)
          : payload.groupId,
    },
  );
  return (HandleGroupInviteResult.success, payload.groupId);
}

Future<(HandleGroupInviteResult, String?)>
_materializePostRemovalAcceptedInvite({
  required GroupInvitePayload payload,
  required GroupRepository groupRepo,
  required SelfRemovedGroupShellRepository shellRepository,
  required Bridge bridge,
  required GroupModel group,
  required List<GroupMember> roster,
  required GroupKeyInfo key,
  required String selfPeerId,
  required DateTime Function()? validationNowUtc,
}) {
  return runGroupMembershipMutationLocked(
    groupId: payload.groupId,
    action: () async {
      final proof = payload.membershipFreshnessProof;
      final lockedValidationTime = (validationNowUtc?.call() ?? DateTime.now())
          .toUtc();
      if (!payload.isInvitePolicyValid(validationTime: lockedValidationTime) ||
          proof == null ||
          !proof.isFreshAt(lockedValidationTime)) {
        return (HandleGroupInviteResult.invalidPayload, null);
      }
      final watermarkRaw = proof.membershipWatermark.trim();
      final issuedAt = proof.issuedAt.toUtc();
      if (watermarkRaw.isEmpty ||
          DateTime.tryParse(watermarkRaw)?.toUtc() == null ||
          selfPeerId.trim().isEmpty) {
        return (HandleGroupInviteResult.invalidPayload, null);
      }

      SelfRemovedAcceptedReentryResult committed;
      try {
        committed = await shellRepository.commitAcceptedReentry(
          group: group,
          roster: roster,
          key: key,
          selfPeerId: selfPeerId,
          authorizationId: payload.id,
          signedMembershipWatermark: watermarkRaw,
          signedIssuedAt: issuedAt.toIso8601String(),
          bindingNonce: const Uuid().v4(),
        );
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INVITE_ACCEPTED_REENTRY_COMMIT_FAILED',
          details: {'groupId': payload.groupId, 'error': error.toString()},
        );
        return (HandleGroupInviteResult.invalidPayload, null);
      }
      if (!committed.committed) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INVITE_ACCEPTED_REENTRY_REFUSED',
          details: {
            'groupId': payload.groupId,
            'outcome': committed.outcome.name,
          },
        );
        return (HandleGroupInviteResult.invalidPayload, null);
      }

      try {
        await callGroupJoinWithConfig(
          bridge,
          groupId: payload.groupId,
          groupConfig: payload.groupConfig,
          groupKey: payload.groupKey,
          keyEpoch: payload.keyEpoch,
        );
      } on BridgeCommandException catch (error) {
        if (_isRepairableJoinMaterialError(error)) {
          final rollback = await shellRepository.rollbackAcceptedReentry(
            groupId: payload.groupId,
            selfPeerId: selfPeerId,
            authorizationId: payload.id,
          );
          if (rollback == SelfRemovedAcceptedRollbackOutcome.rolledBack) {
            return (HandleGroupInviteResult.invalidPayload, null);
          }
          // Exact rollback refused because newer authority won. Preserve that
          // state and surface a retryable error rather than generic-deleting it.
          await _enrollTransientJoinFailureForRejoin(
            groupRepo,
            payload.groupId,
          );
          return (HandleGroupInviteResult.bridgeError, payload.groupId);
        }
        await _enrollTransientJoinFailureForRejoin(groupRepo, payload.groupId);
        return (HandleGroupInviteResult.bridgeError, payload.groupId);
      } on TimeoutException {
        await _enrollTransientJoinFailureForRejoin(groupRepo, payload.groupId);
        return (HandleGroupInviteResult.bridgeError, payload.groupId);
      } catch (_) {
        await _enrollTransientJoinFailureForRejoin(groupRepo, payload.groupId);
        return (HandleGroupInviteResult.bridgeError, payload.groupId);
      }

      return (HandleGroupInviteResult.success, payload.groupId);
    },
  );
}

Future<void> _downloadAcceptedAvatarIfCurrent({
  required GroupInvitePayload payload,
  required GroupRepository groupRepo,
  required Bridge bridge,
  required DownloadGroupAvatarFn? downloadGroupAvatarFn,
  required DateTime? metadataUpdatedAt,
  required String? avatarBlobId,
  required String? avatarMime,
}) async {
  if (avatarBlobId == null || avatarMime == null) return;
  final avatarPath = await (downloadGroupAvatarFn ?? downloadGroupAvatar)(
    bridge: bridge,
    groupId: payload.groupId,
    blobId: avatarBlobId,
  );
  if (avatarPath == null) return;
  final refreshedGroup = await groupRepo.getGroup(payload.groupId);
  final refreshedWatermark = refreshedGroup?.lastMetadataEventAt?.toUtc();
  final inviteWatermark = metadataUpdatedAt?.toUtc();
  final inviteMetadataIsCurrent =
      refreshedWatermark == null ||
      inviteWatermark == null ||
      !inviteWatermark.isBefore(refreshedWatermark);
  if (refreshedGroup != null &&
      refreshedGroup.selfRemovedAt == null &&
      inviteMetadataIsCurrent &&
      refreshedGroup.avatarBlobId == avatarBlobId &&
      refreshedGroup.avatarMime == avatarMime) {
    await groupRepo.updateGroup(
      refreshedGroup.copyWith(avatarPath: avatarPath),
    );
  }
}

DateTime _laterInstant(DateTime first, DateTime second) =>
    first.isAfter(second) ? first.toUtc() : second.toUtc();

DateTime? _parseInviteMembershipWatermark(GroupInvitePayload payload) {
  final raw = payload.membershipFreshnessProof?.membershipWatermark;
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw)?.toUtc();
}

DateTime? _parseInviteIssuedAt(GroupInvitePayload payload) {
  return payload.membershipFreshnessProof?.issuedAt.toUtc() ??
      DateTime.tryParse(payload.timestamp)?.toUtc();
}

DateTime _acceptedMemberJoinedAt(
  Map<String, dynamic> member, {
  required DateTime? membershipWatermarkAt,
  required DateTime materializedAt,
}) {
  final rawJoinedAt = member['joinedAt'] ?? member['joined_at'];
  if (rawJoinedAt is String && rawJoinedAt.trim().isNotEmpty) {
    final parsed = DateTime.tryParse(rawJoinedAt)?.toUtc();
    if (parsed != null) {
      return parsed;
    }
  }
  return membershipWatermarkAt ?? materializedAt;
}

bool _isRepairableJoinMaterialError(BridgeCommandException error) {
  final code = error.errorCode.toUpperCase();
  const repairableCodes = {
    'INVALID_JOIN_MATERIAL',
    'STALE_JOIN_MATERIAL',
    'KEY_DECRYPT_FAILED',
    'GROUP_KEY_DECRYPT_FAILED',
    'WELCOME_DECRYPT_FAILED',
    'KEY_PACKAGE_DECRYPT_FAILED',
    'KEY_EPOCH_STALE',
  };
  if (repairableCodes.contains(code)) {
    return true;
  }

  final message = (error.errorMessage ?? '').toLowerCase();
  return message.contains('join material') ||
      message.contains('key material') ||
      message.contains('key package') ||
      message.contains('welcome') ||
      message.contains('decrypt') ||
      message.contains('stale key') ||
      message.contains('invalid key') ||
      message.contains('key epoch');
}

Future<void> _rollbackMaterializedInviteState({
  required GroupRepository groupRepo,
  required String groupId,
}) async {
  await groupRepo.removeAllKeys(groupId);
  await groupRepo.removeAllMembers(groupId);
  await groupRepo.deleteGroup(groupId);
}

/// Enrolls a half-materialized group (key persisted, topic-join failed
/// transiently) into the bounded 088 `group_rejoin_state` retrier so the next
/// rejoin pass re-attempts the join. Best-effort: any failure here must never
/// mask the originating bridgeError. The 30s base mirrors the rejoin use-case's
/// first backoff (whose constant is file-private there).
Future<void> _enrollTransientJoinFailureForRejoin(
  GroupRepository groupRepo,
  String groupId,
) async {
  try {
    await groupRepo.recordGroupRejoinFailure(
      groupId,
      nextEligibleAt: DateTime.now().toUtc().add(const Duration(seconds: 30)),
    );
  } catch (_) {
    // The retrier's independent periodic sweep is the backstop.
  }
}

GroupType _parseGroupType(String value) {
  switch (value) {
    case 'chat':
      return GroupType.chat;
    case 'announcement':
      return GroupType.announcement;
    case 'qa':
      return GroupType.qa;
    default:
      return GroupType.chat;
  }
}
