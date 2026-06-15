import 'dart:convert';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Applies an incoming `'delivery_receipt'` envelope: flips matching
/// outgoing `'inboxed'` (or unconfirmed `'sent'`) rows to `'delivered'` and
/// clears the retained wire envelope.
///
/// This is G4 allowed minting site (a) — the ONLY place relay-inbox custody
/// becomes 'delivered'. Every forward transition rides
/// `conditionalTransitionStatus` (D-6) so a racing custody sweep can never be
/// downgraded by a stale snapshot and a late receipt can never resurrect a
/// row that already settled.
Future<void> handleDeliveryReceipt({
  required ChatMessage message,
  required MessageRepository messageRepo,
}) async {
  final fromPreview = message.from.length > 10
      ? message.from.substring(0, 10)
      : message.from;

  List<String> messageIds;
  try {
    final json = jsonDecode(message.content) as Map<String, dynamic>;
    if (json['type'] != 'delivery_receipt') return;
    final payload = json['payload'] as Map<String, dynamic>;
    messageIds = (payload['messageIds'] as List<dynamic>)
        .map((id) => id.toString())
        .toList();
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
    if (row.isIncoming || row.contactPeerId != message.from) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_FOREIGN_PEER',
        details: {'from': fromPreview, 'id': idPreview},
      );
      continue;
    }
    if (row.status == 'delivered') {
      // Idempotent re-apply (duplicate receipt) — nothing to do.
      continue;
    }

    var flipped = await messageRepo.conditionalTransitionStatus(
      messageId,
      fromStatus: 'inboxed',
      toStatus: 'delivered',
    );
    if (flipped == 0) {
      // An unconfirmed 'sent' row whose envelope reached the receiver via a
      // path that lost the ack — the receipt is still receiver confirmation.
      flipped = await messageRepo.conditionalTransitionStatus(
        messageId,
        fromStatus: 'sent',
        toStatus: 'delivered',
      );
    }
    if (flipped == 0) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_NO_TRANSITION',
        details: {'from': fromPreview, 'id': idPreview, 'status': row.status},
      );
      continue;
    }

    final delivered = await messageRepo.getMessage(messageId);
    if (delivered != null) {
      await messageRepo.saveMessage(
        normalizeOutgoingDeleteTombstoneVisibility(
          delivered.copyWith(wireEnvelope: null),
        ),
      );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'DELIVERY_RECEIPT_APPLIED',
      details: {'from': fromPreview, 'id': idPreview},
    );
  }
}
