import 'dart:convert';

import 'package:flutter_app/core/database/direct_inbox_event_envelope.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/application/outgoing_direct_private_transport_settlement.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

const Set<String> _trustedDeliveryReceiptTransports = <String>{
  'direct',
  'relay',
  'inbox',
};

/// Applies an incoming `'delivery_receipt'` envelope: flips matching
/// outgoing staged `'sending'`, `'inboxed'`, unconfirmed `'sent'`, or (185)
/// `'failed'` rows to `'delivered'` and clears the retained wire envelope.
///
/// This is G4 allowed minting site (a) — the ONLY place relay-inbox custody
/// becomes 'delivered'. Every ordinary transition uses one atomic typed
/// settlement so a racing custody sweep cannot downgrade it from a stale
/// snapshot. Only `'delivered'` is terminal-settled (the idempotent early-out
/// below); an authenticated-ingress, peer-bound receipt MAY intentionally lift
/// a `'failed'` row. Ingress provenance and row-peer correlation are separate,
/// fail-closed guards.
Future<void> handleDeliveryReceipt({
  required ChatMessage message,
  required MessageRepository messageRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  // 361: shared physical->logical reverse authority for receipts that arrive
  // from a linked origin transport. Null keeps incumbent strict equality.
  DirectTransportAuthorityResolver? transportAuthority,
}) async {
  if (!_trustedDeliveryReceiptTransports.contains(message.transport)) return;

  final fromPreview = message.from.length > 10
      ? message.from.substring(0, 10)
      : message.from;

  List<String> messageIds;
  var mutationEventIds = const <String, String>{};
  try {
    final json = jsonDecode(message.content) as Map<String, dynamic>;
    if (json['type'] != 'delivery_receipt') return;
    final payload = json['payload'] as Map<String, dynamic>;
    messageIds = (payload['messageIds'] as List<dynamic>)
        .map((id) => id.toString())
        .toList();
    final validMessageIds = messageIds.toSet();
    final rawMutationEventIds = payload['mutationEventIds'];
    if (rawMutationEventIds is Map) {
      mutationEventIds = <String, String>{
        for (final entry in rawMutationEventIds.entries)
          if (entry.key is String &&
              entry.value is String &&
              (entry.key as String).trim().isNotEmpty &&
              (entry.value as String).trim().isNotEmpty &&
              validMessageIds.contains((entry.key as String).trim()))
            (entry.key as String).trim(): (entry.value as String).trim(),
      };
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DELIVERY_RECEIPT_PARSE_ERROR',
      details: {'from': fromPreview, 'error': e.toString()},
    );
    return;
  }

  for (final messageId in messageIds) {
    final idPreview = messageId.length > 8
        ? messageId.substring(0, 8)
        : messageId;
    final row = await messageRepo.getMessage(messageId);
    if (row == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_UNMATCHED',
        details: {'from': fromPreview, 'id': idPreview},
      );
      continue;
    }
    var foreignPeer = row.isIncoming;
    if (!foreignPeer && row.contactPeerId != message.from) {
      // 361: an authenticated linked origin transport is an account-level
      // delivery assertion for its LOGICAL contact; anything unresolvable is
      // still a foreign peer.
      if (transportAuthority == null) {
        foreignPeer = true;
      } else {
        final resolution = await transportAuthority
            .resolveDirectTransportAuthority(message.from);
        foreignPeer =
            !resolution.authorized ||
            resolution.contactAccountPeerId != row.contactPeerId;
      }
    }
    if (foreignPeer) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_FOREIGN_PEER',
        details: {'from': fromPreview, 'id': idPreview},
      );
      continue;
    }
    final classified = row.wireEnvelope == null
        ? null
        : classifyDirectInboxEventEnvelope(row.wireEnvelope!);
    if (classified?.isMutation == true &&
        mutationEventIds[messageId] != classified!.eventId) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_MUTATION_EVENT_MISMATCH',
        details: {'from': fromPreview, 'id': idPreview},
      );
      continue;
    }
    // 361: a fanout-marked row settles ONLY against its exact CURRENT
    // generation — the message ID for a fresh initial, the current event ID
    // for a mutation. Stale, prior and future event receipts are zero-effect.
    final fanoutGeneration = row.directEventFanoutGenerationId;
    if (fanoutGeneration != null &&
        (mutationEventIds[messageId] ?? messageId) != fanoutGeneration) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_MUTATION_EVENT_MISMATCH',
        details: {'from': fromPreview, 'id': idPreview},
      );
      continue;
    }
    if (row.status == 'delivered') {
      // Idempotent re-apply (duplicate receipt) — nothing to do.
      continue;
    }

    if (_isOutgoingOneMoreLookPrivate(row)) {
      final expectedEnvelope = row.wireEnvelope;
      var accepted = false;
      if (expectedEnvelope != null && expectedEnvelope.isNotEmpty) {
        if (row.isDeleted) {
          if (messageRepo is DirectPrivateDeleteForEveryoneRepository) {
            final target = normalizeOutgoingDeleteTombstoneVisibility(
              row.copyWith(status: 'delivered', wireEnvelope: null),
            );
            accepted =
                await (messageRepo as DirectPrivateDeleteForEveryoneRepository)
                    .settlePrivateDeleteForEveryoneTombstone(
                      tombstone: target,
                      expectedEnvelope: expectedEnvelope,
                    ) !=
                null;
          }
        } else {
          List<MediaAttachment>? attachments;
          try {
            attachments = await mediaAttachmentRepo?.getAttachmentsForMessage(
              row.id,
              owner: MediaOwnerLane.direct,
            );
          } catch (_) {
            attachments = null;
          }
          final outcome =
              await settleOutgoingDirectPrivateTransportUnderLifecycleLock(
                messageRepository: messageRepo,
                mediaAttachmentRepository: mediaAttachmentRepo,
                attachments: attachments,
                messageId: row.id,
                expectedEnvelope: expectedEnvelope,
                status: 'delivered',
                transport: row.transport,
                relayExpiresAt: null,
              );
          accepted = outcome.accepted;
        }
      }
      if (!accepted) {
        emitFlowEvent(
          layer: 'FL',
          event: 'DELIVERY_RECEIPT_NO_TRANSITION',
          details: {'from': fromPreview, 'id': idPreview, 'status': row.status},
        );
        continue;
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_APPLIED',
        details: {'from': fromPreview, 'id': idPreview},
      );
      continue;
    }

    if (messageRepo is! OutgoingTransportMutationRepository) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_NO_TRANSITION',
        details: {'from': fromPreview, 'id': idPreview, 'status': row.status},
      );
      continue;
    }
    final mutationRepo = messageRepo as OutgoingTransportMutationRepository;
    // 361: a fanout-marked row or a linked-origin receipt settles through the
    // generation- and authority-aware owner; everything else keeps the
    // incumbent settlement byte-identically.
    final needsFanoutSettlement =
        fanoutGeneration != null || row.contactPeerId != message.from;
    final fanoutSettlementRepo =
        messageRepo is OutgoingDirectFanoutReceiptSettlementRepository
        ? messageRepo as OutgoingDirectFanoutReceiptSettlementRepository
        : null;
    if (needsFanoutSettlement &&
        (fanoutSettlementRepo == null ||
            !fanoutSettlementRepo.supportsDirectFanoutReceiptSettlement)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_NO_TRANSITION',
        details: {'from': fromPreview, 'id': idPreview, 'status': row.status},
      );
      continue;
    }
    bool settledChanged;
    if (needsFanoutSettlement) {
      final outcome = await fanoutSettlementRepo!
          .settleOutgoingOrdinaryTransportWithFanoutAuthority(
            messageId: row.id,
            expectedContactPeerId: row.contactPeerId,
            expectedEnvelope: row.wireEnvelope,
            status: 'delivered',
            transport: row.transport,
            relayExpiresAt: null,
            mode: OutgoingOrdinarySettlementMode.receipt,
            isDeleteTombstone: row.isDeleted,
            expectedDirectEventFanoutGenerationId:
                mutationEventIds[messageId] ?? messageId,
            authenticatedTransportPeerId: message.from,
          );
      settledChanged = outcome.changed;
    } else {
      final settled = row.isDeleted
          ? await mutationRepo.settleOutgoingOrdinaryDeleteTombstone(
              messageId: row.id,
              expectedContactPeerId: message.from,
              expectedEnvelope: row.wireEnvelope,
              status: 'delivered',
              transport: row.transport,
              relayExpiresAt: null,
              mode: OutgoingOrdinarySettlementMode.receipt,
            )
          : await mutationRepo.settleOutgoingOrdinaryTransport(
              messageId: row.id,
              expectedContactPeerId: message.from,
              expectedEnvelope: row.wireEnvelope,
              status: 'delivered',
              transport: row.transport,
              relayExpiresAt: null,
              mode: OutgoingOrdinarySettlementMode.receipt,
            );
      settledChanged = settled.changed;
    }
    if (!settledChanged) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_NO_TRANSITION',
        details: {'from': fromPreview, 'id': idPreview, 'status': row.status},
      );
      continue;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'DELIVERY_RECEIPT_APPLIED',
      details: {'from': fromPreview, 'id': idPreview},
    );
  }
}

bool _isOutgoingOneMoreLookPrivate(ConversationMessage message) =>
    !message.isIncoming &&
    message.privateMediaPolicy.version == 1 &&
    (message.privateMediaMode == PrivateMediaMode.protected ||
        message.privateMediaMode == PrivateMediaMode.viewOnce);
