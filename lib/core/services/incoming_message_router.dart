import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Routes incoming P2P messages to typed streams by message `type` field.
///
/// Replaces dual independent subscriptions with a single parse-and-dispatch.
/// Each listener subscribes to its typed stream instead of the raw P2P stream.
class IncomingMessageRouter {
  final P2PService p2pService;
  StreamSubscription<ChatMessage>? _subscription;

  final _contactRequestController = StreamController<ChatMessage>.broadcast();
  final _chatMessageController = StreamController<ChatMessage>.broadcast();
  final _unknownController = StreamController<ChatMessage>.broadcast();

  IncomingMessageRouter({required this.p2pService});

  /// Stream of incoming contact_request messages.
  Stream<ChatMessage> get contactRequestStream =>
      _contactRequestController.stream;

  /// Stream of incoming chat_message messages.
  Stream<ChatMessage> get chatMessageStream => _chatMessageController.stream;

  /// Stream of messages with unknown or unparseable types.
  Stream<ChatMessage> get unknownMessageStream => _unknownController.stream;

  /// Start routing incoming messages.
  void start() {
    if (_subscription != null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_ROUTER_START',
      details: {},
    );

    _subscription = p2pService.messageStream.listen(
      _route,
      onError: (error) {
        emitFlowEvent(layer: 'FL', event: 'MESSAGE_ROUTER_STREAM_ERROR', details: {'error': error.toString()});
      },
      onDone: () {
        emitFlowEvent(layer: 'FL', event: 'MESSAGE_ROUTER_STREAM_DONE', details: {});
      },
    );
  }

  void _route(ChatMessage message) {
    if (!message.isIncoming) return;

    try {
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case 'contact_request':
          _contactRequestController.add(message);
        case 'chat_message':
          _chatMessageController.add(message);
        default:
          emitFlowEvent(
            layer: 'FL',
            event: 'MESSAGE_ROUTER_UNKNOWN_TYPE',
            details: {'type': type},
          );
          _unknownController.add(message);
      }
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_ROUTER_PARSE_ERROR',
        details: {'from': message.from},
      );
      _unknownController.add(message);
    }
  }

  /// Stop routing and clean up resources.
  void stop() {
    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_ROUTER_STOP',
      details: {},
    );

    _subscription?.cancel();
    _subscription = null;
  }

  /// Dispose of the router and close all streams.
  void dispose() {
    stop();
    _contactRequestController.close();
    _chatMessageController.close();
    _unknownController.close();
  }
}
