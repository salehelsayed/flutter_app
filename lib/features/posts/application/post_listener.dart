import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/features/posts/application/ios_thoughts_switch.dart';
import 'package:flutter_app/core/config/thoughts_feature_flags.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/friend_thought_card_registry.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/early_thought_retractions.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_retract_use_case.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_use_case.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_thought_view_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/push/application/notification_preview_copy.dart';

class PostListener {
  final Stream<ChatMessage> postCreateStream;

  /// Authors deleting a thought every friend was sent.
  final Stream<ChatMessage> postRetractStream;
  final Stream<ChatMessage> postViewStream;
  final Future<String?> Function()? getOwnPeerId;
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

  /// Which thought card each friend holds, shared with the background isolate.
  final FriendThoughtCardRegistry? friendThoughtCards;
  final Future<PostMediaAttachmentModel> Function({
    required PostMediaAttachmentModel attachment,
    required String postId,
  })?
  hydratePostMediaFn;

  /// Retractions that beat their thought here, so the thought stays out.
  final EarlyThoughtRetractions earlyRetractions;

  StreamSubscription<ChatMessage>? _subscription;
  StreamSubscription<ChatMessage>? _retractSubscription;
  StreamSubscription<ChatMessage>? _viewSubscription;
  final _postController = StreamController<PostModel>.broadcast();

  PostListener({
    required this.postCreateStream,
    this.postRetractStream = const Stream<ChatMessage>.empty(),
    this.postViewStream = const Stream<ChatMessage>.empty(),
    this.getOwnPeerId,
    required this.postRepo,
    required this.contactRepo,
    this.bridge,
    this.mediaFileManager,
    this.getOwnMlKemSecretKey,
    this.notificationService,
    this.isAppForegroundActive,
    this.remoteNotificationGate,
    this.friendThoughtCards,
    this.hydratePostMediaFn,
    DateTime Function()? nowProvider,
  }) : now = nowProvider ?? DateTime.now,
       earlyRetractions = EarlyThoughtRetractions(nowProvider: nowProvider);

  Stream<PostModel> get incomingPostStream => _postController.stream;

  void start() {
    if (_subscription != null) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(
        publishThoughtsSwitchForIos(
          FlutterSecureKeyStore(appleAccessGroup: mknoonSharedAppleAccessGroup),
        ),
      );
    }
    _subscription = postCreateStream.listen(_onMessage);
    _retractSubscription = postRetractStream.listen(_onRetract);
    _viewSubscription = postViewStream.listen(_onView);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _retractSubscription?.cancel();
    _retractSubscription = null;
    _viewSubscription?.cancel();
    _viewSubscription = null;
  }

  Future<void> _onView(ChatMessage message) async {
    try {
      final localPeerId = await getOwnPeerId?.call();
      final secret = await getOwnMlKemSecretKey?.call();
      final crypto = bridge;
      if (localPeerId == null || secret == null || crypto == null) return;
      await handleIncomingThoughtView(
        message: message,
        localPeerId: localPeerId,
        postRepo: postRepo,
        contactRepo: contactRepo,
        bridge: crypto,
        ownMlKemSecretKey: secret,
        nowProvider: now,
      );
      await _maybeConfirmDirectNonce(message, ok: true);
    } catch (error) {
      await _maybeConfirmDirectNonce(message, ok: false);
      emitFlowEvent(
        layer: 'FL',
        event: 'THOUGHT_VIEW_RECEIVE_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  Future<void> _onRetract(ChatMessage message) async {
    try {
      final (result, postId) = await handleIncomingPostRetract(
        message: message,
        postRepo: postRepo,
        mediaFileManager: mediaFileManager,
        earlyRetractions: earlyRetractions,
      );
      if (result == HandleIncomingPostRetractResult.thoughtDeleted &&
          postId != null) {
        await _cancelCard(NotificationRouteTarget.post(postId).toPayload());
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
    var confirmed = false;
    Future<void> confirmStored() async {
      if (confirmed) return;
      confirmed = true;
      await _maybeConfirmDirectNonce(message, ok: true);
    }

    // Media downloads can outlast the sender's ack window and the process
    // itself; the thought, its media keys and its media kind are saved, so
    // the ack and the friend's card both go out now.
    Future<void> durablyStored(PostModel post, {required bool created}) async {
      await confirmStored();
      if (created) await _announce(post);
    }

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
        onDurablyStored: durablyStored,
        earlyRetractions: earlyRetractions,
      );
    } catch (error) {
      // Nothing final happened, so the sender keeps custody: Go withholds its
      // ack and the sender falls back to the relay inbox.
      if (!confirmed) await _maybeConfirmDirectNonce(message, ok: false);
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_LISTENER_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      return;
    }
    // Every returned result is final (stored, duplicate, or rejected for
    // good), so the sender's Go node may release its ack.
    await confirmStored();
    final (result, post) = outcome;
    switch (result) {
      case HandleIncomingPostResult.postCreated when post != null:
        if (_expired(post)) {
          await _cancelCard(NotificationRouteTarget.post(post.id).toPayload());
          return;
        }
        // Cancelling the subscription does not join an in-flight receive.
        // Its durable ACK still settles, but disposal ends stream publication.
        if (!_postController.isClosed) _postController.add(post);
        return;
      case HandleIncomingPostResult.expired:
      case HandleIncomingPostResult.superseded:
      case HandleIncomingPostResult.retracted:
        // The push isolate may have shown this thought's card already; the
        // thought is not kept, so the card goes.
        if (post != null) {
          await _cancelCard(NotificationRouteTarget.post(post.id).toPayload());
        }
      default:
        break;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_LISTENER_IGNORED',
      details: {'result': result.name},
    );
  }

  /// Shows the friend's card for a thought just stored, unless the app is in
  /// the foreground, thoughts are switched off, the sender is archived, a push
  /// already announced it, or
  /// a newer thought from the friend holds the card. Claiming the card retires
  /// the friend's older one either way. A card that cannot be shown must not
  /// stop the media download that follows.
  Future<void> _announce(PostModel post) async {
    final cardKey = NotificationRouteTarget.post(post.id).toPayload();
    try {
      final sender = await contactRepo.getContact(post.senderPeerId);
      final current =
          !post.isIncoming ||
          await _claimFriendsCard(post.senderPeerId, cardKey);
      final showsCard =
          thoughtsEnabled &&
          current &&
          sender != null &&
          !sender.isArchived &&
          notificationService != null &&
          post.isIncoming &&
          !(await isAppForegroundActive?.call() ?? false);
      final announcedByPush =
          showsCard &&
          (await remoteNotificationGate?.consumeIfRecentAnnouncement(
                payload: cardKey,
                messageId: post.eventId,
              ) ??
              false);
      if (showsCard && !announcedByPush) {
        await notificationService!.showThoughtNotification(
          postId: post.id,
          title: localizedThoughtNotificationTitle(sender.username),
          body: localizedThoughtNotificationBody(
            text: post.text,
            mediaKind: post.mediaKind,
            mediaCount: post.media.length,
          ),
          expiresAt: DateTime.parse(post.expiresAt),
        );
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_LISTENER_CARD_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  /// One card per friend: claiming the friend's card for this thought retires
  /// the card it replaces, whichever isolate showed it. Returns false when a
  /// newer thought from the friend already holds the card.
  Future<bool> _claimFriendsCard(String senderPeerId, String cardKey) async {
    final registry = friendThoughtCards;
    if (registry == null) return true;
    try {
      final claim = await registry.claim(
        senderPeerId: senderPeerId,
        cardKey: cardKey,
      );
      final retired = claim.retired;
      if (retired != null) await _cancelCard(retired);
      return claim.current;
    } catch (error) {
      // A stale card must not stop the new thought from reaching Orbit.
      emitFlowEvent(
        layer: 'FL',
        event: 'POST_LISTENER_RETIRE_FAILED',
        details: {'errorType': error.runtimeType.toString()},
      );
      return true;
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

  Future<void> _cancelCard(String cardKey) async {
    final notifications = notificationService;
    if (notifications is ConversationNotificationCancellation) {
      await (notifications as ConversationNotificationCancellation)
          .cancelConversationNotification(cardKey);
    }
  }

  bool _expired(PostModel post) {
    final expiry = DateTime.tryParse(post.expiresAt);
    return expiry == null || !expiry.isAfter(now().toUtc());
  }
}
