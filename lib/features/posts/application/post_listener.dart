import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_retract_use_case.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/push/application/notification_preview_copy.dart';

class PostListener {
  final Stream<ChatMessage> postCreateStream;

  /// Authors deleting a thought every friend was sent.
  final Stream<ChatMessage> postRetractStream;
  final PostRepository postRepo;
  final ContactRepository contactRepo;
  final Bridge? bridge;
  final MediaFileManager? mediaFileManager;
  final DateTime Function() now;
  final Future<String?> Function()? getOwnMlKemSecretKey;
  final NotificationService? notificationService;
  final Future<bool> Function()? isAppForegroundActive;

  /// The background push isolate marks each thought card it shows here, so
  /// the inbox drain that follows does not post a second one.
  final RecentRemoteNotificationGate? remoteNotificationGate;
  final Future<PostMediaAttachmentModel> Function({
    required PostMediaAttachmentModel attachment,
    required String postId,
  })?
  hydratePostMediaFn;

  StreamSubscription<ChatMessage>? _subscription;
  StreamSubscription<ChatMessage>? _retractSubscription;
  final _postController = StreamController<PostModel>.broadcast();

  PostListener({
    required this.postCreateStream,
    this.postRetractStream = const Stream<ChatMessage>.empty(),
    required this.postRepo,
    required this.contactRepo,
    this.bridge,
    this.mediaFileManager,
    this.getOwnMlKemSecretKey,
    this.notificationService,
    this.isAppForegroundActive,
    this.remoteNotificationGate,
    this.hydratePostMediaFn,
    DateTime Function()? nowProvider,
  }) : now = nowProvider ?? DateTime.now;

  Stream<PostModel> get incomingPostStream => _postController.stream;

  void start() {
    if (_subscription != null) return;
    _subscription = postCreateStream.listen(_onMessage);
    _retractSubscription = postRetractStream.listen(_onRetract);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _retractSubscription?.cancel();
    _retractSubscription = null;
  }

  Future<void> _onRetract(ChatMessage message) async {
    try {
      final (result, postId) = await handleIncomingPostRetract(
        message: message,
        postRepo: postRepo,
        mediaFileManager: mediaFileManager,
      );
      if (result == HandleIncomingPostRetractResult.thoughtDeleted &&
          postId != null) {
        await _cancelThoughtCard(postId);
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_LISTENER_RETRACT_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  void dispose() {
    stop();
    _postController.close();
  }

  Future<void> _onMessage(ChatMessage message) async {
    final (HandleIncomingPostResult, PostModel?) outcome;
    try {
      final ownMlKemSecretKey = getOwnMlKemSecretKey == null
          ? null
          : await getOwnMlKemSecretKey!();
      outcome = await handleIncomingPost(
        message: message,
        postRepo: postRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        mediaFileManager: mediaFileManager,
        ownMlKemSecretKey: ownMlKemSecretKey,
        hydratePostMediaFn: hydratePostMediaFn,
        nowProvider: now,
      );
    } catch (error) {
      // Nothing final happened, so the sender keeps custody: Go withholds its
      // ack and the sender falls back to the relay inbox.
      await _maybeConfirmDirectNonce(message, ok: false);
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_LISTENER_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      return;
    }
    // Every returned result is final (stored, duplicate, or rejected for
    // good), so the sender's Go node may release its ack.
    await _maybeConfirmDirectNonce(message, ok: true);
    final (result, post) = outcome;
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
      final announcedByPush =
          await remoteNotificationGate?.consumeIfRecentAnnouncement(
            payload: NotificationRouteTarget.post(post.id).toPayload(),
            messageId: post.eventId,
          ) ??
          false;
      if (!announcedByPush) {
        await notificationService!.showThoughtNotification(
          postId: post.id,
          title: localizedThoughtNotificationTitle(sender.username),
          body: localizedThoughtNotificationBody(
            text: post.text,
            mediaKind: post.mediaKind,
            mediaCount: post.media.length,
          ),
        );
      }
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

  /// Releases (ok) or withholds (not ok) the deferred direct ack the sender's
  /// Go node is waiting for. A thought without a confirmNonce, such as a
  /// relay-inbox replay, needs nothing.
  Future<void> _maybeConfirmDirectNonce(
    ChatMessage message, {
    required bool ok,
  }) async {
    final nonce = message.confirmNonce;
    final bridge = this.bridge;
    if (bridge == null || nonce == null || nonce.isEmpty) return;
    try {
      await callP2PConfirmDirectMessage(bridge, nonce: nonce, ok: ok);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_LISTENER_CONFIRM_NONCE_ERROR',
        details: {'nonce': nonce, 'error': error.toString(), 'ok': ok},
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

  bool _expired(PostModel post) {
    final expiry = DateTime.tryParse(post.expiresAt);
    return expiry == null || !expiry.isAfter(now().toUtc());
  }
}
