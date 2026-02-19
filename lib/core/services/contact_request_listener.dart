import 'dart:async';

import 'package:flutter_app/core/services/chat_message.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Listens to routed contact request messages.
///
/// In a full implementation, this would handle:
/// - Saving contact requests to the database
/// - Extracting ML-KEM public keys from payloads
/// - Emitting feed items for the UI
///
/// For now, it passes messages through with flow event logging.
class ContactRequestListener {
  final IncomingMessageRouter _router;
  StreamSubscription<ChatMessage>? _subscription;

  final _requestController = StreamController<ChatMessage>.broadcast();

  ContactRequestListener({required IncomingMessageRouter router})
      : _router = router {
    _subscription = _router.contactRequests.listen(_handleContactRequest);
  }

  /// Stream of contact request messages for UI consumption.
  Stream<ChatMessage> get requests => _requestController.stream;

  void _handleContactRequest(ChatMessage msg) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQ_LISTENER_RECEIVED',
      details: {'from': msg.from, 'to': msg.to},
    );

    // TODO: Parse payload, save to contact_requests table
    // TODO: Extract ML-KEM public key from payload
    // TODO: Create ConnectionFeedItem for feed

    _requestController.add(msg);
  }

  void dispose() {
    _subscription?.cancel();
    _requestController.close();
  }
}
