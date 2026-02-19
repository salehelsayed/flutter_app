import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/services/chat_message.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Routes incoming P2P messages to the correct listener based on message type.
///
/// Listens to [P2PService.messageStream], parses the content envelope,
/// and dispatches to typed streams that listeners subscribe to.
class IncomingMessageRouter {
  final P2PService _p2pService;
  StreamSubscription<ChatMessage>? _subscription;

  final _chatMessageController = StreamController<ChatMessage>.broadcast();
  final _contactRequestController = StreamController<ChatMessage>.broadcast();

  IncomingMessageRouter({required P2PService p2pService})
      : _p2pService = p2pService {
    _subscription = _p2pService.messageStream
        .where((msg) => msg.isIncoming)
        .listen(_routeMessage);
  }

  /// Stream of incoming chat messages (type == "chat").
  Stream<ChatMessage> get chatMessages => _chatMessageController.stream;

  /// Stream of incoming contact requests (type == "contact_request" or "contact_accept").
  Stream<ChatMessage> get contactRequests => _contactRequestController.stream;

  void _routeMessage(ChatMessage msg) {
    try {
      final envelope = jsonDecode(msg.content) as Map<String, dynamic>;
      final type = envelope['type'] as String?;
      final version = envelope['version'] as String?;

      emitFlowEvent(
        layer: 'FL',
        event: 'INCOMING_MSG_ROUTED',
        details: {'type': type, 'version': version, 'from': msg.from},
      );

      // v2 encrypted messages need decryption first — forward to chat handler
      // which is responsible for decryption
      if (version == '2') {
        _chatMessageController.add(msg);
        return;
      }

      switch (type) {
        case 'chat':
          _chatMessageController.add(msg);
          break;
        case 'contact_request':
        case 'contact_accept':
          _contactRequestController.add(msg);
          break;
        default:
          emitFlowEvent(
            layer: 'FL',
            event: 'INCOMING_MSG_UNKNOWN_TYPE',
            details: {'type': type, 'from': msg.from},
          );
      }
    } catch (e) {
      // If content is not JSON (e.g. raw text), treat as chat message
      _chatMessageController.add(msg);
    }
  }

  void dispose() {
    _subscription?.cancel();
    _chatMessageController.close();
    _contactRequestController.close();
  }
}
