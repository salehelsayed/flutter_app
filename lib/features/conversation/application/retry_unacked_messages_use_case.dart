import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/application/outbound_envelope_policy.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Retries outgoing messages stuck in 'sent' status by storing them
/// in the relay inbox using the persisted wire_envelope.
///
/// This is inbox-only -- no direct send, no re-encrypt, no media rebuild.
/// Once successfully stored, status moves to 'inboxed' and wire_envelope is
/// retained until a delivery receipt proves receiver-side delivery.
///
/// Returns the count of successfully updated messages.
Future<int> retryUnackedMessages({
  required MessageRepository messageRepo,
  required P2PService p2pService,
  // 186 (FU-185-A): the anti-race window. The periodic pass keeps the default
  // 60s (a genuinely in-flight recent send may still get its ack); the
  // reconnect pass passes Duration.zero so a freshly-queued offline message
  // converges as soon as we are back online instead of after the 5-min tick.
  Duration olderThan = const Duration(seconds: 60),
}) async {
  final retryStopwatch = Stopwatch()..start();
  void emitRetryTiming({
    required String outcome,
    required int total,
    required int delivered,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_UNACKED_MESSAGES_TIMING',
      details: {
        'elapsedMs': retryStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'total': total,
        'delivered': delivered,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_UNACKED_MESSAGES_START',
    details: {},
  );

  final unacked = await messageRepo.getUnackedOutgoingMessages(
    olderThan: olderThan,
  );

  if (unacked.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_UNACKED_MESSAGES_NONE',
      details: {},
    );
    emitRetryTiming(outcome: 'none', total: 0, delivered: 0);
    return 0;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_UNACKED_MESSAGES_FOUND',
    details: {'count': unacked.length},
  );

  var count = 0;
  for (final msg in unacked) {
    // Defensive: skip messages with null or empty wireEnvelope.
    // The SQL query should exclude these, but a corrupt row or future
    // query change could let one through.
    if (msg.wireEnvelope == null || msg.wireEnvelope!.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_MESSAGE_SKIP_NULL_ENVELOPE',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      continue;
    }

    if (isUnsafeLegacyOutboundEnvelope(msg.wireEnvelope!)) {
      await messageRepo.saveMessage(
        normalizeOutgoingDeleteTombstoneVisibility(
          msg.copyWith(status: 'failed'),
        ),
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_MESSAGE_SKIP_LEGACY_WIRE_ENVELOPE',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      continue;
    }
    try {
      final stored = await p2pService.storeInInbox(
        msg.contactPeerId,
        msg.wireEnvelope!,
      );
      if (stored) {
        await messageRepo.saveMessage(
          normalizeOutgoingDeleteTombstoneVisibility(
            msg.copyWith(status: 'inboxed', transport: 'inbox'),
          ),
        );
        count++;
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_UNACKED_MESSAGE_INBOXED',
          details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
        );
      }
      // Not stored -> leave as 'sent', retry on next online transition
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_MESSAGE_ERROR',
        details: {
          'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
          'error': e.toString(),
        },
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_UNACKED_MESSAGES_COMPLETE',
    details: {'total': unacked.length, 'delivered': count},
  );
  emitRetryTiming(outcome: 'complete', total: unacked.length, delivered: count);

  return count;
}
