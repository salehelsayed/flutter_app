import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/push/application/notification_preview_copy.dart';

class PostListener {
  final Stream<ChatMessage> postCreateStream;
  final PostRepository postRepo;
  final ContactRepository contactRepo;
  final Bridge? bridge;
  final MediaFileManager? mediaFileManager;
  final DateTime Function() now;
  final Future<String?> Function()? getOwnMlKemSecretKey;
  final NotificationService? notificationService;
  final Future<bool> Function()? isAppForegroundActive;
  final Future<PostMediaAttachmentModel> Function({
    required PostMediaAttachmentModel attachment,
    required String postId,
  })?
  hydratePostMediaFn;

  StreamSubscription<ChatMessage>? _subscription;
  final _postController = StreamController<PostModel>.broadcast();

  PostListener({
    required this.postCreateStream,
    required this.postRepo,
    required this.contactRepo,
    this.bridge,
    this.mediaFileManager,
    this.getOwnMlKemSecretKey,
    this.notificationService,
    this.isAppForegroundActive,
    this.hydratePostMediaFn,
    DateTime Function()? nowProvider,
  }) : now = nowProvider ?? DateTime.now;

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
      mediaFileManager: mediaFileManager,
      ownMlKemSecretKey: ownMlKemSecretKey,
      hydratePostMediaFn: hydratePostMediaFn,
      nowProvider: now,
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
    if (_expired(post)) return;
    if (post.isIncoming) await _retireOlderThoughtCards(post);
    if (sender != null &&
        !sender.isArchived &&
        notificationService != null &&
        post.isIncoming &&
        !(await isAppForegroundActive?.call() ?? false)) {
      await notificationService!.showThoughtNotification(
        postId: post.id,
        title: localizedThoughtNotificationTitle(post.authorUsername),
        body: _thoughtNotificationBody(post),
      );
    }
    if (_expired(post)) {
      await _cancelThoughtCard(post.id);
      return;
    }
    _postController.add(post);
  }

  /// One card per friend: the newest thought replaces the friend's older ones.
  Future<void> _retireOlderThoughtCards(PostModel post) async {
    if (notificationService is! ConversationNotificationCancellation) return;
    try {
      for (final older in await postRepo.loadFeed()) {
        if (older.id != post.id &&
            older.isIncoming &&
            older.authorPeerId == post.authorPeerId) {
          await _cancelThoughtCard(older.id);
        }
      }
    } catch (error) {
      // A stale card must not stop the new thought from reaching Orbit.
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_LISTENER_RETIRE_FAILED',
        details: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  Future<void> _cancelThoughtCard(String postId) async {
    final notifications = notificationService;
    if (notifications is ConversationNotificationCancellation) {
      await (notifications as ConversationNotificationCancellation)
          .cancelConversationNotification(
            NotificationRouteTarget.post(postId).toPayload(),
          );
    }
  }

  static String _thoughtNotificationBody(PostModel post) {
    final text = post.text.trim();
    if (text.isNotEmpty) return text;
    return switch (post.mediaKind) {
      'image' => localizedNotificationPhoto(1),
      'image_carousel' => localizedNotificationPhoto(post.media.length),
      'video' => localizedNotificationVideo(1),
      'voice' => localizedNotificationVoiceMessage(),
      _ => localizedNotificationMedia(),
    };
  }

  bool _expired(PostModel post) {
    final expiry = DateTime.tryParse(post.expiresAt);
    return expiry == null || !expiry.isAfter(now().toUtc());
  }
}
