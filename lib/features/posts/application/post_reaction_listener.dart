import 'dart:async';

import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_reaction_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

class PostReactionListener {
  final Stream<ChatMessage> postReactionStream;
  final Stream<ChatMessage> postCommentReactionStream;
  final PostRepository postRepo;
  final ContactRepository contactRepo;
  final NotificationService? notificationService;

  StreamSubscription<ChatMessage>? _postReactionSubscription;
  StreamSubscription<ChatMessage>? _commentReactionSubscription;
  final _postReactionController =
      StreamController<PostReactionModel>.broadcast();
  final _commentReactionController =
      StreamController<PostCommentReactionModel>.broadcast();

  PostReactionListener({
    required this.postReactionStream,
    required this.postCommentReactionStream,
    required this.postRepo,
    required this.contactRepo,
    this.notificationService,
  });

  Stream<PostReactionModel> get incomingPostReactionStream =>
      _postReactionController.stream;
  Stream<PostCommentReactionModel> get incomingCommentReactionStream =>
      _commentReactionController.stream;

  void start() {
    if (_postReactionSubscription != null ||
        _commentReactionSubscription != null) {
      return;
    }
    _postReactionSubscription = postReactionStream.listen(_onPostReaction);
    _commentReactionSubscription = postCommentReactionStream.listen(
      _onCommentReaction,
    );
  }

  void stop() {
    _postReactionSubscription?.cancel();
    _postReactionSubscription = null;
    _commentReactionSubscription?.cancel();
    _commentReactionSubscription = null;
  }

  void dispose() {
    stop();
    _postReactionController.close();
    _commentReactionController.close();
  }

  Future<void> _onPostReaction(ChatMessage message) async {
    try {
      final (result, reaction) = await handleIncomingPostReaction(
        message: message,
        postRepo: postRepo,
        contactRepo: contactRepo,
      );
      if (result == HandleIncomingPostReactionResult.reactionApplied &&
          reaction != null) {
        final post = await postRepo.getPost(reaction.postId);
        final sender = await contactRepo.getContact(reaction.senderPeerId);
        if (post != null &&
            !post.isIncoming &&
            sender != null &&
            !sender.isArchived &&
            notificationService != null &&
            reaction.isActive) {
          await notificationService!.showNotification(
            title: sender.username,
            body: 'Hearted your post',
            payload: NotificationRouteTarget.post(reaction.postId).toPayload(),
          );
        }
        _postReactionController.add(reaction);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_REACTION_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onCommentReaction(ChatMessage message) async {
    try {
      final (result, reaction) = await handleIncomingPostCommentReaction(
        message: message,
        postRepo: postRepo,
        contactRepo: contactRepo,
      );
      if (result == HandleIncomingPostCommentReactionResult.reactionApplied &&
          reaction != null) {
        _commentReactionController.add(reaction);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_COMMENT_REACTION_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
