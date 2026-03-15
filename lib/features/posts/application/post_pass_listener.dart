import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_passed_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PostPassListener {
  final Stream<ChatMessage> postPassStream;
  final PostRepository postRepo;
  final ContactRepository contactRepo;

  StreamSubscription<ChatMessage>? _subscription;
  final _postController = StreamController<PostModel>.broadcast();

  PostPassListener({
    required this.postPassStream,
    required this.postRepo,
    required this.contactRepo,
  });

  Stream<PostModel> get incomingPostPassStream => _postController.stream;

  void start() {
    if (_subscription != null) {
      return;
    }
    _subscription = postPassStream.listen(_onMessage);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
    _postController.close();
  }

  Future<void> _onMessage(ChatMessage message) async {
    try {
      final (result, post) = await handleIncomingPassedPost(
        message: message,
        postRepo: postRepo,
        contactRepo: contactRepo,
      );
      if (result == HandleIncomingPassedPostResult.passAccepted &&
          post != null) {
        _postController.add(post);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_PASS_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
