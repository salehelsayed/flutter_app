import 'dart:convert';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// 132 Phase 1 flag (LIVE by default since 2026-06-19, device-verified): when
/// true, the receiver mints a confirmatory delivery receipt for direct/LAN/
/// non-inbox durable arrivals too — NOT only relay-inbox ones. The original
/// design assumed direct/LAN sends already hold 'delivered' via their own live/
/// committed acks, but device evidence (iPhone↔Pixel over the prod relay)
/// confirmed those acks are LOST in practice: every live message logged
/// `DELIVERY_RECEIPT_MINT_SKIPPED reason=direct`, so a delivered-but-unacked row
/// stayed on the amber pending clock with no repair. A confirmatory receipt
/// converges such rows to 'delivered'. Safe because every mint site fires only
/// AFTER a durable persist (never for a quarantined/rejected replay) and is
/// idempotent on the sender (handleDeliveryReceipt early-returns on 'delivered').
/// Set false to fall back to the relay-inbox-only contract. See
/// Test-Flight-Improv/132-delivered-message-stuck-pending-clock-tdd-plan.md.
const bool kConfirmatoryDirectLanReceiptEnabled = true;

/// Why a mint was skipped — surfaced as `DELIVERY_RECEIPT_MINT_SKIPPED` so a
/// single device session names the exact dead-end behind a stuck pending clock.
enum DeliveryReceiptMintSkipReason { direct, lan, nonInbox }

class DeliveryReceiptMintDecision {
  final bool shouldMint;
  final DeliveryReceiptMintSkipReason? skipReason;
  const DeliveryReceiptMintDecision.mint() : shouldMint = true, skipReason = null;
  const DeliveryReceiptMintDecision.skip(DeliveryReceiptMintSkipReason reason)
    : shouldMint = false,
      skipReason = reason;
}

/// 115 P2 origin-marker contract (shared with doc 114): by default delivery
/// receipts are minted ONLY for relay-inbox arrivals. `'direct:'`-staged
/// replays are (notionally) confirmed by the live deferred direct ack and
/// `'lan:'`-staged replays by doc 114's committed LAN ack. With no staged entry
/// id, the inbound transport tag decides: only `'inbox'` arrivals are relay
/// deliveries. 132 Phase 1 can broaden this via
/// [kConfirmatoryDirectLanReceiptEnabled] (threadable for tests) once the
/// lost-ack dead-end is device-confirmed.
DeliveryReceiptMintDecision deliveryReceiptMintDecision({
  String? stagedEntryId,
  String? transport,
  bool confirmatoryDirectLanEnabled = kConfirmatoryDirectLanReceiptEnabled,
}) {
  if (stagedEntryId != null) {
    if (stagedEntryId.startsWith('direct:')) {
      return confirmatoryDirectLanEnabled
          ? const DeliveryReceiptMintDecision.mint()
          : const DeliveryReceiptMintDecision.skip(
              DeliveryReceiptMintSkipReason.direct,
            );
    }
    if (stagedEntryId.startsWith('lan:')) {
      return confirmatoryDirectLanEnabled
          ? const DeliveryReceiptMintDecision.mint()
          : const DeliveryReceiptMintDecision.skip(
              DeliveryReceiptMintSkipReason.lan,
            );
    }
    return const DeliveryReceiptMintDecision.mint();
  }
  if (transport == 'inbox') return const DeliveryReceiptMintDecision.mint();
  return confirmatoryDirectLanEnabled
      ? const DeliveryReceiptMintDecision.mint()
      : const DeliveryReceiptMintDecision.skip(
          DeliveryReceiptMintSkipReason.nonInbox,
        );
}

/// Back-compat boolean wrapper over [deliveryReceiptMintDecision]; truth table
/// is byte-identical to the historical gate when the flag is off.
bool shouldMintDeliveryReceipt({String? stagedEntryId, String? transport}) =>
    deliveryReceiptMintDecision(
      stagedEntryId: stagedEntryId,
      transport: transport,
    ).shouldMint;

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
