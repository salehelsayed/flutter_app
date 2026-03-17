import 'dart:async';

import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_comment_use_case.dart';
import 'package:flutter_app/features/posts/application/reconcile_pending_post_child_events_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PostCommentListener {
  final Stream<ChatMessage> postCommentStream;
  final PostRepository postRepo;
  final ContactRepository contactRepo;
  final NotificationService? notificationService;

  StreamSubscription<ChatMessage>? _subscription;
  final _commentController = StreamController<PostCommentModel>.broadcast();
  Future<void> _pendingMessageHandling = Future<void>.value();

  PostCommentListener({
    required this.postCommentStream,
    required this.postRepo,
    required this.contactRepo,
    this.notificationService,
  });

  Stream<PostCommentModel> get incomingCommentStream =>
      _commentController.stream;

  void start() {
    if (_subscription != null) {
      return;
    }
    _subscription = postCommentStream.listen((message) {
      // Serialize comment handling so duplicate deliveries cannot race past the
      // persistence dedupe check and emit the same comment twice.
      _pendingMessageHandling = _pendingMessageHandling.then(
        (_) => _onMessage(message),
      );
    });
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
    _commentController.close();
  }

  Future<void> _onMessage(ChatMessage message) async {
    try {
      final (result, comment) = await handleIncomingPostComment(
        message: message,
        postRepo: postRepo,
        contactRepo: contactRepo,
      );
      if (result == HandleIncomingPostCommentResult.commentCreated &&
          comment != null) {
        await reconcilePendingPostChildEvents(
          postId: comment.postId,
          postRepo: postRepo,
          contactRepo: contactRepo,
        );
        final post = await postRepo.getPost(comment.postId);
        final sender = await contactRepo.getContact(comment.senderPeerId);
        if (post != null &&
            !post.isIncoming &&
            sender != null &&
            !sender.isArchived &&
            notificationService != null) {
          await notificationService!.showNotification(
            title: sender.username,
            body: comment.body,
            payload: NotificationRouteTarget.postComment(
              postId: comment.postId,
              commentId: comment.id,
            ).toPayload(),
          );
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'POST_COMMENT_RECEIVED',
          details: {
            'postId': comment.postId,
            'commentId': comment.id,
            'transport': message.transport ?? 'unknown',
          },
        );
        _commentController.add(comment);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_COMMENT_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
