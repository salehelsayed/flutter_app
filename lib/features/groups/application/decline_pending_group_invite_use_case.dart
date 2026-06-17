import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_decline_ack_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';

enum DeclinePendingGroupInviteResult { success, notFound, expired }

/// Declines a pending invite locally (tombstone + delete). When the optional
/// transport deps are supplied, it ALSO best-effort notifies the inviter with
/// a signed decline-ack so their delivery-attempt row can flip to `declined`.
/// The ack send never throws and never changes the local result: for a
/// non-contact inviter (no resolvable ML-KEM key) it degrades to a
/// DECLINE_ACK_ENCRYPTION_SKIPPED no-op.
Future<DeclinePendingGroupInviteResult> declinePendingGroupInvite({
  required PendingGroupInviteRepository pendingInviteRepo,
  required String groupId,
  DateTime? now,
  P2PService? p2pService,
  Bridge? bridge,
  ContactRepository? contactRepo,
  String? declinerPeerId,
  String? declinerPrivateKey,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'PENDING_GROUP_INVITE_DECLINE_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final invite = await pendingInviteRepo.getPendingInvite(groupId);
  if (invite == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_DECLINE_NOT_FOUND',
      details: {'groupId': groupId},
    );
    return DeclinePendingGroupInviteResult.notFound;
  }

  final effectiveNow = (now ?? DateTime.now()).toUtc();
  await _recordDeclinedInviteTombstone(
    pendingInviteRepo: pendingInviteRepo,
    invite: invite,
    declinedAt: effectiveNow,
  );
  await pendingInviteRepo.deletePendingInvite(groupId);

  // Best-effort decline-ack to the inviter (never blocks or fails the local
  // decline above).
  await _maybeSendDeclineAck(
    invite: invite,
    now: effectiveNow,
    p2pService: p2pService,
    bridge: bridge,
    contactRepo: contactRepo,
    declinerPeerId: declinerPeerId,
    declinerPrivateKey: declinerPrivateKey,
  );

  final result = invite.isExpiredAt(effectiveNow)
      ? DeclinePendingGroupInviteResult.expired
      : DeclinePendingGroupInviteResult.success;
  emitFlowEvent(
    layer: 'FL',
    event: result == DeclinePendingGroupInviteResult.expired
        ? 'PENDING_GROUP_INVITE_DECLINE_EXPIRED'
        : 'PENDING_GROUP_INVITE_DECLINE_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );
  return result;
}

Future<void> _maybeSendDeclineAck({
  required PendingGroupInvite invite,
  required DateTime now,
  P2PService? p2pService,
  Bridge? bridge,
  ContactRepository? contactRepo,
  String? declinerPeerId,
  String? declinerPrivateKey,
}) async {
  // Local-only mode: callers that don't wire transport just skip the ack.
  if (p2pService == null ||
      bridge == null ||
      contactRepo == null ||
      declinerPeerId == null ||
      declinerPrivateKey == null) {
    return;
  }
  try {
    // Prefer the inviter ML-KEM key captured from the invite's freshness proof
    // (works for non-contact inviters, the common group case — G1); fall back
    // to a contact lookup for legacy invites that stored no key. Only when both
    // are absent does the send fn degrade to a DECLINE_ACK_ENCRYPTION_SKIPPED
    // no-op.
    final inviterMlKemPublicKey =
        (invite.mlKemPublicKey != null && invite.mlKemPublicKey!.trim().isNotEmpty)
        ? invite.mlKemPublicKey
        : (await contactRepo.getContact(invite.senderPeerId))?.mlKemPublicKey;
    await sendGroupInviteDeclineAck(
      p2pService: p2pService,
      bridge: bridge,
      inviteId: invite.inviteId,
      groupId: invite.groupId,
      inviterPeerId: invite.senderPeerId,
      inviterMlKemPublicKey: inviterMlKemPublicKey,
      declinerPeerId: declinerPeerId,
      declinerPrivateKey: declinerPrivateKey,
      now: now,
    );
  } catch (e) {
    // Fire-and-forget: the user's local decline already succeeded.
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_SEND_SUPPRESSED_ERROR',
      details: {'error': e.toString()},
    );
  }
}

Future<void> _recordDeclinedInviteTombstone({
  required PendingGroupInviteRepository pendingInviteRepo,
  required PendingGroupInvite invite,
  required DateTime declinedAt,
}) async {
  final declinedAtUtc = declinedAt.toUtc();
  final retentionExpiry = declinedAtUtc.add(pendingGroupInviteTtl);
  await pendingInviteRepo.saveConsumedInvite(
    GroupInviteConsumption(
      inviteId: invite.inviteId,
      groupId: invite.groupId,
      consumedAt: declinedAtUtc,
      expiresAt: invite.expiresAt.isAfter(retentionExpiry)
          ? invite.expiresAt
          : retentionExpiry,
    ),
  );
}
