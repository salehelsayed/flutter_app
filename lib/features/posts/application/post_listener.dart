import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PostListener {
  final Stream<ChatMessage> postCreateStream;
  final PostRepository postRepo;
  final ContactRepository contactRepo;
  final Bridge? bridge;
  final Future<String?> Function()? getOwnMlKemSecretKey;
  final NotificationService? notificationService;

  StreamSubscription<ChatMessage>? _subscription;
  final _postController = StreamController<PostModel>.broadcast();

  PostListener({
    required this.postCreateStream,
    required this.postRepo,
    required this.contactRepo,
    this.bridge,
    this.getOwnMlKemSecretKey,
    this.notificationService,
  });

  Stream<PostModel> get incomingPostStream => _postController.stream;

  void start() {
    if (_subscription != null) return;
    _subscription = postCreateStream.listen(_onMessage);
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
    final ownMlKemSecretKey = getOwnMlKemSecretKey == null
        ? null
        : await getOwnMlKemSecretKey!();
    final (result, post) = await handleIncomingPost(
      message: message,
      postRepo: postRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      ownMlKemSecretKey: ownMlKemSecretKey,
    );
    if (result != HandleIncomingPostResult.postCreated || post == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_LISTENER_IGNORED',
        details: {'result': result.name},
      );
      return;
    }

    final sender = await contactRepo.getContact(post.senderPeerId);
    if (sender != null &&
        !sender.isArchived &&
        notificationService != null &&
        post.isIncoming) {
      await notificationService!.showNotification(
        title: post.authorUsername,
        body: post.text,
        payload: NotificationRouteTarget.post(post.id).toPayload(),
      );
    }
    _postController.add(post);
  }
}
