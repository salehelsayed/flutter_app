import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_pins_use_case.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PostPinListener {
  final Stream<ChatMessage> postPinUpdateStream;
  final Stream<ChatMessage> postPinRemoveStream;
  final PostRepository postRepo;
  final ContactRepository contactRepo;

  StreamSubscription<ChatMessage>? _updateSubscription;
  StreamSubscription<ChatMessage>? _removeSubscription;

  PostPinListener({
    required this.postPinUpdateStream,
    required this.postPinRemoveStream,
    required this.postRepo,
    required this.contactRepo,
  });

  void start() {
    if (_updateSubscription != null || _removeSubscription != null) {
      return;
    }
    _updateSubscription = postPinUpdateStream.listen(_onUpdateMessage);
    _removeSubscription = postPinRemoveStream.listen(_onRemoveMessage);
  }

  void stop() {
    _updateSubscription?.cancel();
    _removeSubscription?.cancel();
    _updateSubscription = null;
    _removeSubscription = null;
  }

  void dispose() {
    stop();
  }

  Future<void> _onUpdateMessage(ChatMessage message) async {
    try {
      await handleIncomingPostPinUpdate(
        message: message,
        postRepo: postRepo,
        contactRepo: contactRepo,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_PIN_UPDATE_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onRemoveMessage(ChatMessage message) async {
    try {
      await handleIncomingPostPinRemove(
        message: message,
        postRepo: postRepo,
        contactRepo: contactRepo,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_PIN_REMOVE_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
