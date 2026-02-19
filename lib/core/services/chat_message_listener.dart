import 'dart:async';

import 'package:flutter_app/core/services/chat_message.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Listens to routed chat messages and makes them available to the UI layer.
///
/// In a full implementation, this would handle:
/// - ML-KEM decryption for v2 envelopes
/// - Message deduplication
/// - Persistence to the messages table
///
/// For now, it passes messages through with flow event logging.
class ChatMessageListener {
  final IncomingMessageRouter _router;
  StreamSubscription<ChatMessage>? _subscription;

  final _messageController = StreamController<ChatMessage>.broadcast();

  ChatMessageListener({required IncomingMessageRouter router})
      : _router = router {
    _subscription = _router.chatMessages.listen(_handleChatMessage);
  }

  /// Stream of processed chat messages for UI consumption.
  Stream<ChatMessage> get messages => _messageController.stream;

  void _handleChatMessage(ChatMessage msg) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_LISTENER_RECEIVED',
      details: {'from': msg.from, 'to': msg.to},
    );

    // TODO: ML-KEM decryption for v2 envelopes
    // TODO: Message deduplication via messageExists(id)
    // TODO: Persist to messages table via messageRepo.saveMessage()

    _messageController.add(msg);
  }

  void dispose() {
    _subscription?.cancel();
    _messageController.close();
  }
}
