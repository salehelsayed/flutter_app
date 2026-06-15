import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Listens to routed `'delivery_receipt'` envelopes and applies them to the
/// sender-side message rows (115 P2 — the 'inboxed' → 'delivered' flip).
///
/// Mirrors the [ChatMessageListener] subscription pattern: subscribe on
/// [start], swallow per-message errors so one bad receipt never kills the
/// stream, clean up on [dispose].
class DeliveryReceiptListener {
  final Stream<ChatMessage> receiptStream;
  final MessageRepository messageRepo;
  StreamSubscription<ChatMessage>? _subscription;

  DeliveryReceiptListener({
    required this.receiptStream,
    required this.messageRepo,
  });

  void start() {
    if (_subscription != null) return;
    emitFlowEvent(
      layer: 'FL',
      event: 'DELIVERY_RECEIPT_LISTENER_START',
      details: {},
    );
    _subscription = receiptStream.listen(
      (message) async {
        if (!message.isIncoming) return;
        try {
          await handleDeliveryReceipt(
            message: message,
            messageRepo: messageRepo,
          );
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'DELIVERY_RECEIPT_LISTENER_ERROR',
            details: {'error': e.toString()},
          );
        }
      },
      onError: (Object error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'DELIVERY_RECEIPT_LISTENER_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  void stop() {
    emitFlowEvent(
      layer: 'FL',
      event: 'DELIVERY_RECEIPT_LISTENER_STOP',
      details: {},
    );
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
  }
}
