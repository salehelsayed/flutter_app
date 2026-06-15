import 'dart:convert';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// 115 P2 origin-marker contract (shared with doc 114): delivery receipts are
/// minted ONLY for relay-inbox arrivals. `'direct:'`-staged replays are
/// confirmed by the live deferred direct ack and `'lan:'`-staged replays by
/// doc 114's committed LAN ack — both senders already hold 'delivered' at the
/// same durable bar, so receipts there would be redundant (and dangerous: a
/// quarantined replay must never flip a sender to 'delivered'). With no
/// staged entry id, the inbound transport tag decides: only `'inbox'`
/// arrivals are relay deliveries.
bool shouldMintDeliveryReceipt({String? stagedEntryId, String? transport}) {
  if (stagedEntryId != null) {
    return !stagedEntryId.startsWith('direct:') &&
        !stagedEntryId.startsWith('lan:');
  }
  return transport == 'inbox';
}

/// Sends a cross-device delivery receipt for [messageIds] to [targetPeerId].
///
/// Plaintext v1 by design (D-4): `'delivery_receipt'` is the one envelope
/// type old routers provably drop by name, making it the version-skew-safe
/// choice. Live send first, relay-inbox fallback second. NO retry loop on
/// failure (D-5): the sender's custody sweep and the duplicate-receive →
/// receipt re-send path are the repair loop.
///
/// Returns true when the receipt went out (acked live or stored).
Future<bool> sendDeliveryReceipt({
  required P2PService p2pService,
  required String targetPeerId,
  required List<String> messageIds,
}) async {
  final envelope = jsonEncode({
    'type': 'delivery_receipt',
    'version': '1',
    'payload': {
      'messageIds': messageIds,
      'ts': DateTime.now().toUtc().toIso8601String(),
    },
  });
  final idPreview = messageIds.isEmpty
      ? ''
      : (messageIds.first.length > 8
            ? messageIds.first.substring(0, 8)
            : messageIds.first);

  try {
    final result = await p2pService.sendMessageWithReply(
      targetPeerId,
      envelope,
    );
    final acked = result.acked ?? (result.reply?.isNotEmpty ?? false);
    if (result.sent && acked) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_SENT',
        details: {'via': 'live', 'count': messageIds.length, 'id': idPreview},
      );
      return true;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DELIVERY_RECEIPT_LIVE_SEND_ERROR',
      details: {'error': e.toString()},
    );
  }

  try {
    final stored = await p2pService.storeInInbox(targetPeerId, envelope);
    if (stored) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_SENT',
        details: {'via': 'inbox', 'count': messageIds.length, 'id': idPreview},
      );
      return true;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DELIVERY_RECEIPT_STORE_FAILED',
      details: {
        'count': messageIds.length,
        'id': idPreview,
        'error': e.toString(),
      },
    );
    return false;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'DELIVERY_RECEIPT_STORE_FAILED',
    details: {
      'count': messageIds.length,
      'id': idPreview,
      'reason': 'store_returned_false',
    },
  );
  return false;
}
