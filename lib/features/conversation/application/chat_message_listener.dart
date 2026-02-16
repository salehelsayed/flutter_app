import 'dart:async';

import 'package:flutter_app/core/bridge/js_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Listener service that monitors P2P messages for chat messages.
///
/// Subscribes to a typed chat message stream (from IncomingMessageRouter),
/// calls handleIncomingChatMessage, and broadcasts persisted
/// ConversationMessages to the UI layer.
class ChatMessageListener {
  final Stream<ChatMessage> chatMessageStream;
  final MessageRepository messageRepo;
  final ContactRepository contactRepo;
  final JsBridge? bridge;
  final Future<String?> Function()? getOwnMlKemSecretKey;

  StreamSubscription<ChatMessage>? _subscription;
  final _messageController = StreamController<ConversationMessage>.broadcast();
  final _contactUpdatedController = StreamController<ContactModel>.broadcast();

  ChatMessageListener({
    required this.chatMessageStream,
    required this.messageRepo,
    required this.contactRepo,
    this.bridge,
    this.getOwnMlKemSecretKey,
  });

  /// Stream of new incoming chat messages for the UI to listen to.
  Stream<ConversationMessage> get incomingMessageStream =>
      _messageController.stream;

  /// Stream of contacts whose username was updated from an incoming message.
  Stream<ContactModel> get contactUpdatedStream =>
      _contactUpdatedController.stream;

  /// Starts listening for incoming P2P messages.
  void start() {
    if (_subscription != null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_LISTENER_START',
      details: {},
    );

    _subscription = chatMessageStream.listen(_onMessage);
  }

  /// Stops listening and cleans up resources.
  void stop() {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_LISTENER_STOP',
      details: {},
    );

    _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    stop();
    _messageController.close();
    _contactUpdatedController.close();
  }

  Future<void> _onMessage(ChatMessage message) async {
    try {
      final ownSecretKey = getOwnMlKemSecretKey != null
          ? await getOwnMlKemSecretKey!()
          : null;

      final (result, conversationMessage, updatedContact) =
          await handleIncomingChatMessage(
        message: message,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: ownSecretKey,
      );

      if (updatedContact != null) {
        _contactUpdatedController.add(updatedContact);
      }

      if (result == HandleChatMessageResult.chatMessage &&
          conversationMessage != null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_LISTENER_NEW_MESSAGE',
          details: {
            'id': conversationMessage.id.length > 8
                ? conversationMessage.id.substring(0, 8)
                : conversationMessage.id,
            'from': conversationMessage.senderPeerId.length > 10
                ? conversationMessage.senderPeerId.substring(0, 10)
                : conversationMessage.senderPeerId,
          },
        );

        _messageController.add(conversationMessage);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
