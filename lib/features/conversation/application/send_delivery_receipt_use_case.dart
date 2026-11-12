import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/features/conversation/domain/models/delivery_receipt_outbox_entry.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/delivery_receipt_outbox_repository.dart';

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
/// Set false to fall back to the relay-inbox-only contract.
const bool kConfirmatoryDirectLanReceiptEnabled = true;

/// Why a mint was skipped — surfaced as `DELIVERY_RECEIPT_MINT_SKIPPED` so a
/// single device session names the exact dead-end behind a stuck pending clock.
enum DeliveryReceiptMintSkipReason { direct, lan, nonInbox }

class DeliveryReceiptMintDecision {
  final bool shouldMint;
  final DeliveryReceiptMintSkipReason? skipReason;
  const DeliveryReceiptMintDecision.mint()
    : shouldMint = true,
      skipReason = null;
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
/// choice. Live send first, relay-inbox fallback second. This compatibility
/// entry point attempts once; production uses [DeliveryReceiptOutbox] to retain
/// the exact envelope before transport and retry through the existing lifecycle.
///
/// Returns true when the receipt went out (acked live or stored).
Future<bool> sendDeliveryReceipt({
  required P2PService p2pService,
  required String targetPeerId,
  required List<String> messageIds,
  Map<String, String>? mutationEventIds,
}) => _sendDeliveryReceiptEnvelope(
  p2pService: p2pService,
  targetPeerId: targetPeerId,
  messageIds: messageIds,
  envelope: _buildDeliveryReceiptEnvelope(
    messageIds: messageIds,
    mutationEventIds: mutationEventIds,
    now: DateTime.now(),
  ),
);

String _buildDeliveryReceiptEnvelope({
  required List<String> messageIds,
  Map<String, String>? mutationEventIds,
  required DateTime now,
}) {
  final messageIdSet = messageIds.toSet();
  final filteredMutationEventIds = <String, String>{};
  if (mutationEventIds != null) {
    for (final entry in mutationEventIds.entries) {
      final messageId = entry.key.trim();
      final eventId = entry.value.trim();
      if (messageId.isNotEmpty &&
          eventId.isNotEmpty &&
          messageIdSet.contains(messageId)) {
        filteredMutationEventIds[messageId] = eventId;
      }
    }
  }
  return jsonEncode({
    'type': 'delivery_receipt',
    'version': '1',
    'payload': {
      'messageIds': messageIds,
      if (filteredMutationEventIds.isNotEmpty)
        'mutationEventIds': filteredMutationEventIds,
      'ts': now.toUtc().toIso8601String(),
    },
  });
}

Future<bool> _sendDeliveryReceiptEnvelope({
  required P2PService p2pService,
  required String targetPeerId,
  required List<String> messageIds,
  required String envelope,
}) async {
  AppDiagnostics? diagnostics;
  String? trace;
  try {
    final current = AppDiagnostics.instance;
    diagnostics = current;
    trace = current.currentTraceForFeature('message');
  } catch (_) {
    // Receipt transport remains independent of optional diagnostic state.
  }
  void recordOutcome(String outcome, {bool acknowledged = false}) {
    if (trace == null) return;
    try {
      diagnostics?.record(
        feature: 'message',
        stage: 'receipt',
        outcome: outcome,
        reason: outcome == 'failed' ? 'send_failed' : 'none',
        traceId: trace,
        values: {'direction': 'incoming', 'acknowledged': acknowledged},
      );
    } catch (_) {
      // Recording cannot change ACK handling, inbox fallback, or the result.
    }
  }

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
      recordOutcome('ok', acknowledged: true);
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
      recordOutcome('pending');
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
    recordOutcome('failed');
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
  recordOutcome('failed');
  return false;
}

/// Account-scoped receipt owner shared by minting and lifecycle retry triggers.
/// Queuing never means sent: only the unchanged live ACK/store result does.
class DeliveryReceiptOutbox {
  DeliveryReceiptOutbox({
    required this.repository,
    required this.p2pService,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final DeliveryReceiptOutboxRepository repository;
  final P2PService Function() p2pService;
  final DateTime Function() _now;
  Future<int>? _draining;
  final _attempting = <String>{};

  Future<bool> send({
    required String targetPeerId,
    required List<String> messageIds,
    Map<String, String>? mutationEventIds,
  }) async {
    try {
      final now = _now();
      final nowMs = now.millisecondsSinceEpoch;
      final envelope = _buildDeliveryReceiptEnvelope(
        messageIds: messageIds,
        mutationEventIds: mutationEventIds,
        now: now,
      );
      final payload = (jsonDecode(envelope) as Map)['payload'] as Map;
      final mutations = payload['mutationEventIds'] as Map? ?? const {};
      final mutationKeys = mutations.keys.cast<String>().toList()..sort();
      // Dedupe only the same pending receipt. Keep its original bytes, ts,
      // expiry and backoff; a later generation/recipient is a different key.
      final key = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                targetPeerId,
                messageIds,
                {for (final id in mutationKeys) id: mutations[id]},
              ]),
            ),
          )
          .toString();
      await repository.deleteExpired(nowMs: nowMs);
      final entry = await repository.stage(
        DeliveryReceiptOutboxEntry(
          receiptKey: key,
          recipientPeerId: targetPeerId,
          receiptPayload: envelope,
          createdAtMs: nowMs,
          expiresAtMs: now.add(const Duration(days: 7)).millisecondsSinceEpoch,
          nextAttemptAtMs: nowMs,
          attemptCount: 0,
        ),
      );
      return _attempt(entry);
    } catch (error) {
      _recordQueueError(error);
      return false;
    }
  }

  /// Startup, online, restored-network, periodic and resume share this flight.
  Future<int> drain() {
    final active = _draining;
    if (active != null) return active;
    late final Future<int> attempt;
    attempt = _drain().whenComplete(() {
      if (identical(_draining, attempt)) _draining = null;
    });
    _draining = attempt;
    return attempt;
  }

  Future<int> _drain() async {
    try {
      final nowMs = _now().millisecondsSinceEpoch;
      await repository.deleteExpired(nowMs: nowMs);
      final entries = await repository.loadDue(nowMs: nowMs);
      var accepted = 0;
      for (final entry in entries) {
        if (await _attempt(entry)) accepted++;
      }
      return accepted;
    } catch (error) {
      _recordQueueError(error);
      return 0;
    }
  }

  Future<bool> _attempt(DeliveryReceiptOutboxEntry entry) async {
    if (!_attempting.add(entry.receiptKey)) return false;
    try {
      final nowMs = _now().millisecondsSinceEpoch;
      final delayMs = (5000 * (1 << entry.attemptCount.clamp(0, 8))).clamp(
        5000,
        15 * 60 * 1000,
      );
      final claimed = await repository.claimAttempt(
        expected: entry,
        nowMs: nowMs,
        nextAttemptAtMs: nowMs + delayMs,
      );
      if (claimed == null) return false;
      final payload =
          (jsonDecode(claimed.receiptPayload) as Map)['payload'] as Map;
      final accepted = await _sendDeliveryReceiptEnvelope(
        p2pService: p2pService(),
        targetPeerId: claimed.recipientPeerId,
        messageIds: (payload['messageIds'] as List).cast<String>(),
        envelope: claimed.receiptPayload,
      );
      if (accepted) {
        try {
          await repository.deleteIfExact(claimed);
        } catch (error) {
          // Transport acceptance is still true. Failed local cleanup retains
          // an idempotent receipt until a later accepted retry or its expiry.
          _recordQueueError(error);
        }
      }
      return accepted;
    } catch (error) {
      _recordQueueError(error);
      return false;
    } finally {
      _attempting.remove(entry.receiptKey);
    }
  }

  void _recordQueueError(Object error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DELIVERY_RECEIPT_OUTBOX_ERROR',
      details: {'errorType': error.runtimeType.toString()},
    );
  }
}
