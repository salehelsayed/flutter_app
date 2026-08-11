import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_reaction_use_case.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';

typedef ResolveReactionNotificationDependencies =
    ({
      NotificationService service,
      ActiveConversationTracker tracker,
      AppLifecycleState Function() lifecycle,
      NotificationToneTracker toneTracker,
      ResolveDurableNotificationCoordinator durableCoordinatorResolver,
      ConsumeRecentRemoteNotificationAnnouncement consumeRemoteAnnouncement,
      MarkRecentRemoteNotificationAnnouncement markRemoteAnnouncement,
      LoadConversationNotificationSnapshot loadSnapshot,
    })?
    Function(String contactPeerId);

/// Listener service that monitors P2P messages for emoji reactions.
///
/// Subscribes to the typed reaction stream (from IncomingMessageRouter),
/// calls handleIncomingReaction, and broadcasts persisted
/// MessageReactions to the UI layer.
class ReactionListener {
  final Stream<ChatMessage> reactionStream;
  final MessageRepository messageRepo;
  final ReactionRepository reactionRepo;
  final ContactRepository contactRepo;

  /// 361: shared physical->logical reverse authority (null = incumbent).
  final DirectTransportAuthorityResolver? transportAuthority;
  final Bridge bridge;
  final Future<String?> Function() getOwnMlKemSecretKey;
  final ResolveReactionNotificationDependencies?
  resolveNotificationDependencies;
  final StageDirectReactionNotificationDisplayCustody?
  stageNotificationDisplayCustody;
  final PromoteDirectReactionNotificationDisplayCustody?
  promoteNotificationDisplayCustody;
  final CommitDirectReactionNotificationRemove? commitNotificationRemove;
  final Future<void> Function()? retryNotificationDisplays;

  StreamSubscription<ChatMessage>? _subscription;
  final _reactionController = StreamController<MessageReaction>.broadcast();
  final _reactionChangeController =
      StreamController<ReactionChange>.broadcast();

  ReactionListener({
    required this.reactionStream,
    required this.messageRepo,
    required this.reactionRepo,
    required this.contactRepo,
    this.transportAuthority,
    required this.bridge,
    required this.getOwnMlKemSecretKey,
    this.resolveNotificationDependencies,
    this.stageNotificationDisplayCustody,
    this.promoteNotificationDisplayCustody,
    this.commitNotificationRemove,
    this.retryNotificationDisplays,
  });

  /// Stream of incoming reactions for the UI.
  Stream<MessageReaction> get incomingReactionStream =>
      _reactionController.stream;

  /// Stream of incoming reaction changes, including removals.
  Stream<ReactionChange> get incomingReactionChangeStream =>
      _reactionChangeController.stream;

  /// Broadcasts a reaction change that was already persisted by the shared
  /// replay pipeline (relay, staged push, or stage-error fallback).
  ///
  /// Those paths intentionally bypass [_onMessage] so persistence and
  /// notification policy run exactly once. They still need to reach mounted
  /// conversations through the same UI stream as a legacy raw-listener event.
  void publishPersistedChange(ReactionChange change) {
    if (_reactionChangeController.isClosed) return;
    if (change.type == ReactionChangeType.upserted &&
        change.reaction != null &&
        !_reactionController.isClosed) {
      _reactionController.add(change.reaction!);
    }
    _reactionChangeController.add(change);
  }

  /// Starts listening for incoming reactions.
  void start() {
    if (_subscription != null) return;

    emitFlowEvent(layer: 'FL', event: 'REACTION_LISTENER_START', details: {});

    _subscription = reactionStream.listen(
      _onMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'REACTION_LISTENER_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'REACTION_LISTENER_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  /// Stops listening.
  void stop() {
    emitFlowEvent(layer: 'FL', event: 'REACTION_LISTENER_STOP', details: {});

    _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    stop();
    _reactionController.close();
    _reactionChangeController.close();
  }

  Future<void> _onMessage(ChatMessage message) async {
    try {
      // Check if sender is blocked. 361: with a transport authority present
      // the blocked policy applies to the RESOLVED logical contact.
      final senderPeerId = message.from;
      var blockedLookupPeerId = senderPeerId;
      if (transportAuthority != null) {
        final resolution = await transportAuthority!
            .resolveDirectTransportAuthority(senderPeerId);
        if (resolution.authorized) {
          blockedLookupPeerId = resolution.contactAccountPeerId!;
        }
      }
      final senderContact = await contactRepo.getContact(blockedLookupPeerId);
      if (senderContact != null && senderContact.isBlocked) {
        emitFlowEvent(
          layer: 'FL',
          event: 'REACTION_LISTENER_BLOCKED_REJECT',
          details: {
            'from': senderPeerId.length > 10
                ? senderPeerId.substring(0, 10)
                : senderPeerId,
          },
        );
        return;
      }

      final ownSecretKey = await getOwnMlKemSecretKey();
      final notify = resolveNotificationDependencies?.call(message.from);

      final (result, change) = await handleIncomingReaction(
        message: message,
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        transportAuthority: transportAuthority,
        bridge: bridge,
        ownMlKemSecretKey: ownSecretKey,
        notificationService: notify?.service,
        conversationTracker: notify?.tracker,
        getAppLifecycleState: notify?.lifecycle,
        notificationToneTracker: notify?.toneTracker,
        durableNotificationCoordinatorResolver:
            notify?.durableCoordinatorResolver,
        consumeRecentRemoteNotificationAnnouncement:
            notify?.consumeRemoteAnnouncement,
        markRecentRemoteNotificationAnnouncement:
            notify?.markRemoteAnnouncement,
        loadConversationNotificationSnapshot: notify?.loadSnapshot,
        stageNotificationDisplayCustody: stageNotificationDisplayCustody,
        promoteNotificationDisplayCustody: promoteNotificationDisplayCustody,
        commitNotificationRemove: commitNotificationRemove,
        retryNotificationDisplays: retryNotificationDisplays,
      );

      if (result == HandleReactionResult.success && change != null) {
        if (change.type == ReactionChangeType.upserted &&
            change.reaction != null) {
          final reaction = change.reaction!;
          emitFlowEvent(
            layer: 'FL',
            event: 'REACTION_LISTENER_NEW_REACTION',
            details: {
              'id': reaction.id.length > 8
                  ? reaction.id.substring(0, 8)
                  : reaction.id,
              'emoji': reaction.emoji,
            },
          );
        }
        publishPersistedChange(change);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
