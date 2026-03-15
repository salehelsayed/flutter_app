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
  final _profileUpdateController = StreamController<ChatMessage>.broadcast();
  final _reactionController = StreamController<ChatMessage>.broadcast();
  final _groupInviteController = StreamController<ChatMessage>.broadcast();
  final _groupKeyUpdateController = StreamController<ChatMessage>.broadcast();
  final _introductionController = StreamController<ChatMessage>.broadcast();
  final _postCreateController = StreamController<ChatMessage>.broadcast();
  final _unknownController = StreamController<ChatMessage>.broadcast();

  IncomingMessageRouter({required this.p2pService});

  /// Stream of incoming contact_request messages.
  Stream<ChatMessage> get contactRequestStream =>
      _contactRequestController.stream;

  /// Stream of incoming chat_message messages.
  Stream<ChatMessage> get chatMessageStream => _chatMessageController.stream;

  /// Stream of incoming profile_update messages.
  Stream<ChatMessage> get profileUpdateStream =>
      _profileUpdateController.stream;

  /// Stream of incoming message_reaction messages.
  Stream<ChatMessage> get reactionStream => _reactionController.stream;

  /// Stream of incoming group_invite messages.
  Stream<ChatMessage> get groupInviteStream => _groupInviteController.stream;

  /// Stream of incoming group_key_update messages.
  Stream<ChatMessage> get groupKeyUpdateStream =>
      _groupKeyUpdateController.stream;

  /// Stream of incoming introduction messages.
  Stream<ChatMessage> get introductionStream => _introductionController.stream;

  /// Stream of incoming post_create messages.
  Stream<ChatMessage> get postCreateStream => _postCreateController.stream;

  /// Stream of messages with unknown or unparseable types.
  Stream<ChatMessage> get unknownMessageStream => _unknownController.stream;

  /// Start routing incoming messages.
  void start() {
    if (_subscription != null) return;

    emitFlowEvent(layer: 'FL', event: 'MESSAGE_ROUTER_START', details: {});

    _subscription = p2pService.messageStream.listen(
      _route,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'MESSAGE_ROUTER_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'MESSAGE_ROUTER_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  void _route(ChatMessage message) {
    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_ROUTER_RECEIVED',
      details: {
        'from': message.from.length > 10
            ? message.from.substring(0, 10)
            : message.from,
        'isIncoming': message.isIncoming,
        'contentLength': message.content.length,
      },
    );

    if (!message.isIncoming) return;

    try {
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final type = json['type'] as String?;
      final version = json['version'] as String?;

      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_ROUTER_ROUTING',
        details: {
          'type': type,
          'version': version,
          'from': message.from.length > 10
              ? message.from.substring(0, 10)
              : message.from,
        },
      );

      switch (type) {
        case 'contact_request':
          _contactRequestController.add(message);
        case 'chat_message':
          _chatMessageController.add(message);
        case 'profile_update':
          _profileUpdateController.add(message);
        case 'message_reaction':
          _reactionController.add(message);
        case 'group_invite':
          emitFlowEvent(
            layer: 'FL',
            event: 'MESSAGE_ROUTER_GROUP_INVITE_DISPATCHED',
            details: {
              'from': message.from.length > 10
                  ? message.from.substring(0, 10)
                  : message.from,
              'hasListeners': _groupInviteController.hasListener,
            },
          );
          _groupInviteController.add(message);
        case 'group_key_update':
          _groupKeyUpdateController.add(message);
        case 'introduction':
          _introductionController.add(message);
        case 'post_create':
          _postCreateController.add(message);
        case 'delivery_receipt':
          // Legacy envelope type kept for backward compatibility.
          // Delivery status is now sender-side inbox/direct semantics only.
          return;
        default:
          emitFlowEvent(
            layer: 'FL',
            event: 'MESSAGE_ROUTER_UNKNOWN_TYPE',
            details: {'type': type},
          );
          _unknownController.add(message);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_ROUTER_PARSE_ERROR',
        details: {
          'from': message.from,
          'error': e.toString(),
          'contentPreview': message.content.length > 100
              ? message.content.substring(0, 100)
              : message.content,
        },
      );
      _unknownController.add(message);
    }
  }

  /// Stop routing and clean up resources.
  void stop() {
    emitFlowEvent(layer: 'FL', event: 'MESSAGE_ROUTER_STOP', details: {});

    _subscription?.cancel();
    _subscription = null;
  }

  /// Dispose of the router and close all streams.
  void dispose() {
    stop();
    _contactRequestController.close();
    _chatMessageController.close();
    _profileUpdateController.close();
    _reactionController.close();
    _groupInviteController.close();
    _groupKeyUpdateController.close();
    _introductionController.close();
    _postCreateController.close();
    _unknownController.close();
  }
}
